---
type: note
last_accessed: 2026-05-05
relevance: 0.1
tier: archive
---
# Todoist Integration — индекс

Работа с Todoist разбита на модули. Читай через Read только нужный модуль под конкретную операцию — не грузи всё сразу.

**ВСЕГДА используй todoist-cli** (обёртка над Todoist API v1). НЕ используй MCP tools напрямую.
**Скорость:** todoist-cli ходит напрямую в Todoist API (быстро). Создаёшь несколько задач — передавай их ОДНИМ `add-tasks` с массивом, не по одной.

## Модули

| Что делаешь | Читай |
|-------------|-------|
| Любые команды (create/read/complete/update), формат ссылок, обработка ошибок | [references/todoist/commands.md](todoist/commands.md) |
| Перед созданием: проверка загрузки, дублей, балансировка, анти-паттерны | [references/todoist/checklist.md](todoist/checklist.md) |
| Приоритеты (домены/keywords/boost) и даты (RU→dueString) | [references/todoist/priority-dates.md](todoist/priority-dates.md) |
| Проекты (projectId, авто-кластеризация), клиентские лейблы | [references/todoist/projects.md](todoist/projects.md) |
| Повторяющиеся задачи (process goals) | [references/todoist/recurring.md](todoist/recurring.md) |

## Типовой порядок при создании задач

1. `checklist.md` — проверь загрузку и дубли
2. `priority-dates.md` — определи приоритет и dueString
3. `projects.md` — определи projectId/лейблы, при 3+ задач одной сущности — кластеризуй
4. `commands.md` — создай ОДНИМ батч-вызовом `add-tasks`
