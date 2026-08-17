"""Process menu handler - inline keyboard after pressing Обработать."""

import asyncio
import logging
from datetime import date
from pathlib import Path

from aiogram import Router
from aiogram.types import CallbackQuery

from d_brain.bot.formatters import format_process_report, split_long_message
from d_brain.config import get_settings
from d_brain.services.git import VaultGit
from d_brain.services.processor import ClaudeProcessor

router = Router(name="process_menu")
logger = logging.getLogger(__name__)


async def _run_with_progress(status_msg, coro) -> dict:
    task = asyncio.create_task(coro)
    elapsed = 0
    while not task.done():
        await asyncio.sleep(30)
        elapsed += 30
        if not task.done():
            try:
                await status_msg.edit_text(f"⏳ Обрабатываю... ({elapsed // 60}m {elapsed % 60}s)")
            except Exception:
                pass
    return await task


@router.callback_query(lambda c: c.data and c.data.startswith("pmenu:"))
async def handle_process_menu(callback: CallbackQuery) -> None:
    if not callback.data or not callback.message or not callback.from_user:
        return

    action = callback.data[6:]
    user_id = callback.from_user.id
    await callback.answer()

    settings = get_settings()
    processor = ClaudeProcessor(settings.vault_path, settings.todoist_api_key)
    today = date.today()
    today_iso = today.isoformat()
    daily_file: Path = settings.vault_path / "daily" / f"{today_iso}.md"

    if action == "tasks":
        await callback.message.edit_text("⏳ Задачи → Todoist...")
        tasks_prompt = (
            f"Прочитай vault/daily/{today_iso}.md. Извлеки actionable-задачи "
            "(что нужно сделать) — мысли, идеи и рефлексии игнорируй, их обрабатывает "
            "кнопка «Память».\n"
            "ВАЖНО против дублей: обрабатывай ТОЛЬКО записи (блоки '## HH:MM [тип]'), "
            "в заголовке которых НЕТ маркера '<!--tasks:done-->'. Записи с этим маркером "
            "уже обработаны — пропускай их полностью, не создавай по ним задачи.\n"
            "Для каждой новой задачи определи приоритет и срок по правилам todoist.md.\n"
            "ВНЕСИ все новые задачи в Todoist ОДНИМ вызовом mcp-cli add-tasks с массивом "
            "tasks (не по одной!).\n"
            "После успешного внесения — для КАЖДОЙ обработанной записи допиши маркер "
            "'<!--tasks:done-->' в конец её заголовка через Edit "
            f"(файл vault/daily/{today_iso}.md). Пример: '## 10:22 [text]' → "
            "'## 10:22 [text] <!--tasks:done-->'.\n"
            "Верни краткую сводку созданного. Если все записи уже помечены — верни "
            "'ℹ️ Новых задач нет (всё обработано)'."
        )
        report = await _run_with_progress(
            callback.message,
            asyncio.to_thread(processor.execute_prompt, tasks_prompt, user_id),
        )
        if "error" not in report:
            git = VaultGit(settings.vault_path)
            await asyncio.to_thread(git.commit_and_push, f"chore: process daily {today_iso}")

    elif action == "calendar":
        await callback.message.edit_text("⏳ Ищу события в daily...")
        report = await _run_with_progress(
            callback.message,
            asyncio.to_thread(processor.analyze_file_for_calendar, daily_file),
        )

    elif action == "tasks_cal":
        await callback.message.edit_text("⏳ Задачи + Календарь...")
        tasks_prompt = (
            f"Прочитай vault/daily/{today_iso}.md. Извлеки actionable-задачи "
            "(что нужно сделать) — мысли, идеи и рефлексии игнорируй, их обрабатывает "
            "кнопка «Память».\n"
            "ВАЖНО против дублей: обрабатывай ТОЛЬКО записи (блоки '## HH:MM [тип]'), "
            "в заголовке которых НЕТ маркера '<!--tasks:done-->'. Записи с этим маркером "
            "уже обработаны — пропускай их полностью, не создавай по ним задачи.\n"
            "Для каждой новой задачи определи приоритет и срок по правилам todoist.md.\n"
            "ВНЕСИ все новые задачи в Todoist ОДНИМ вызовом mcp-cli add-tasks с массивом "
            "tasks (не по одной!).\n"
            "После успешного внесения — для КАЖДОЙ обработанной записи допиши маркер "
            "'<!--tasks:done-->' в конец её заголовка через Edit "
            f"(файл vault/daily/{today_iso}.md). Пример: '## 10:22 [text]' → "
            "'## 10:22 [text] <!--tasks:done-->'.\n"
            "Верни краткую сводку созданного. Если все записи уже помечены — верни "
            "'ℹ️ Новых задач нет (всё обработано)'."
        )
        tasks_report = await _run_with_progress(
            callback.message,
            asyncio.to_thread(processor.execute_prompt, tasks_prompt, user_id),
        )
        if "error" not in tasks_report:
            git = VaultGit(settings.vault_path)
            await asyncio.to_thread(git.commit_and_push, f"chore: process daily {today_iso}")
        await callback.message.edit_text("⏳ Добавляю события в Google Calendar...")
        cal_report = await _run_with_progress(
            callback.message,
            asyncio.to_thread(processor.analyze_file_for_calendar, daily_file),
        )
        tasks_text = tasks_report.get("report", tasks_report.get("error", ""))
        cal_text = cal_report.get("report", cal_report.get("error", ""))
        report = {"report": tasks_text + "\n\n" + cal_text}

    elif action == "memory":
        await callback.message.edit_text("⏳ Раскладываю знания по хранилищу мыслей...")
        prompt = (
            f"Прочитай daily/{today_iso}.md. Сегодня {today_iso}.\n\n"
            "Задача: извлечь ВСЕ единицы знаний и разложить по vault. Применяй полные правила из "
            ".claude/skills/dbrain-processor/SKILL.md и references/classification.md.\n\n"
            "=== ЧТО ИЗВЛЕКАТЬ ===\n\n"
            "1) МЫСЛИ (thoughts/):\n"
            "   - learning  → thoughts/learnings/  — новый паттерн/механика/«узнал как работает»\n"
            "   - idea      → thoughts/ideas/      — продуктовая идея, гипотеза, контент-тезис\n"
            "   - reflection→ thoughts/reflections/— личное осознание, философия, «понял про себя»\n"
            "   - project   → thoughts/projects/   — стратегическая/долгосрочная проектная мысль\n"
            "   Имя файла: {YYYY-MM-DD}-short-title.md. Структура: Context / Insight / Implication / Next Action.\n\n"
            "2) ИСТОЧНИКИ ЗНАНИЙ (interests/):\n"
            "   - book   → interests/books/{slug}.md   триггеры: «прочитал», «читаю», «книга», «глава», «автор»\n"
            "   - film   → interests/films/{slug}.md   триггеры: «посмотрел», «фильм/сериал»\n"
            "   - topic  → interests/topics/{slug}.md  устойчивый интерес к теме\n"
            "   Если паттерн «X посоветовал/рекомендует [название]» — set recommended_by: PERSON-SLUG "
            "   И добавь запись в people/PERSON-SLUG.md секцию «Что советовал».\n\n"
            "3) MEMORY.md:\n"
            "   Если learning действительно важный (новый паттерн с impact) — обнови секцию Learnings через Edit. "
            "Принцип evolve, не append (см. SKILL.md).\n\n"
            "4) СВЯЗИ С ЛЮДЬМИ (обязательно):\n"
            "   Если в мысли/инсайте/идее упомянут человек:\n"
            "   - Внутри файла мысли — wiki-link [[people/{slug}]]\n"
            "   - В people/{slug}.md → строка в «История взаимодействий»: "
            "`- {YYYY-MM-DD} — {краткое описание} → [[thoughts/{cat}/{file}]]`\n"
            "   - Если тема профессиональная — также строка в «Темы разговоров»\n"
            "   - Если карточки нет — создай из templates/person-template.md\n"
            "   - Bidirectional: если у человека есть компания, проверь company-карточку тоже\n\n"
            "=== ЧТО НЕ ДЕЛАТЬ ===\n"
            "- НЕ создавать задачи в Todoist (это делает кнопка Задачи)\n"
            "- НЕ трогать people/companies/CRM для встреч (это делает Итоги встречи)\n"
            "- НЕ дублировать существующие заметки — сначала grep по vault, потом create-or-update\n\n"
            "=== ОТЧЁТ (HTML для Telegram, без markdown) ===\n\n"
            f"🧠 <b>Знания за {today_iso}</b>\n\n"
            "<b>💡 Идеи:</b>\n• {title} → thoughts/ideas/{file}\n\n"
            "<b>🧠 Инсайты (learnings):</b>\n• {title} → thoughts/learnings/{file}\n\n"
            "<b>🪞 Рефлексии:</b>\n• {title} → thoughts/reflections/{file}\n\n"
            "<b>🎯 Проекты:</b>\n• {title} → thoughts/projects/{file}\n\n"
            "<b>📚 Книги:</b>\n• {title} (recommended_by: {person}) → interests/books/{slug}\n\n"
            "<b>🎬 Фильмы/сериалы:</b>\n• {title} → interests/films/{slug}\n\n"
            "<b>🏷 Темы:</b>\n• {title} → interests/topics/{slug}\n\n"
            "<b>📌 MEMORY.md обновлено:</b>\n• {секция}: {что добавлено}\n\n"
            "Пустые секции — опусти полностью. Если знаний вообще не найдено, выведи: "
            "'🧠 <b>Знаний в сегодняшнем daily не найдено</b>'. "
            "Allowed tags: <b>, <i>, <code>, <s>, <u>, <a href=>."
        )
        report = await _run_with_progress(
            callback.message,
            asyncio.to_thread(processor.execute_prompt, prompt, user_id),
        )
        git = VaultGit(settings.vault_path)
        await asyncio.to_thread(git.commit_and_push, f"chore: memory update {today_iso}")

    elif action == "meeting":
        await callback.message.edit_text("⏳ Обрабатываю итоги встречи...")
        prompt = (
            f"Прочитай daily/{today_iso}.md и найди записи-итоги встреч (характерные маркеры: 'итоги общения', 'встретился с', 'встретилась с', 'провели встречу', 'диагностика с'). "
            f"Сегодня {today_iso}.\n\n"
            "ДЛЯ КАЖДОЙ ВСТРЕЧИ выполни следующее:\n\n"
            "1. ПАРСИНГ: извлеки участников (имена), компании, договорённости, болячки клиента, что предложил, следующие шаги (даты, действия)\n\n"
            "2. КАРТОЧКИ ЛЮДЕЙ (vault/people/{slug}.md):\n"
            "   - Для каждого участника create-or-update карточку\n"
            "   - Проверяй aliases (Rule 10) перед созданием новой\n"
            "   - Добавь запись в '## История' с датой и итогами\n"
            "   - Свяжи через wiki-links с companies/ и business/crm/\n\n"
            "3. КАРТОЧКА КОМПАНИИ (vault/companies/{slug}.md):\n"
            "   - create-or-update с website, индустрией, структурой\n"
            "   - Секция 'Боли' — конкретный список\n"
            "   - Секция 'Потенциальное сотрудничество' — что я предложил\n"
            "   - Связи: ключевые люди → people/, CRM → business/crm/\n\n"
            "4. CRM-КАРТОЧКА (vault/business/crm/{slug}.md):\n"
            "   - type: crm, priority, status (Discovery/Nurture/Active/Won/Lost), deal_status\n"
            "   - deal_deadline = дата next-step\n"
            "   - Секция 'Следующий шаг' — конкретное действие с датой\n"
            "   - История взаимодействий (хронология)\n\n"
            "5. FOLLOW-UP ЗАДАЧА в Todoist:\n"
            "   - Создай через mcp-cli add-tasks\n"
            "   - content: 'Follow-up с [[people/{slug}|Имя]] по [[companies/{slug}|Компания]]: {конкретное действие}'\n"
            "   - dueString = договорённая дата (если '2 недели' → today+14, если 'через месяц' → today+30)\n"
            "   - priority: p2 (для hot lead), p3 (для тёплых)\n"
            "   - labels: ['client:{slug}', 'follow-up']\n"
            "   - ОБЯЗАТЕЛЬНО возьми РЕАЛЬНЫЙ id из response (Rule 8), не выдумывай\n\n"
            "6. ОТЧЁТ HTML для Telegram:\n\n"
            "<b>🤝 Итоги встречи обработаны</b>\n\n"
            "<b>👤 Участники:</b>\n"
            "• {Имя} ({роль}) → [[people/{slug}]] (создано/обновлено)\n\n"
            "<b>🏢 Компании:</b>\n"
            "• {Название} → [[companies/{slug}]] (создано)\n\n"
            "<b>💼 CRM:</b>\n"
            "• {компания} → status: {status}, deadline: {date}\n\n"
            "<b>📌 Боли клиента:</b>\n"
            "• {боль 1}\n• {боль 2}\n\n"
            "<b>💡 Что предложено:</b>\n"
            "• {1}\n• {2}\n\n"
            "<b>📅 Следующий шаг:</b>\n"
            "{Дата} — {действие}\n\n"
            "<b>✅ Задача Todoist:</b>\n"
            "{content} (id: {real_id}, p{X}, {due})\n\n"
            "ФОРМАТ: только HTML, без markdown (**, ##, ```). Allowed: <b>, <i>, <code>, <s>, <u>, <a href=>.\n\n"
            "Если встреч в daily не найдено — выведи: '🤝 <b>Встреч в сегодняшнем daily не найдено</b>\\n\\nЕсли встреча была — добавь итоги текстом в бот и попробуй снова.'"
        )
        report = await _run_with_progress(
            callback.message,
            asyncio.to_thread(processor.execute_prompt, prompt, user_id),
        )
        git = VaultGit(settings.vault_path)
        await asyncio.to_thread(git.commit_and_push, f"chore: meeting outcomes {today_iso}")

    else:
        report = {"error": f"Unknown action: {action}"}

    formatted = format_process_report(report)
    chunks = split_long_message(formatted)
    try:
        await callback.message.edit_text(chunks[0])
    except Exception:
        await callback.message.edit_text(chunks[0], parse_mode=None)
    for chunk in chunks[1:]:
        try:
            await callback.message.answer(chunk)
        except Exception:
            await callback.message.answer(chunk, parse_mode=None)

    logger.info("Process menu action '%s' done for user %s", action, user_id)
