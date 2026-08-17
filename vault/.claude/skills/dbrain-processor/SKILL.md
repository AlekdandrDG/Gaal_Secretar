---
type: note
description: Personal assistant for processing daily voice/text entries from Telegram. Classifies content, creates Todoist tasks aligned with goals, saves thoughts to Obsidian with wiki-links, generates HTML reports. Integrates Your Business context (clients, projects, CRM). Triggers on /process command or daily 21:00 cron.
last_accessed: 2026-05-05
relevance: 0.1
tier: archive
name: dbrain-processor
allowed-tools: Bash(todoist-cli:*), Bash(mcp-cli:*)
depends_on: [graph-builder, todoist-ai, agent-memory, vault-health]
---

# d-brain Processor

Process daily entries → tasks (Todoist) + thoughts (Obsidian) + HTML report (Telegram).

Integrates with Your Business data for business context.

## CRITICAL: Output Format

**ALWAYS return RAW HTML. No exceptions. No markdown. Ever.**

Your final output goes directly to Telegram with `parse_mode=HTML`.

Rules:
1. ALWAYS return HTML report — even if entries already processed
2. ALWAYS use the template below — no free-form text
3. NEVER use markdown syntax (**, ##, ```, -)
4. NEVER explain what you did in plain text — put it in HTML report

WRONG:
```html
<b>Title</b>
```

CORRECT:
<b>Title</b>

## Todoist через todoist-cli

**ВСЕГДА используй todoist-cli для Todoist** (обёртка над Todoist API v1). Не используй прямые MCP tools.

### Базовые команды:

```bash
# Задачи на сегодня (проверка workload)
todoist-cli find-tasks-by-date '{"startDate": "today"}'

# Создать задачу
todoist-cli add-tasks '{"tasks": [{"content": "Task", "dueString": "tomorrow", "priority": 2}]}'

# Найти задачи по label
todoist-cli find-tasks '{"labels": ["process-goal"]}'

# Завершить задачи
todoist-cli complete-tasks '{"ids": ["task_id"]}'

# Обзор
todoist-cli get-overview '{}'
```

### Приоритеты:
- 1 = p1 (highest)
- 2 = p2 (high)
- 3 = p3 (medium)
- 4 = p4 (default)

## CRITICAL: todoist-cli Usage

**СНАЧАЛА ВЫЗОВИ КОМАНДУ. ПОТОМ ДУМАЙ.**

### Обязательный алгоритм:

```
1. ВЫЗОВИ: todoist-cli find-tasks-by-date '{"startDate": "today"}'
   ↓
   Получил результат? → Продолжай
   ↓
   Ошибка? → Читай файлы 30 секунд, потом ВЫЗОВИ СНОВА
   ↓
   3 ошибки подряд? → Покажи ТОЧНЫЙ текст ошибки
```

### ЗАПРЕЩЕНО:

- ❌ "Todoist недоступен"
- ❌ "todoist-cli не работает"
- ❌ "добавь вручную"
- ❌ Решать что не работает БЕЗ вызова команды

### ОБЯЗАТЕЛЬНО:

- ✅ ВЫЗВАТЬ команду через Bash
- ✅ Если ошибка — подождать, вызвать снова
- ✅ 3 retry перед любыми выводами
- ✅ Показать task ID если создан

## Processing Flow

1. **Load personal context** — Read goals/1-yearly, goals/2-monthly, goals/3-weekly
2. **Load business context**:
   - Read `business/_index.md` — Your Business (клиенты, проекты, CRM)
   - Read `projects/_index.md` — личные проекты (если релевантно)
3. **Read daily** — daily/YYYY-MM-DD.md
4. **Check workload** — `todoist-cli find-tasks-by-date '{"startDate": "today", "daysCount": 7}'`
4a. **Check completed tasks (TODAY)** — `todoist-cli find-completed-tasks '{"since": "YYYY-MM-DDT00:00:00Z", "until": "YYYY-MM-DDT23:59:59Z"}'` (replace YYYY-MM-DD with today)
4d. **CHECK DELETED TASKS** — сравни вчерашний снэпшот с текущим Todoist (см. § Deleted Tasks Tracking). Выяви исчезнувшие задачи (не закрытые) → секция 🗑 в отчёте.
5. **CHECK PROCESS GOALS** — `todoist-cli find-tasks '{"labels": ["process-goal"]}'`
   → If empty or stale: generate from goals, create recurring tasks
6. **Process entries** — Classify → task or thought, detect business mentions
7. **Build links** — Connect notes with [[wiki-links]], link to business entities
8. **Generate HTML report** — include process goals status + business activity
9. **Log actions to daily** — append action log entry (see below)
10. **Evolve MEMORY.md** — update long-term memory if needed (see below)
11. **Capture observations** — record friction signals to handoff.md (see below)
12. **Save tasks snapshot** — в самом конце сохрани снэпшот активных задач (см. § Deleted Tasks Tracking)

## ОБЯЗАТЕЛЬНО: Логирование в daily/

**После ЛЮБЫХ изменений в vault — СРАЗУ пиши в `daily/YYYY-MM-DD.md`:**

Формат:
```
## HH:MM [text]
{Описание действий}

**Создано/Обновлено:**
- [[path/to/file|Name]] — описание
```

**Что логировать:**
- Создание файлов в thoughts/
- Обновление business/ или projects/
- Создание задач в Todoist (с task ID)
- Синхронизация с внешними системами

**Пример:**
```
## 14:30 [text]
Обработка ежедневных записей

**Создано задач:** 3
- "Follow-up Acme Corp" (id: 8501234567, p2, завтра)
- "Подготовить КП Unilever" (id: 8501234568, p2, пятница)

**Сохранено мыслей:** 1
- [[thoughts/ideas/product-launch|Product Launch]] — идея запуска
```

**Зачем:** Audit trail + контекст для будущих обработок.

## Evolve MEMORY.md (Step 10 Detail)

**ЦЕЛЬ:** Поддерживать MEMORY.md актуальным. Не добавлять, а ЭВОЛЮЦИОНИРОВАТЬ.

### Когда обновлять MEMORY.md

Проверь после обработки entries — есть ли информация достойная долгосрочной памяти?

### Write Rules: Что достойно MEMORY.md

**ПИСАТЬ:**
- ✅ Key decisions с impact (pivot, tool choice, architecture change)
- ✅ Изменения в pipeline (новый лид, закрытая сделка, изменение статуса)
- ✅ Финансовые изменения (оплаты получены, долги, новые контракты)
- ✅ Новые паттерны/инсайты (learnings)
- ✅ Изменения в Active Context (новый ONE Big Thing, Hot Projects)
- ✅ Новые ключевые контакты (с context)

**НЕ ПИСАТЬ:**
- ❌ Ежедневные мелочи (встречи, звонки без impact)
- ❌ Временные заметки (оставить в daily/)
- ❌ Дубликаты того что уже есть
- ❌ Детали проектов (оставить в business/crm/, projects/)
- ❌ Тривиальные задачи

### Как обновлять (evolve, не append)

**Принцип:** Новое ЗАМЕНЯЕТ устаревшее, не добавляется рядом.

| Ситуация | Действие |
|----------|----------|
| Новое противоречит старому | ЗАМЕНИТЬ старую информацию |
| Новое дополняет старое | Добавить в существующую секцию |
| Информация устарела | Удалить или архивировать |

**Пример 1 — Изменение статуса проекта:**
```
Old: "| Acme Corp NCP Meals | p1 | Активная разработка | $XXK |"
New info: "Acme Corp NCP Meals сдан клиенту"
→ ЗАМЕНИТЬ на: "| Acme Corp NCP Meals | ✅ | Завершён | $XXK |"
```

**Пример 2 — Новое решение:**
```
Добавить в Key Decisions таблицу:
| 2026-02-01 | Отказ от X в пользу Y | причина | impact |
```

**Пример 3 — Изменение в pipeline:**
```
Old: "| LogisticsLead | Hot | $XXK |"
New info: "LogisticsLead подписал контракт"
→ Удалить из Pipeline
→ Добавить в Hot Projects или Financial Context
```

### Секции MEMORY.md для обновления

| Секция | Когда обновлять |
|--------|-----------------|
| Active Context | Изменение ONE Big Thing, Hot Projects, Pipeline |
| Key Decisions | Новое решение с impact |
| Financial Context | Оплаты, долги, контракты |
| Key People | Новый важный контакт |
| Learnings | Новый паттерн/инсайт |
| Current Crisis | Изменение в текущей критической ситуации |

### Формат Edit

Используй Edit tool для точечных изменений:

```
Edit MEMORY.md:
old_string: "| LogisticsLead | Hot | $XXK |"
new_string: "| LogisticsLead | ✅ Signed | $XXK |"
```

### В отчёте

Если обновил MEMORY.md, добавь секцию:

```html
<b>🧠 MEMORY.md обновлён:</b>
• Active Context → Hot Projects updated
• Key Decisions → +1 новое решение
```

## Capture Observations (Step 11 Detail)

**ЦЕЛЬ:** Записывать friction signals, паттерны и идеи для улучшения системы.

### Когда записывать

После обработки проверь — были ли проблемы или наблюдения?

| Тип | Когда |
|-----|-------|
| `[friction]` | mcp-cli errors, timeouts, empty daily, broken links, unexpected data |
| `[pattern]` | Повторяющийся паттерн (задачи всегда overdue, daily пустой по выходным) |
| `[idea]` | Идея для улучшения pipeline, schema, отчёта |

### Формат

Append в `vault/.session/handoff.md` секцию `## Observations`:

```markdown
## Observations
- [friction] YYYY-MM-DD: mcp-cli timeout 3x на todoist — retry спас, но -60 сек
- [pattern] YYYY-MM-DD: daily без entries 2 дня подряд — выходные?
- [idea] YYYY-MM-DD: CRM карточки без deal_deadline = невидимые дедлайны
```

### Правила

- Одна строка на наблюдение (конкретика, не абстракции)
- Дата обязательна
- Не повторять уже записанные observations
- Когда observations ≥10 → сигнал для system improvement session

### В отчёте

Если записаны observations, добавь:

```html
<b>👁 Observations:</b>
• [friction] mcp-cli timeout 3x
```

---

## Process Goals Check (Step 5 Detail)

**ОБЯЗАТЕЛЬНО выполни этот шаг при каждом /process:**

### 1. Проверь существующие process goals

```bash
todoist-cli find-tasks '{"labels": ["process-goal"], "limit": 20}'
```

### 2. Если process goals ОТСУТСТВУЮТ — создай их

Читай goals файлы и генерируй process commitments:

| Goal Level | Source | Process Pattern |
|------------|--------|-----------------|
| Weekly ONE Big Thing | goals/3-weekly.md | 2h deep work ежедневно |
| Monthly Top 3 | goals/2-monthly.md | 1 action/день на приоритет |
| Yearly Focus | goals/1-yearly-*.md | 30 мин/день на стратегию |

**Создай recurring tasks:**

```bash
todoist-cli add-tasks '{"tasks": [
  {"content": "2h deep work: [ONE Big Thing]", "dueString": "every weekday at 6am", "priority": 2, "labels": ["process-goal"]},
  {"content": "1 outreach/день: [monthly priority]", "dueString": "every weekday", "priority": 3, "labels": ["process-goal"]},
  {"content": "30 мин продуктовые идеи", "dueString": "every day", "priority": 4, "labels": ["process-goal"]}
]}'
```

**Лимит:** Max 5-7 активных process goals.

### 3. Если process goals ЕСТЬ — проверь статус

- Активные (upcoming) → ✅ показать в отчёте
- Просроченные (overdue) → ⚠️ предупредить
- Устаревшие (не связаны с текущими целями) → рекомендовать удалить

### 4. Включи в отчёт

```html
<b>📋 Process Goals:</b>
• 2h deep work: [Client Project] → ✅ активен
• 1 outreach/день → ⚠️ просрочен
{N} активных | {M} требуют внимания
```

## Deleted Tasks Tracking (Steps 4d + 12)

**ЦЕЛЬ:** Todoist НЕ отдаёт список удалённых задач — удалённая задача просто исчезает. Чтобы отслеживать это, ведём снэпшот активных задач и сравниваем день ко дню.

### Хранилище

`vault/.snapshots/tasks-YYYY-MM-DD.json` — служебная папка (в .gitignore, НЕ часть хранилища мыслей).

Формат снэпшота (JSON):

<pre>{
  "date": "YYYY-MM-DD",
  "tasks": [
    {"id": "6gWg...", "content": "Созвон с Иваном Петровым", "due": "2026-06-05", "priority": 2}
  ]
}</pre>

### Step 4d — Сравнение (в начале обработки)

1. Получи ТЕКУЩИЕ активные задачи (широкое окно):
   `todoist-cli find-tasks-by-date '{"startDate": "today", "daysCount": 30, "limit": 100}'`
   Сохрани множество текущих id.

2. Найди ПОСЛЕДНИЙ предыдущий снэпшот: самый свежий `vault/.snapshots/tasks-*.json` с датой < сегодня. Если снэпшотов нет — пропусти сравнение (первый запуск), сразу к Step 12.

3. Закрытые сегодня задачи уже есть из шага 4a. Собери множество id и content закрытых.

4. **Удалённые = задачи из вчерашнего снэпшота, которых НЕТ среди текущих активных И НЕТ среди закрытых сегодня.** Если задача закрыта — это выполнение, НЕ удаление.

### Классификация удалённых

| Признак в content | Категория | Эмодзи |
|-------------------|-----------|--------|
| встреча / созвон / call / звонок / float / митинг / интервью | встреча отменена | 🤝 |
| остальное | задача удалена (передумал/неактуально) | 🗑 |

### Удалённые ВСТРЕЧИ — спросить причину + записать в карточку человека

Когда удалена задача-ВСТРЕЧА с конкретным человеком:

1. Извлеки имя человека из content (с alias-check по Rule C → vault/people/*.md).
2. Если человек найден → запиши факт в его карточку `people/{slug}.md` (или `business/crm/{slug}.md` если это лид) в секцию `## История взаимодействий`:
   `- YYYY-MM-DD: ❌ Встреча отменена (причина не указана) [[daily/YYYY-MM-DD]]`
3. В HTML-отчёте по таким встречам **явно попроси причину** — пользователь может ответить боту текстом, и причина будет дописана при следующей обработке.

**Дозапись причины (последующий ответ пользователя):**
Если пользователь присылает причину отмены («заболел», «перенесли», «отказались от сотрудничества») — найди последнюю запись `❌ Встреча отменена (причина не указана)` в карточке человека и ЗАМЕНИ её на:
`- YYYY-MM-DD: ❌ Встреча отменена — {причина} [[daily/YYYY-MM-DD]]`
Если причина значимая (отказ от сотрудничества) → также обнови `deal_status` в business/crm и MEMORY.md Pipeline.

### Удалённые обычные задачи

Просто фиксируй факт в отчёте. Причину не выпрашивай (мягкое «📌 укажи причину если важно» допустимо только для задач, бывших p1/p2).

### Step 12 — Сохранить снэпшот (в самом конце)

После всей обработки сохрани ТЕКУЩЕЕ состояние активных задач (из шага 4d.1) в `vault/.snapshots/tasks-{today}.json` в формате выше. Это станет базой сравнения для следующего /process. Пиши файл напрямую (Write), utf-8, ensure_ascii=false. Папка уже существует.

**Очистка:** храни снэпшоты за последние ~14 дней; более старые `tasks-*.json` можно удалить.

## Entry Format

## HH:MM [type]
Content

Types: [voice], [text], [forward from: Name], [photo], [achievement:voice], [achievement:text]

## Достижения — отдельная категория

Записи с маркером `[achievement:*]` — это самопохвала пользователя.

**Правила:**
- НЕ создавать задач в Todoist
- НЕ классифицировать как обычные мысли
- НЕ обрабатывать через decision tree
- Маркировать `<!-- ✓ processed: achievement -->` без обработки
- В отчёте — отдельная секция `<b>🏆 Достижения:</b>` со списком текстов

**В weekly/monthly дайджесте:**

Читай `references/achievements.md` — там 10 категорий и правила сбора.

Источники:
- `[achievement:*]` маркеры из daily/*.md → префикс 🏆
- Закрытые задачи Todoist (значимые) → префикс ✅
- События календаря (значимые) → префикс 📅

Распределяй по категориям, пустые скрывай, сортируй по количеству.

## Business Context Integration

**ТОЧКА ВХОДА:** `business/_index.md` — читай для понимания бизнес-контекста.

### Структура:
```
business/
├── _index.md       ← Статистика, обзор
├── crm/            ← ВСЁ: компании + сделки + проекты в одном файле
├── network/        ← Структура холдинга
└── events/         ← Мероприятия
```

### Распознавание упоминаний

При обработке entries ищи упоминания клиентов и проектов:

| Паттерн | Действие |
|---------|----------|
| "звонил [Client]" | Найти `business/crm/{client}.md`, добавить связь |
| "по проекту [Client]" | Найти `business/crm/{client}.md` |
| "встреча с [Client]" | Создать задачу + связать с `business/crm/{client}.md` |
| "отправил КП для [Client]" | Связать с `business/crm/{client}.md` |

### Поиск клиента по имени

1. Имя → kebab-case: "Acme Corp" → `acme-corp`, "Bi Group" → `bi-group`
2. Искать: `business/crm/{kebab-case}.md`
3. Если не найден — fuzzy search по `grep -l "{name}" business/crm/`

### Создание связей

Когда упомянут клиент/проект, добавляй wiki-links:

**В задачу:**
```
"Follow-up [[business/crm/acme-corp|Acme Corp]] по снекам"
```

**В thought:**
```
Связано с: [[business/crm/techco|TechCo]], [[business/crm/phonebrand-smm|PhoneBrand SMM]]
```

### Приоритет задач с бизнесом

| Условие | Приоритет |
|---------|-----------|
| Клиент с priority: High + deadline | p1 |
| Активный проект (In progress) | p2 |
| Клиент с priority: High | p2 |
| Клиент с priority: Mid | p3 |
| Prospect без срочности | p4 |

## Classification

task → Todoist (see references/todoist.md)
idea/reflection/learning → thoughts/ (see references/classification.md)

ENTITY ROUTING (см. references/classification.md § Entity Cards Detection):
- person mention → people/SLUG.md (create-or-update; bidirectional с companies)
- company mention → companies/SLUG.md (bidirectional с people)
- book/film → interests/books/SLUG.md или interests/films/SLUG.md (с recommended_by если упомянут источник)
- recipe → recipes/SLUG.md
- place (food) → places/food/CITY/SLUG.md
- place (хочу съездить) → places/visit-later/SLUG.md
- place (был, посетил, ездил, сходил) → places/visited/YYYY-MM-DD-SLUG.md  ← НОВОЕ
- travel (по календарю) → places/travels/YYYY-MM-DESTINATION.md
- habit ✓/✗ → habits/SLUG.md (по keywords)
- wish (предмет, можно подарить) → wishlist/items/SLUG.md  ← НОВОЕ (разделение)
- wish (опыт, активность, нельзя подарить как объект) → wishlist/experiences/SLUG.md  ← НОВОЕ
- gift idea для X → gifts/X-SLUG.md
- topic интерес → interests/topics/SLUG.md
- workout → health/workouts/SLUG.md, питание → health/nutrition/, метрика → health/tracking/

## Auto-discovery: повторяющиеся темы

Если в записях за период (текущий day + последние 2-3 дня) встречается **одна и та же тема 2+ раз** (например: Древний Рим, AI-агенты, конкретное хобби), а карточки `interests/topics/{тема}.md` ещё нет:

1. Создай `interests/topics/{slug}.md` со списком источников (ссылки на daily)
2. В отчёте отметь: `<b>🆕 Новая тема:</b> {название} ({N} упоминаний)`

Это помогает выявлять формирующиеся интересы.

## Family timeline

Если запись касается **членов семьи** (жена, дети, родители, родственники) — параллельно с обычной обработкой:

1. Обнови `people/{member}.md` — добавь событие в timeline-секцию
2. Формат: `- YYYY-MM-DD: {краткое событие} [[daily/YYYY-MM-DD]]`

Это нужно чтобы видеть ритм семьи и совместные активности отдельно от рабочих контактов.

При неоднозначности → НЕ создавать карточку, оставить маркер в daily:
HTML-комментарий с classification: ambiguous и пометкой что review нужен
client/project mention → link to Business/Projects + create task if actionable

## Projects Context Integration

**Точка входа:** `projects/_index.md`

### Структура:
```
projects/
├── _index.md       # Clients overview
├── clients/        # Clients
└── leads/          # Leads
```

### Распознавание упоминаний

| Паттерн | Файл |
|---------|------|
| "[Client A]" | projects/clients/{client-a}.md |
| "[Client B]" | projects/clients/{client-b}.md |
| "AI обучение", "воркшоп" | projects/ контекст |

### Отличие от Business

- **Business** = основной бизнес
- **Projects** = личные проекты (консалтинг, обучение)

Если entry упоминает AI/ML обучение — ищи в projects/ сначала.

## Contacts Context Integration

**Точка входа:** `contacts/_index.md`

### Распознавание имён в entries

Ищи паттерны:
- "созвонился с [Contact] из [Client]"
- "встреча с @username"
- "Имя Фамилия написал"

### Классификация

| Индикатор | Категория | Vault Link |
|-----------|-----------|------------|
| Known business clients | business | `business/crm/{client}` |
| AI/обучение expertise, known leads | projects | `projects/leads/{name}` |
| Остальные | personal | — |

### В отчёте

Если в entries упомянуты люди, добавь секцию:

```html
<b>👤 Упомянуто контактов:</b>
• [Contact Name] (business → [[business/crm/acme-corp]])
• [Contact Name] (personal)
```

## Priority Rules

p1 — Client deadline, urgent
p2 — Aligns with ONE Big Thing or monthly priority
p3 — Aligns with yearly goal
p4 — Operational, no goal alignment

## Process Goals Preference

When creating tasks, prefer PROCESS over OUTCOME formulations.

**Outcome (less effective):**
- "Закрыть сделку с X"
- "Запустить продукт"
- "Подготовить программу"

**Process (more effective):**
- "Отправить follow-up клиенту X" (actionable, controllable)
- "2h deep work на MVP" (time-bounded)
- "Показать драфт программы коллеге" (checkpoint)

**When to transform:**
- Entry sounds vague/outcome-focused → make it specific/process-focused
- User says "нужно сделать X" → create actionable next step, not X itself
- Goal mentioned → create task that MOVES TOWARD goal, not goal itself

See: references/process-goals.md for patterns and examples.

## Thought Categories

💡 idea → thoughts/ideas/
🪞 reflection → thoughts/reflections/
🎯 project → thoughts/projects/
📚 learning → thoughts/learnings/

## HTML Report Template

Output RAW HTML (no markdown, no code blocks):

📊 <b>Обработка за {DATE}</b>

<b>🎯 Текущий фокус:</b>
{ONE_BIG_THING}

<b>📓 Сохранено мыслей:</b> {N}
• {emoji} {title} → {category}/

<b>💡 Инсайты дня:</b>
• <b>{короткий заголовок мысли}</b> — 1-2 строки выжимки сути (не пересказ, а смысл)
(показывать только для today's thoughts; если 0 — скрыть секцию)

<b>✅ Создано задач:</b> {M}
• {task} <i>({priority}, {due})</i>

<b>🗑 Удалено из Todoist:</b> {D}
• 🤝 {встреча} — отменена <i>(укажи причину ответом, если важно)</i>
• 🗑 {задача} — удалена
(показывать только если есть удалённые; иначе скрыть секцию)

<b>❓ Уточнить людей:</b> {Q}
• «{как услышано}» — это {кандидат или новый человек}? <i>(ответь — привяжу)</i>
(показывать только если есть люди в карантине; иначе скрыть)

<b>🏢 Business Activity:</b>
• {client} — {action}
• {project} — {status update}
<i>Упомянуто клиентов: {N} | Проектов: {M}</i>

<b>📋 Process Goals:</b>
• {process goal 1} → {status}
• {process goal 2} → {status}
{N} активных | {M} требуют внимания
<i>Создано новых: {K}</i>

<b>📅 Загрузка на неделю:</b>
Пн: {n} | Вт: {n} | Ср: {n} | Чт: {n} | Пт: {n} | Сб: {n} | Вс: {n}

<b>⚠️ Требует внимания:</b>
• {overdue or stale goals}

<b>🔗 Новые связи:</b>
• [[Note A]] ↔ [[Note B]]

<b>⚡ Топ-3 приоритета:</b>
1. {task}
2. {task}
3. {task}

<b>📈 Прогресс:</b>
• {goal}: {%} {emoji}

<b>🧠 MEMORY.md:</b>
• {section} → {change description}
<i>(если обновлено)</i>

---
<i>Обработано за {duration}</i>

## If Already Processed

If all entries have `<!-- ✓ processed -->` marker, return status report:

📊 <b>Статус за {DATE}</b>

<b>🎯 Текущий фокус:</b>
{ONE_BIG_THING}

<b>📋 Process Goals:</b>
• {process goal 1} → {status}
• {process goal 2} → {status}
{N} активных | {M} требуют внимания

<b>📅 Загрузка на неделю:</b>
Пн: {n} | Вт: {n} | Ср: {n} | Чт: {n} | Пт: {n} | Сб: {n} | Вс: {n}

<b>⚠️ Требует внимания:</b>
• {overdue count} просроченных
• {today count} на сегодня

<b>⚡ Топ-3 приоритета:</b>
1. {task}
2. {task}
3. {task}

---
<i>Записи уже обработаны ранее</i>



## Дни рождения близких

### Daily check (при /process)

В начале обработки прочитай vault/people/*.md и найди дни рождения которые наступят **в следующие 3 дня**. Если найден — добавь в начало HTML отчёта блок:

```html
<b>🎂 Скоро ДР:</b>
⚠️ {Имя} — через {N} дней ({age} лет). Идеи в [[gifts/{slug}]]
```

### Weekly digest (14 дней вперёд)

В weekly:
- ≤7 дней — префикс ⚠️
- 8-14 дней — префикс 📅
Подтягивай 2-3 идеи из gifts/{slug}.md (секции Желания / Идеи, не Уже подарено).

### Monthly digest (30 дней вперёд)

В monthly — все ДР следующего месяца со списком идей подарков.

### Возраст

Считай возраст по `birthday` в frontmatter people-карточки. Формат frontmatter: `birthday: YYYY-MM-DD`.

### Не упоминать в отчёте если

- У человека нет `birthday:` в frontmatter
- ДР сегодня (то отдельный case: `🎉 Сегодня ДР у X!`)

## Meeting Outcomes (итоги встреч)

При обработке записей-итогов встреч (триггеры: "итоги общения", "встретился с", "встретилась с", "провели встречу", "диагностика с"):

### Что создать/обновить

1. **people/{slug}.md** — для каждого участника:
   - Проверь aliases (Rule 10) перед созданием новой карточки
   - Обнови `## История взаимодействий` или `## История` с датой и итогами
   - Если карточка новая — заполни role, контекст знакомства

2. **companies/{slug}.md** — для упомянутой компании:
   - website, индустрия, структура (key people via wiki-links)
   - `## Боли` — конкретный список (что болит у клиента)
   - `## Потенциальное сотрудничество` — что я предложил
   - Связи на people/ и business/crm/

3. **business/crm/{slug}.md** — CRM-карточка лида:
   - type: crm, priority (High/Mid/Low), status (Discovery/Nurture/Active/Won/Lost)
   - deal_status: nurture/active/won/lost, deal_deadline (дата next-step)
   - `## Следующий шаг` — конкретное действие с датой
   - История взаимодействий хронологически

4. **Todoist follow-up задача:**
   - content с wiki-links на people/companies
   - dueString = договорённая дата
   - priority p2 (hot) / p3 (warm)
   - labels: `client:{slug}`, `follow-up`
   - ОБЯЗАТЕЛЬНО реальный id из response (Rule 8)

### Что не делать

- ❌ Не оставлять итоги встречи только в daily — раскидать по карточкам
- ❌ Не создавать новых people для непроверенных имён (Rule 10)
- ❌ Не выдумывать дату follow-up — брать договорённость из текста

### Триггер кнопкой

Меню `Обработать → 🤝 Итоги встречи` — отдельный handler в process_menu.py, который запускает этот workflow.

---

## CRITICAL Rules — обязательные проверки

### Rule A: Verify task id after add-tasks

**После КАЖДОГО `todoist-cli add-tasks ...`:**

1. Возьми RAW response от todoist-cli
2. Распарси `data.tasks[].id` — это РЕАЛЬНЫЕ id от Todoist
3. В маркере daily пиши ТОЛЬКО эти id

**ЗАПРЕЩЕНО:**
- Выдумывать id (галлюцинация типа `6gf7CCcPX9JW42jQ`)
- Брать id из другой задачи
- Писать id без проверки response

**Если add-tasks вернул ошибку или пустой response → НЕ пиши никакой id, отметь как `<!-- ✗ FAILED: причина -->`**

### Rule B: Correction ≠ Complete

Если приходит запись-коррекция к предыдущей (формат: "Не X, а Y" / "ошибка распознавания" / "уточняю"):

1. Найди ОРИГИНАЛЬНУЮ задачу/карточку по id из предыдущего маркера
2. Используй `update-tasks` для исправления content
3. **НИКОГДА не используй complete-tasks** при корректировке
4. В маркере пиши: `<!-- ✓ correction → task updated, new content: ... -->`

**ЗАПРЕЩЕНО при коррекции:**
- complete-tasks (это маркер ВЫПОЛНЕНИЯ, не правки)
- delete-object (потеря данных)
- создание новой задачи + удаление старой (потеря id и истории)

### Rule C: Alias-check для имён в задачах

При создании задачи с именем человека ("связаться с X", "встреча с Y", "позвонить Z"):

1. Извлеки имя из текста
2. Загляни в vault/people/*.md frontmatter:
   - Поле `name:` (полное имя)
   - Поле `aliases:` (короткие/прозвища)
3. Если найден match (full или partial → similarity ≥ 0.6 ИЛИ полное совпадение с alias):
   - Используй каноническое имя из `name:` в content задачи
   - Добавь wiki-link `[[people/{slug}]]` в description
4. Если **НЕ найден**:
   - **Если запись из голоса** ([voice]) — пометь low-confidence, в daily маркере:
     `<!-- ⚠️ unknown person "X", possible speech recognition error -->`
   - Создай задачу с пометкой "(?)" в content для review
   - **НЕ создавай people/-карточку автоматически** для неизвестных имён из голоса
5. Если **запись текстовая** [text] — имя считается верным, можно создать people/-карточку

**Пример провала** (мусор типа "ВИЧ-корова") должен попасть в low-confidence, а не в Todoist.

### Rule D: Travel dates — только из карточки

Если в записи или отчёте упоминается **поездка / возвращение / прилёт / отъезд**:

1. **ОБЯЗАТЕЛЬНО** прочитай соответствующую `vault/places/travels/*.md`
2. Возьми ТОЧНЫЕ даты из frontmatter (`start_date`, `end_date`)
3. **НИКОГДА не используй "завтра"/"послезавтра" без сверки с карточкой**

**ЗАПРЕЩЕНО:**
- Писать "Завтра X — день возвращения" без чтения travel-карточки
- Прибавлять/вычитать дни из end_date "на глаз"
- Угадывать дату возвращения по start_date + N дней

**Если travel-карточка не найдена** — спроси у пользователя или пометь как unknown, не выдумывай дату.

---

## Allowed HTML Tags

<b> — bold (headers)
<i> — italic (metadata)
<code> — commands, paths
<s> — strikethrough
<u> — underline
<a href="url">text</a> — links

## FORBIDDEN in Output

NO markdown: **, ##, -, *, backticks
NO code blocks (triple backticks)
NO tables
NO unsupported tags: div, span, br, p, table

Max length: 4096 characters.

## References

Read these files as needed:
- references/about.md — User profile, decision filters
- references/classification.md — Entry classification rules
- references/todoist.md — Task creation details + recurring patterns
- references/goals.md — Goal alignment logic
- references/process-goals.md — Process vs outcome goals, transformation patterns
- references/links.md — Wiki-links building
- references/rules.md — Mandatory processing rules
- references/report-template.md — Full HTML report spec
- references/business.md — Business client/project context, search patterns
- references/contacts.md — Contacts search and classification

## Business Quick Reference

**Точка входа:** `business/_index.md`

**Поиск клиента:**
```
grep -l "Acme Corp" business/crm/
→ business/crm/acme-corp.md
```

**Активные сделки:**
```
grep -l "deal_status:" business/crm/
```

**High priority клиенты:**
```
grep -l "priority: High" business/crm/
```

**Frontmatter полей:**
- type: crm
- industry, priority, status, region, owner, responsible
- deal_status, deal_deadline (для активных сделок)
- updated

## Relevant Skills

- [[vault/.claude/skills/graph-builder/SKILL|graph-builder]] — Vault graph analysis
- [[vault/.claude/skills/todoist-ai/SKILL|todoist-ai]] — Todoist task management
