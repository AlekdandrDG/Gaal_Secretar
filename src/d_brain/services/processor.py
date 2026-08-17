"""Claude processing service."""

import json
import logging
import os
import re
import shutil
import subprocess
from datetime import date
from pathlib import Path
from typing import Any

from d_brain.services.session import SessionStore

logger = logging.getLogger(__name__)

DEFAULT_TIMEOUT = 1200  # 20 minutes


class ClaudeProcessor:
    """Service for triggering Claude Code processing."""

    def __init__(self, vault_path: Path, todoist_api_key: str = "") -> None:
        self.vault_path = Path(vault_path)
        self.todoist_api_key = todoist_api_key
        self._mcp_config_path = (self.vault_path.parent / "mcp-config.json").resolve()

    def _get_claude_bin(self) -> str:
        """Find claude binary path.

        Override with CLAUDE_BIN if the CLI lives somewhere unusual.
        """
        candidates = [
            os.environ.get("CLAUDE_BIN"),
            shutil.which("claude"),
            os.path.expanduser("~/.local/bin/claude"),
            os.path.expanduser("~/bin/claude"),
        ]
        for path in candidates:
            if path and os.path.isfile(path):
                return path
        return "claude"

    def _build_env(self) -> dict:
        """Build environment for Claude subprocess."""
        env = os.environ.copy()
        # Сломан IPv6 на сервере: Node в CLI виснет на AAAA-резолве — форсируем IPv4.
        env["NODE_OPTIONS"] = (
            env.get("NODE_OPTIONS", "") + " --dns-result-order=ipv4first"
        ).strip()
        if "HOME" not in env:
            env["HOME"] = str(Path("~").expanduser())
        home = env.get("HOME", "")
        extra_paths = [f"{home}/bin", f"{home}/.local/bin"]
        current_path = env.get("PATH", "")
        env["PATH"] = ":".join(extra_paths) + (":" + current_path if current_path else "")
        if self.todoist_api_key:
            env["TODOIST_API_KEY"] = self.todoist_api_key
        return env

    def _get_session_context(self, user_id: int) -> str:
        if user_id == 0:
            return ""
        session = SessionStore(self.vault_path)
        today_entries = session.get_today(user_id)
        if not today_entries:
            return ""
        lines = ["=== TODAY'S SESSION ==="]
        for entry in today_entries[-10:]:
            ts = entry.get("ts", "")[11:16]
            entry_type = entry.get("type", "unknown")
            text = entry.get("text", "")[:80]
            if text:
                lines.append(f"{ts} [{entry_type}] {text}")
        lines.append("=== END SESSION ===\n")
        return "\n".join(lines)

    def _html_to_markdown(self, html: str) -> str:
        text = html
        text = re.sub(r"<b>(.*?)</b>", r"**\1**", text)
        text = re.sub(r"<i>(.*?)</i>", r"*\1*", text)
        text = re.sub(r"<code>(.*?)</code>", r"`\1`", text)
        text = re.sub(r"<s>(.*?)</s>", r"~~\1~~", text)
        text = re.sub(r"</?u>", "", text)
        text = re.sub(r'<a href="([^"]+)">([^<]+)</a>', r"[\2](\1)", text)
        return text

    def _run_claude(
        self, prompt: str, kind: str, user_id: int = 0
    ) -> tuple[str | None, str | None]:
        """Run claude --print with JSON output.

        Returns:
            (text, None) on success, (None, error) on failure.
        """
        claude_bin = self._get_claude_bin()
        env = self._build_env()
        result = subprocess.run(
            [
                claude_bin,
                "--print",
                "--dangerously-skip-permissions",
                "--output-format",
                "json",
                "-p",
                prompt,
            ],
            cwd=self.vault_path.parent,
            capture_output=True,
            text=True,
            timeout=DEFAULT_TIMEOUT,
            check=False,
            env=env,
        )
        if result.returncode != 0:
            error_detail = result.stderr.strip() or result.stdout.strip() or "unknown error"
            logger.error("Claude %s failed (rc=%d): %s", kind, result.returncode, error_detail)
            return None, error_detail
        out = result.stdout.strip()
        try:
            data = json.loads(out)
            return (data.get("result") or "").strip(), None
        except (json.JSONDecodeError, AttributeError):
            # fallback: непредвиденный формат — отдать как есть
            logger.warning("Claude %s: non-JSON output", kind)
            return out, None

    def _daily_sources_block(self, start: date, end: date) -> str:
        """Build an append-only «Источники» block linking daily files in range.

        Deterministic (no LLM): links only to files that actually exist,
        so drill-down from a summary can never hit a hallucinated path.
        """
        from datetime import timedelta

        links = []
        d = start
        while d <= end:
            if (self.vault_path / "daily" / f"{d.isoformat()}.md").exists():
                links.append(f"- [[daily/{d.isoformat()}]]")
            d += timedelta(days=1)
        if not links:
            return ""
        return "\n\n## Источники\n\n" + "\n".join(links) + "\n"

    def _save_weekly_summary(self, report_html: str, week_date: date) -> Path:
        from datetime import timedelta

        year, week, _ = week_date.isocalendar()
        filename = f"{year}-W{week:02d}-summary.md"
        summary_path = self.vault_path / "summaries" / filename
        content = self._html_to_markdown(report_html)
        sources = self._daily_sources_block(week_date - timedelta(days=7), week_date)
        frontmatter = f"""---
date: {week_date.isoformat()}
type: weekly-summary
week: {year}-W{week:02d}
---

"""
        summary_path.write_text(frontmatter + content + sources)
        logger.info("Weekly summary saved to %s", summary_path)
        return summary_path

    def _update_weekly_moc(self, summary_path: Path) -> None:
        moc_path = self.vault_path / "MOC" / "MOC-weekly.md"
        if moc_path.exists():
            content = moc_path.read_text()
            link = f"- [[summaries/{summary_path.name}|{summary_path.stem}]]"
            if summary_path.stem not in content:
                content = content.replace(
                    "## Previous Weeks\n",
                    f"## Previous Weeks\n\n{link}\n",
                )
                moc_path.write_text(content)

    def extract_events_from_file(self, file_path: Path) -> list[dict[str, Any]]:
        """Ask Claude to extract calendar events from a file as JSON.

        Claude's role: read the file and return structured data only.
        No calendar calls, no emails — just extraction.

        Returns:
            List of event dicts with keys: summary, start_time, end_time, description
        """
        today = date.today()
        abs_path = Path(file_path).resolve()

        prompt = (
            f"Сегодня {today}.\n\n"
            f"Прочти файл: {abs_path}\n\n"
            "Найди в нём события: встречи, поездки, авиа/ж.д. билеты, мероприятия, дедлайны.\n\n"
            "Правила:\n"
            "- Для каждого рейса/поезда: ОДНО событие. start_time = вылет/отправление, "
            "end_time = прилёт/прибытие, summary = маршрут + номер рейса/поезда.\n"
            "- Ж/Д БИЛЕТ: location = вокзал отправления (напр. \"Ленинградский вокзал, Москва\"). "
            "description ОБЯЗАТЕЛЬНО содержит № поезда, № вагона и место(а). "
            "Формат description: \"Поезд 780 · вагон 13 · место 034\".\n"
            "- АВИА БИЛЕТ: location = аэропорт вылета (название/код, напр. \"Пулково (LED), Санкт-Петербург\"). "
            "description ОБЯЗАТЕЛЬНО содержит авиакомпанию, номер рейса и аэропорты вылета→прилёта. "
            "Формат description: \"Аэрофлот · рейс SU6661 · LED→KGD\".\n"
            "- Если какое-то поле в билете не указано — пропусти его, не выдумывай.\n"
            "- Если время окончания неизвестно — start_time + 1 час\n"
            f"- Если год не указан — используй {today.year}\n"
            "- Если событий нет — верни пустой массив\n"
            "- ПОВТОРЯЮЩИЕСЯ события («каждый день», «ежедневно», «каждую среду», «по будням», «каждую неделю»): "
            "заполни поле recurrence массивом RRULE. start_time/end_time = первое вхождение.\n"
            "- «до <дата>» / «до следующей пятницы» → добавь UNTIL в RRULE (формат YYYYMMDDT000000Z, UTC).\n"
            f"- «до следующей <день недели>» считай от {today}. Примеры RRULE:\n"
            "  ежедневно до 12 июня: [\"RRULE:FREQ=DAILY;UNTIL=20260612T000000Z\"]\n"
            "  каждый будний день: [\"RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR\"]\n"
            "  каждую среду: [\"RRULE:FREQ=WEEKLY;BYDAY=WE\"]\n"
            "- Если событие РАЗОВОЕ — recurrence = пустой массив [].\n\n"
            "Верни ТОЛЬКО валидный JSON без markdown и пояснений:\n"
            "{\n"
            "  \"events\": [\n"
            "    {\n"
            "      \"summary\": \"название\",\n"
            "      \"start_time\": \"YYYY-MM-DDTHH:MM:SS\",\n"
            "      \"end_time\": \"YYYY-MM-DDTHH:MM:SS\",\n"
            "      \"description\": \"детали или пустая строка\",\n"
            "      \"location\": \"вокзал/аэропорт или пустая строка\",\n"
            "      \"recurrence\": []\n"
            "    }\n"
            "  ]\n"
            "}"
        )

        raw, error = self._run_claude(prompt, kind="calendar")
        if error is not None:
            raise RuntimeError(error)

        match = re.search(r"\{[\s\S]*\}", raw)
        if not match:
            raise ValueError(f"No JSON in Claude output: {raw[:200]}")

        data = json.loads(match.group())
        return data.get("events", [])

    _BINARY_SUFFIXES = {".pdf", ".jpg", ".jpeg", ".png", ".gif", ".webp"}

    @staticmethod
    def _read_calendar_keys(file_path: Path) -> set[str]:
        """Read already-added calendar event keys from file frontmatter or sidecar."""
        if file_path.suffix.lower() in ClaudeProcessor._BINARY_SUFFIXES:
            meta_path = file_path.with_suffix(file_path.suffix + ".calmeta")
            if not meta_path.exists():
                return set()
            try:
                import json as _json
                data = _json.loads(meta_path.read_text(encoding="utf-8"))
                return set(data.get("calendar_events", []))
            except Exception:
                return set()
        content = file_path.read_text(encoding="utf-8")
        m = re.search(r"^---\n(.*?)\n---", content, re.DOTALL)
        if not m:
            return set()
        keys: set[str] = set()
        in_block = False
        for line in m.group(1).splitlines():
            if line.strip() == "calendar_events:":
                in_block = True
            elif in_block:
                if line.startswith("  - "):
                    keys.add(line[4:].strip())
                else:
                    break
        return keys

    @staticmethod
    def _write_calendar_keys(file_path: Path, new_keys: list[str]) -> None:
        """Append new calendar event keys to file frontmatter or sidecar."""
        if file_path.suffix.lower() in ClaudeProcessor._BINARY_SUFFIXES:
            import json as _json
            meta_path = file_path.with_suffix(file_path.suffix + ".calmeta")
            existing: set[str] = set()
            if meta_path.exists():
                try:
                    data = _json.loads(meta_path.read_text(encoding="utf-8"))
                    existing = set(data.get("calendar_events", []))
                except Exception:
                    pass
            existing.update(new_keys)
            meta_path.write_text(
                _json.dumps({"calendar_events": sorted(existing)}, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
            return
        content = file_path.read_text(encoding="utf-8")
        key_lines = "\n".join(f"  - {k}" for k in new_keys)
        m = re.search(r"^---\n(.*?)\n---", content, re.DOTALL)
        if m:
            fm = m.group(1)
            if "calendar_events:" in fm:
                new_fm = fm + "\n" + key_lines
            else:
                new_fm = fm + "\ncalendar_events:\n" + key_lines
            content = content[: m.start(1)] + new_fm + content[m.end(1) :]
        else:
            header = f"---\ncalendar_events:\n{key_lines}\n---\n"
            content = header + content
        file_path.write_text(content, encoding="utf-8")

    def analyze_file_for_calendar(self, file_path: Path) -> dict[str, Any]:
        """Extract events from file and add them to Google Calendar.

        Flow:
          1. Claude extracts events as JSON (no calendar calls in prompt).
          2. Filter out events already added in previous runs (tracked in frontmatter).
          3. CalendarClient creates only new events via service account.
          4. Update frontmatter with newly added event keys.

        Args:
            file_path: Absolute path to image, PDF, or markdown file

        Returns:
            Report dict with 'report' or 'error' key
        """
        from d_brain.config import get_settings
        from d_brain.services.calendar import CalendarClient

        try:
            events = self.extract_events_from_file(file_path)
        except subprocess.TimeoutExpired:
            return {"error": "Timed out"}
        except FileNotFoundError:
            return {"error": "Claude CLI not installed"}
        except Exception as e:
            logger.exception("Event extraction failed")
            return {"error": str(e)}

        if not events:
            return {"report": "\U0001f4c5 <b>Результат</b>\n\nСобытий не найдено."}

        # Filter out events already added in previous runs
        already_added = self._read_calendar_keys(file_path)
        new_events = [
            ev for ev in events
            if f"{ev.get('summary', '')}|{ev.get('start_time', '')[:19]}" not in already_added
        ]
        skipped = len(events) - len(new_events)

        if not new_events:
            return {"report": "\U0001f4c5 <b>Результат</b>\n\nВсе события уже добавлены ранее."}

        settings = get_settings()
        if not Path(settings.google_credentials_path).exists():
            # Google Calendar is the one optional integration: without
            # credentials the bot keeps working, this feature just reports off.
            return {
                "error": (
                    "Google Calendar не настроен — нет файла credentials "
                    f"({settings.google_credentials_path}). "
                    "События не добавлены."
                )
            }
        try:
            cal = CalendarClient(
                settings.google_credentials_path, settings.google_calendar_id
            )
            created, failed = cal.create_events_from_list(new_events)
        except Exception as e:
            logger.exception("CalendarClient init or batch failed")
            return {"error": str(e)}

        if created:
            new_keys = [f"{ev['summary']}|{ev['start_time'][:19]}" for ev in created]
            try:
                self._write_calendar_keys(file_path, new_keys)
            except Exception:
                logger.exception("Failed to write calendar keys to frontmatter")

        lines = ["\U0001f4c5 <b>Результат</b>\n"]
        if skipped:
            lines.append(f"<i>Пропущено (уже добавлены): {skipped}</i>")
        if created:
            lines.append(f"<b>Добавлено: {len(created)}</b>")
            for ev in created:
                dt = ev["start_time"][:16].replace("T", " ")
                lines.append(f"\u2705 {ev['summary']} — {dt}")
                loc = (ev.get("location") or "").strip()
                if loc:
                    lines.append(f"   \U0001f4cd {loc}")
                desc = (ev.get("description") or "").strip()
                if desc:
                    lines.append(f"   <i>{desc}</i>")
        if failed:
            lines.append(f"\n<b>Ошибки ({len(failed)}):</b>")
            for ev, err in failed:
                lines.append(f"\u274c {ev['summary']}: <code>{err[:120]}</code>")

        return {"report": "\n".join(lines)}

    def _build_people_registry_block(self) -> str:
        """Regenerate the people registry from cards and return a prompt block."""
        try:
            from d_brain.services.people_registry import (
                registry_as_prompt,
                write_registry,
            )

            people_dir = self.vault_path / "people"
            out_path = self.vault_path / ".people-registry.json"
            entries = write_registry(people_dir, out_path)
            if not entries:
                return ""
            return (
                "=== PEOPLE REGISTRY (источник правды для матчинга имён) ===\n"
                + registry_as_prompt(entries)
                + "\n=== END PEOPLE REGISTRY ===\n"
            )
        except Exception:
            logger.exception("Failed to build people registry")
            return ""

    def process_daily(self, day: date | None = None) -> dict[str, Any]:
        """Process daily file with Claude."""
        if day is None:
            day = date.today()

        daily_file = self.vault_path / "daily" / f"{day.isoformat()}.md"

        if not daily_file.exists():
            logger.warning("No daily file for %s", day)
            return {"error": f"No daily file for {day}", "processed_entries": 0}

        people_block = self._build_people_registry_block()

        prompt = f"""Сегодня {day}. Выполни ежедневную обработку.

ОБЯЗАТЕЛЬНО ПЕРВЫМ ДЕЙСТВИЕМ прочитай инструкцию через Read:
  vault/.claude/skills/dbrain-processor/SKILL.md
Это твой свод правил обработки — работай строго по нему.

{people_block}

CRITICAL TOOL RULE — для работы с внешними сервисами используй mcp-cli через bash:
- Список инструментов: todoist-cli --help
- Создать задачи: todoist-cli add-tasks '{{"tasks": [{{"content": "...", "due_string": "today"}}]}}' 
- Найти задачи: todoist-cli find-tasks '{{"query": "..."}}'
- Никогда не пиши "нет доступа" — используй todoist-cli
- Если todoist-cli вернул ошибку — покажи ТОЧНУЮ ошибку в отчёте

CRITICAL OUTPUT FORMAT:
- Return ONLY raw HTML for Telegram (parse_mode=HTML)
- NO markdown: no **, no ## , no ```, no tables
- Start directly with 📊 <b>Обработка за {day}</b>
- Allowed tags: <b>, <i>, <code>, <s>, <u>
- If entries already processed, return status report in same HTML format"""

        try:
            text, error = self._run_claude(prompt, kind="process")
            if error is not None:
                return {"error": error, "processed_entries": 0}
            return {"report": text, "processed_entries": 1}
        except subprocess.TimeoutExpired:
            return {"error": "Processing timed out", "processed_entries": 0}
        except FileNotFoundError:
            return {"error": "Claude CLI not installed", "processed_entries": 0}
        except Exception as e:
            logger.exception("Unexpected error during processing")
            return {"error": str(e), "processed_entries": 0}

    def execute_prompt(self, user_prompt: str, user_id: int = 0) -> dict[str, Any]:
        """Execute arbitrary prompt with Claude."""
        today = date.today()

        session_context = self._get_session_context(user_id)

        prompt = f"""Ты - персональный ассистент d-brain.

CONTEXT:
- Текущая дата: {today}
- Vault path: {self.vault_path}

{session_context}Прежде чем работать с Todoist, ОБЯЗАТЕЛЬНО прочитай через Read справку:
  vault/.claude/skills/dbrain-processor/references/todoist.md
Следуй её правилам (формат ссылок, приоритеты, проекты, анти-паттерны).

CRITICAL TOOL RULE — для работы с Todoist используй todoist-cli через bash:

TODOIST:
- Создать задачи: todoist-cli add-tasks '{{"tasks": [{{"content": "...", "due_string": "today"}}]}}' 
- Найти задачи: todoist-cli find-tasks '{{"query": "..."}}'
- Никогда не пиши "нет доступа" — используй todoist-cli
- Если todoist-cli вернул ошибку — покажи ТОЧНУЮ ошибку в отчёте

USER REQUEST:
{user_prompt}

CRITICAL OUTPUT FORMAT — ТОЛЬКО сводка того, ЧТО СОЗДАНО (как для событий календаря):
- Return ONLY raw HTML for Telegram (parse_mode=HTML)
- NO markdown: no **, no ##, no ```, no tables, no -
- Allowed tags: <b>, <i>, <code>, <s>, <u>
- НЕ выдавай полный аналитический отчёт (цели, мысли, инсайты, планы) — его бот присылает по графику
- Только перечисли конкретно созданные/изменённые сущности

ФОРМАТ ОТВЕТА (строго):
- Первая строка: <b>✅ Создано: N</b>  (N = число созданных задач; если 0 — <b>ℹ️ Задачи не создавались</b>)
- Далее по одной строке на каждую созданную задачу: ✅ {{текст задачи}} — {{срок, если есть}}
- Если что-то изменено/закрыто, а не создано — отдельными строками с префиксом ✏️ (изменено) или ☑️ (закрыто)
- Если todoist-cli вернул ошибку — строка ❌ с ТОЧНЫМ текстом ошибки
- Никакого вступления и заключения, только заголовок + список

EXECUTION:
1. Analyze the request
2. Use todoist-cli for Todoist, read/write vault files directly
3. Верни ТОЛЬКО краткую сводку созданного по формату выше (не отчёт)"""

        try:
            text, error = self._run_claude(prompt, kind="do", user_id=user_id)
            if error is not None:
                return {"error": error, "processed_entries": 0}
            return {"report": text, "processed_entries": 1}
        except subprocess.TimeoutExpired:
            return {"error": "Execution timed out", "processed_entries": 0}
        except FileNotFoundError:
            return {"error": "Claude CLI not installed", "processed_entries": 0}
        except Exception as e:
            logger.exception("Unexpected error during execution")
            return {"error": str(e), "processed_entries": 0}

    def generate_weekly(self) -> dict[str, Any]:
        """Generate weekly digest with Claude."""
        today = date.today()

        from datetime import timedelta
        week_ago = (today - timedelta(days=7)).isoformat()
        today_iso = today.isoformat()
        prompt = f"""Сегодня {today_iso}. Сгенерируй недельный дайджест за период {week_ago}..{today_iso}.

CRITICAL TOOL RULE — для Todoist используй todoist-cli через bash:
- Закрытые задачи за неделю: todoist-cli find-completed-tasks '{{"since": "{week_ago}T00:00:00Z", "until": "{today_iso}T23:59:59Z"}}'
- Активные на 7 дней: todoist-cli find-tasks-by-date '{{"startDate": "today", "daysCount": 7}}'
- Никогда не пиши "нет доступа" — используй todoist-cli
- При ошибке — покажи ТОЧНЫЙ текст

WORKFLOW:
1. Прочитай vault/daily/*.md за период {week_ago}..{today_iso}
2. find-completed-tasks за указанный диапазон
3. goals/3-weekly.md — прогресс по ONE Big Thing
5. vault/MEMORY.md — Active Context, Pipeline
6. ДОСТИЖЕНИЯ: Прочитай vault/.claude/skills/dbrain-processor/references/achievements.md и собери:
   - все маркеры [achievement:*] из daily/*.md за период (префикс 🏆)
   - значимые закрытые Todoist задачи (префикс ✅)
   - значимые события календаря если есть (префикс 📅)
   Распредели по 10 категориям из achievements.md и выведи в секции "🏆 Достижения за период"
7. ДНИ РОЖДЕНИЯ: Прочитай все vault/people/*.md, найди записи где `birthday:` попадает в окно следующие 14 дней от сегодня. Для каждого:
   - вычислить дней до ДР
   - возраст в этом году
   - если есть vault/gifts/{{slug}}.md — подтянуть последние 2-3 идеи подарка / зафиксированных желания
   Сгруппировать по близости: ⚠️ ≤7 дней / 📅 8-14 дней
8. Сгенерируй HTML

OUTPUT TEMPLATE (Telegram parse_mode=HTML):

📅 <b>Недельный дайджест: {week_ago} — {today_iso}</b>

<b>🎯 ONE Big Thing</b>
статус достижения цели недели

<b>✅ Закрыто задач:</b> N
• имя задачи (закрыта дата)

<b>📓 Captured:</b> мыслей M, новых карточек K

<b>🏆 Достижения за период:</b>
(категории по achievements.md, только непустые, сортировка по количеству)

<b>🎂 Дни рождения близких (ближайшие 14 дней):</b>
⚠️ через X дней — Имя ({{age}} лет) — топ идея подарка
(показывать только если есть кандидаты; иначе скрыть секцию)

<b>🔥 Победы недели</b>

<b>⚠️ Висит без движения</b>

<b>🏢 Pipeline / клиенты</b>

<b>⚡ Фокус следующей недели</b>

CRITICAL FORMAT:
- ONLY raw HTML, NO markdown (**, ##, triple-backtick, tables)
- Allowed tags: <b>, <i>, <code>, <s>, <u>
- Начни вывод СРАЗУ с 📅 — без преамбулы и размышлений
- Telegram limit 4096 — компактно"""

        try:
            output, error = self._run_claude(prompt, kind="weekly")
            if error is not None:
                logger.error("Weekly digest failed: %s", error)
                return {"error": error, "processed_entries": 0}

            try:
                summary_path = self._save_weekly_summary(output, today)
                self._update_weekly_moc(summary_path)
            except Exception as e:
                logger.warning("Failed to save weekly summary: %s", e)

            return {"report": output, "processed_entries": 1}
        except subprocess.TimeoutExpired:
            return {"error": "Weekly digest timed out", "processed_entries": 0}
        except FileNotFoundError:
            return {"error": "Claude CLI not installed", "processed_entries": 0}
        except Exception as e:
            logger.exception("Unexpected error during weekly digest")
            return {"error": str(e), "processed_entries": 0}
