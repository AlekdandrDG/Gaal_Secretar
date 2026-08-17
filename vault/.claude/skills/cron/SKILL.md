---
type: note
description: Управление собственным расписанием — напоминания, рутины, периодические задачи. Триггеры — "напомни", "каждый день/час/утро", "по расписанию", "schedule", "reminder", "отмени напоминание", "что запланировано".
last_accessed: 2026-06-18
relevance: 0.13
tier: cold
name: cron
---

# Cron: расписания и напоминания

Ты управляешь своим расписанием сам — через CLI, который редактирует
`jobs.json`. Бот перечитывает файл каждую минуту и запускает задания
отдельным процессом Claude. Результат запуска уходит пользователю в Telegram.

## Команды

Рабочая директория — vault, проект уровнем выше. ВСЕГДА указывай
`--dir ../.runtime/cron`, иначе бот не увидит задание.

```bash
# Повторяющееся по cron-выражению (время местное — указывай --tz)
/home/dbrain/uv run --project .. python -m d_brain.cron add \
  --dir ../.runtime/cron \
  --prompt "Собери утреннюю сводку: вчерашний daily, goals недели" \
  --cron "0 9 * * *" --tz Europe/Moscow --id morning-brief

# Интервал в секундах
/home/dbrain/uv run --project .. python -m d_brain.cron add \
  --dir ../.runtime/cron \
  --prompt "Проверь inbox в vault, новое разложи по карточкам. Если пусто — начни ответ с [SILENT]" \
  --every 3600

# Разовое напоминание: ВСЕГДА --at + --delete-after-run
/home/dbrain/uv run --project .. python -m d_brain.cron add \
  --dir ../.runtime/cron \
  --prompt "Напомни про звонок с подрядчиком" \
  --at "2026-06-20T18:00:00+03:00" --delete-after-run

/home/dbrain/uv run --project .. python -m d_brain.cron list   --dir ../.runtime/cron
/home/dbrain/uv run --project .. python -m d_brain.cron remove <id> --dir ../.runtime/cron
/home/dbrain/uv run --project .. python -m d_brain.cron enable <id> --dir ../.runtime/cron
```

Ошибка → exit 2 и текст в stderr: прочитай и исправь аргументы.

## Перевод естественного языка в расписание

Часовой пояс пользователя — **Europe/Moscow (UTC+3)**.

| Просьба | Аргументы |
|---|---|
| «каждый день в 9» | `--cron "0 9 * * *" --tz Europe/Moscow` |
| «по будням в 18:30» | `--cron "30 18 * * 1-5" --tz Europe/Moscow` |
| «каждое воскресенье в 10» | `--cron "0 10 * * 0" --tz Europe/Moscow` |
| «каждый час» | `--every 3600` |
| «каждые 15 минут» | `--every 900` |
| «через 20 минут» | вычисли ISO-время now+20m → `--at <ISO+03:00> --delete-after-run` |
| «завтра в 15» | `--at "<завтра>T15:00:00+03:00" --delete-after-run` |

## Правила

1. **Никогда не эмулируй расписание** через `sleep`, циклы в Bash или
   фоновые процессы — только этот CLI.
2. Разовое («напомни…») — всегда `--at` + `--delete-after-run`.
3. `--at` пиши со смещением зоны (`+03:00`); naive-время трактуется в `--tz`.
4. **Prompt задания — самодостаточный**: исполняет отдельный процесс без
   контекста текущего разговора. Включай в prompt всё нужное (пути, имена,
   критерии).
5. Мониторинговым заданиям («проверь и скажи, если что-то новое») вели в
   prompt: «если ничего важного — начни ответ строкой [SILENT]» — тогда
   пользователь не получит пустой спам.
6. **Recursion guard**: если текущий запрос помечен `[CRON JOB ...]` — ты
   внутри планового запуска; создавать/менять/удалять задания ЗАПРЕЩЕНО.
7. После add/remove подтверди пользователю результат строкой из `list`
   (id, расписание, next run).
