---
type: note
last_accessed: 2026-07-17
relevance: 0.56
tier: cold
---
# Todoist — базовые команды (todoist-cli)

**ВСЕГДА используй todoist-cli (обёртка над Todoist API v1).**

## Reading

```bash
todoist-cli get-overview '{}'                                        # обзор всех проектов
todoist-cli find-tasks '{"searchText": "keyword"}'                   # поиск по тексту/проекту/секции
todoist-cli find-tasks-by-date '{"startDate": "today", "daysCount": 7}'  # задачи по дате
```

## Writing

```bash
# Создать задачи (ВСЕГДА батчем — массив в одном вызове, а не по одной)
todoist-cli add-tasks '{"tasks": [{"content": "Task", "dueString": "tomorrow", "priority": 2}]}'
# Завершить
todoist-cli complete-tasks '{"ids": ["task_id"]}'
# Обновить
todoist-cli update-tasks '{"tasks": [{"id": "task_id", "content": "New title"}]}'
```

**ВАЖНО про скорость:** todoist-cli ходит напрямую в Todoist API (быстро). Если создаёшь несколько задач — передавай их ОДНИМ `add-tasks` с массивом `tasks`, не вызывай команду на каждую задачу отдельно.

## Формат ссылок на задачи

✅ Правильно: `https://app.todoist.com/app/task/{task_id}`
❌ Устарело: `https://todoist.com/showTask?id={task_id}`, `https://todoist.com/app/task/{task_id}`

Если MCP вернул `url` — используй его напрямую. Иначе строй по формату выше.

## Error Handling

CRITICAL: Никогда не предлагай «добавить вручную».

Если `add-tasks` упал:
1. Включи ТОЧНЫЙ текст ошибки в отчёт
2. Продолжай со следующей записью
3. Не помечай как обработанное

WRONG: «Не удалось добавить (MCP недоступен). Добавь вручную: …»
CORRECT: «Ошибка создания задачи: [точная ошибка из MCP]»
