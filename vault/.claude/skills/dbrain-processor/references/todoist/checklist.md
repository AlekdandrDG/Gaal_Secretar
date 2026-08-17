---
type: note
last_accessed: 2026-07-17
relevance: 0.56
tier: cold
---
# Todoist — pre-creation checklist

Выполнить ПЕРЕД созданием задач.

## 1. Check Workload (REQUIRED)

```bash
todoist-cli find-tasks-by-date '{"startDate": "today", "daysCount": 7, "limit": 50}'
```

Построй карту загрузки:
```
Mon: 2 tasks
Tue: 4 tasks  ← overloaded
Wed: 1 task
Thu: 3 tasks  ← at limit
```

## 2. Check Duplicates (REQUIRED)

```bash
todoist-cli find-tasks '{"searchText": "ключевые слова новой задачи"}'
```

Если похожая есть → пометь как дубликат, не создавай.

## Workload Balancing

Если на целевой день уже 3+ задач:
1. Найди ближайший день с < 3 задач
2. Поставь туда
3. В отчёте: «сдвинуто на {day} (перегрузка)»

## Anti-Patterns (НЕ СОЗДАВАТЬ)

- ❌ «Подумать о…» → конкретизируй действие
- ❌ «Разобраться с…» → что именно сделать?
- ❌ Абстрактные задачи без Next Action
- ❌ Дубликаты существующих задач
- ❌ Задачи без дат
