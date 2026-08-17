---
type: note
last_accessed: 2026-07-17
relevance: 0.56
tier: cold
---
# Todoist — повторяющиеся задачи (process goals)

Для process-обязательств → `dueString` с повторяющимся паттерном.

## Recurring Patterns

| Описание | dueString |
|----------|-----------|
| каждое утро в 6 | every day at 6am |
| каждый день | every day |
| каждый рабочий день | every weekday |
| 3 раза в неделю | every monday, wednesday, friday |
| раз в неделю | every week |
| каждый понедельник | every monday |
| каждую пятницу | every friday |

## Пример

```bash
todoist-cli add-tasks '{"tasks": [
  {"content": "2h deep work: программа [Client B]", "dueString": "every day at 6am", "priority": 2, "labels": ["process-goal"]},
  {"content": "1 outreach для 2го спикера", "dueString": "every weekday", "priority": 3, "labels": ["process-goal"]}
]}'
```

## Label

Для повторяющихся задач из process-commitments используй label `process-goal` — для фильтрации и чистки.

## Когда создавать

- Генерация недельного дайджеста (планирование новой недели)
- Пользователь явно просит настроить process goal
- Превращение outcome-цели в process (если пользователь подтвердил)

## Чистка устаревших

В недельном дайджесте:
```bash
todoist-cli find-tasks '{"labels": ["process-goal"]}'
```
Если задача с прошлой недели → предупреди закрыть/удалить.
