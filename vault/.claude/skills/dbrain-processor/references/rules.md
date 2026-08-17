---
type: note
last_accessed: 2026-05-05
relevance: 0.1
tier: archive
---
# Critical Processing Rules

See [ABOUT.md](ABOUT.md) for user context and preferences.

## Rule 1: Skip Processed Entries

```
If entry contains `<!-- ✓ processed` → SKIP COMPLETELY
```

Check AFTER each `## HH:MM` header for the marker.

## Rule 2: Every Task = Date

**NEVER create a task without `dueString`:**

| Text | dueString |
|------|-----------|
| завтра | tomorrow |
| в пятницу | friday |
| на этой неделе | friday |
| в четверг | thursday |
| 15 января | January 15 |
| NOT SPECIFIED | in 3 days |

## Rule 3: Check Duplicates

**BEFORE creating any task:**

1. Call `find-tasks` with key words from task
2. If similar task exists → **DO NOT CREATE**
3. Mark as: `<!-- ✓ processed: task (duplicate) -->`

## Rule 4: Consider Workload

**BEFORE creating tasks:**

1. Call `find-tasks-by-date` with `startDate: "today"`, `daysCount: 7`
2. Count tasks per day
3. If target day has 3+ tasks → shift to next day with less load

## Rule 5: Mark After Processing

After EACH processed entry, add marker:

```markdown
<!-- ✓ processed: {category} -->
```

For tasks with details:
```markdown
<!-- ✓ processed: task → Todoist: {name} {priority} {date} -->
```

## Rule 6: Apply Decision Filters

Before saving any thought or task, check:
- Это масштабируется?
- Это можно автоматизировать?
- Это усиливает экспертизу [Your Business]?
- Это приближает к продукту/SaaS?

If 2+ yes → boost priority.

## Rule 7: Книги — НЕ задачи

**Книги (рекомендации, упоминания, "хочу прочитать") НИКОГДА не создают задач в Todoist** — если пользователь не сказал явно "добавь в задачи" / "напомни прочитать".

### Что делать с книгой:

1. Сохранить в `interests/books/{slug}.md` с метаданными (источник, рекомендатель, статус: want-to-read)
2. Связать через wiki-link с источником (контактом, который рекомендовал)
3. Добавить в отчёт в секцию "📚 Книги" а не в "✅ Задачи"
4. **НЕ создавать** Todoist задачу с дедлайном "прочитать книгу"

### Триггеры для книг:

- "рекомендую книгу", "почитай", "хорошая книга", "есть книга про..."
- упоминание автора книги
- ссылка на книгу

### Когда книга СТАНОВИТСЯ задачей:

Только если пользователь явно сказал:
- "добавь в задачи прочитать"
- "напомни через неделю"
- "поставь на конкретную дату"

В остальных случаях книга = заметка в `interests/books/`, не задача.

## Rule 8: Verify task id

После `todoist-cli add-tasks ...` ВСЕГДА бери id из RAW response (`data.tasks[].id`).

**Запрещено:** выдумывать id, брать из памяти, копировать из другой задачи. Если add-tasks упал — пиши `<!-- ✗ FAILED -->`, не подделывай id.

## Rule 9: Correction ≠ Complete

Запись-коррекция ("не X, а Y" / "ошибка распознавания" / "уточняю") → используй `update-tasks` для исправления content.

**Запрещено:** complete-tasks при коррекции, delete + recreate, создание дубликата.

Маркер: `<!-- ✓ correction → task {id} updated, new content: ... -->`

## Rule 10: Привязка имён через PEOPLE REGISTRY + карантин

В начале промпта есть блок **=== PEOPLE REGISTRY ===** — это источник правды по всем известным людям (каноническое имя, slug, варианты написания, роль). Матчь имена ТОЛЬКО по нему, не грепай people/*.md вручную.

### Алгоритм матчинга (для каждого упомянутого человека)

1. Нормализуй имя из текста (убери склонения: «Петровым»→«Петров», «с Ваней»→«Ваня»).
2. Сверь с PEOPLE REGISTRY:
   - **Точное совпадение** с name или одним из вариантов → это тот человек. Используй каноническое name + `[[people/{slug}]]`.
   - **Ровно один похожий** (явная форма того же имени/фамилии) → привязывай к нему.
   - **Несколько кандидатов** (например 2 Игоря) → НЕ выбирай наугад → КАРАНТИН (см. ниже).
   - **Нет совпадений** → см. п.4.
3. Если привязал — при необходимости добавь недостающий вариант в `aliases:` карточки (чтобы впредь матчилось лучше).
4. **Нет совпадений в registry:**
   - Источник [text], имя выглядит валидным («Иван Петров») → создай карточку people/{slug}.md (type:person, name, slug, aliases широко) и используй её. Карточка автоматически попадёт в registry при следующем /process.
   - Источник [voice] ИЛИ имя сомнительное/обрывок → **КАРАНТИН**. НЕ создавай карточку.

### КАРАНТИН (низкая уверенность / неоднозначность)

Когда нельзя уверенно привязать:
1. Задачу/заметку всё равно создай, но в content пометь имя как `Имя(?)`.
2. **НЕ создавай people-карточку.**
3. Добавь запись в карантин-файл `vault/.session/people-quarantine.md` (создай если нет), одна строка:
   `- {YYYY-MM-DD} | "{как услышано}" | {context: что за событие/задача} | кандидаты: {slug1, slug2 или "нет"} | [[daily/{YYYY-MM-DD}]]`
4. В HTML-отчёте добавь в секцию «❓ Уточнить людей» вопрос (см. шаблон).

### Дозапись ответа пользователя (correction-поток)

Если пользователь отвечает на вопрос из карантина («это Петров» / «новый человек, Иван Петров» / «это тот же Игорь-массажист»):
1. Найди строку в `vault/.session/people-quarantine.md`.
2. Привяжи отложенное: обнови задачу (update-tasks, НЕ complete) убрав `(?)` и добавив `[[people/{slug}]]`; или создай новую карточку, если пользователь назвал нового человека.
3. Добавь услышанный вариант имени в `aliases:` соответствующей карточки — чтобы в следующий раз матчилось автоматически.
4. Удали обработанную строку из people-quarantine.md.

Мусор типа "ВИЧ-корова" (явный сбой распознавания) → НЕ в задачу, НЕ в карантин — просто пометь в daily `<!-- ⚠️ speech garbage -->`.

## Rule 11: Travel dates — только из карточки

При упоминании поездки/возвращения/прилёта:

1. Прочитай `vault/places/travels/*.md`
2. Бери даты из frontmatter `start_date` / `end_date`

**Запрещено:** угадывать "завтра возвращение", прибавлять дни к end_date, выдумывать даты без сверки.

## Rule 12: Avoid Anti-Patterns

NEVER create:
- Абстрактные задачи без Next Action ("Подумать о...")
- Хаотичные списки без приоритетов
- Повторы без синтеза
- Академическая теория без применения

See [ABOUT.md](ABOUT.md) → Anti-Patterns section.

---

## Checklist Before Completion

- [ ] All new entries processed
- [ ] No duplicates in Todoist
- [ ] All tasks have dates and concrete actions
- [ ] Task ids in markers verified from add-tasks RAW response (Rule 8)
- [ ] Corrections used update-tasks, not complete-tasks (Rule 9)
- [ ] Имена сверены с PEOPLE REGISTRY; неоднозначные → карантин + вопрос в отчёте (Rule 10)
- [ ] Travel dates taken from places/travels/*.md (Rule 11)
- [ ] Decision filters applied
- [ ] Anti-patterns avoided
- [ ] MOC files updated
- [ ] Report generated
