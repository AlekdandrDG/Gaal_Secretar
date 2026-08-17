---
type: note
last_accessed: 2026-07-17
relevance: 0.56
tier: cold
---
# Todoist — проекты и авто-кластеризация

## Известные проекты (projectId)

Таблица заполняется по мере работы (см. «Авто-кластеризация» ниже). Изначально пуста — всё уходит в Inbox.

| Keywords | Project | projectId |
|----------|---------|-----------|
| ООО «Пример», проект «Пример» | Пример | `PROJECT_ID_HERE` |
| (по умолчанию) | Inbox | `INBOX_PROJECT_ID` |

Если задача упоминает entity из списка — добавляй `projectId` в `add-tasks`.

```bash
todoist-cli add-tasks '{"tasks": [{"content": "…", "dueString": "friday", "priority": 4, "projectId": "…"}]}'
```

## Авто-кластеризация (создание новых проектов)

Если в текущем `/process` встретилось **3+ новых задач** одной сущности (проект/клиент/тема), для которой **нет projectId выше**:

1. Проверь `find-projects` — вдруг проект уже есть
2. Если нет — создай:
   ```bash
   todoist-cli add-projects '{"projects": [{"name": "Имя"}]}'
   ```
3. Используй новый `projectId` для всех связанных задач
4. Добавь строку в таблицу выше (Edit этого файла)
5. В отчёте: `<b>📁 Создан проект:</b> {name} ({N} задач)`

### Эвристика «одна сущность»

- Одно имя/бренд упомянуто ≥2 раз суммарно
- Общий префикс/тема («Пример:», «Acme Corp —»)
- Похожий контекст (клиент, продукт, проект)

Если непонятно → Inbox.

## Client Labels

Формат: `client:{kebab-case-name}` (напр. `client:acme-corp`).

```bash
todoist-cli add-tasks '{"tasks": [{"content": "Follow-up [Client A]", "labels": ["client:acme-corp", "deadline"]}]}'
```

Фильтр в Todoist: `@client:acme-corp`.
