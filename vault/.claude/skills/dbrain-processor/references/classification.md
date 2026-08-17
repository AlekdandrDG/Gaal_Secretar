---
type: note
last_accessed: 2026-05-05
relevance: 0.1
tier: archive
---
# Entry Classification

## Work Domains → Categories

Based on user's work context (see [ABOUT.md](ABOUT.md)):

### Client Work
Брифы, стратегии, креатив, кампании, KPI, предложения

**Keywords:** [Client A], [Client B], [Client C], клиент, бриф, презентация, дедлайн, KPI

**→ Category:** task (p1-p2) → Todoist

### AI & Tech
Инструменты, модели, промпты, пайплайны, агенты

**Keywords:** GPT, Claude, модель, агент, API, пайплайн, автоматизация, интеграция

**→ Category:** learning или project → thoughts/

### Product
Идеи, гипотезы, MVP, юнит-экономика

**Keywords:** продукт, SaaS, MVP, гипотеза, монетизация, юнит-экономика, стартап

**→ Category:** idea или project → thoughts/

### Company Ops
Команда, процессы, автоматизация, найм, управление, финансы

**Keywords:** команда, найм, процесс, HR, финансы, [Your Business], агентство

**→ Category:** task или project (depends on urgency)

### Content
Посты, идеи, тезисы для Telegram и LinkedIn

**Keywords:** пост, @yourbrand, LinkedIn, контент, тезис, статья

**→ Category:** idea → thoughts/ideas/ или task если с дедлайном

---

## Decision Tree

```
Entry text contains...
│
├─ Client brand or deadline? ────────────────────> TASK (p1-p2)
│  ([Client A], [Client B], клиент, дедлайн, презентация)
│
├─ Operational/urgent? ──────────────────────────> TASK (p2-p3)
│  (нужно сделать, не забыть, позвонить, встреча)
│
├─ AI/tech learning? ────────────────────────────> LEARNING
│  (узнал, модель, агент, интеграция)
│
├─ Product/SaaS idea? ───────────────────────────> IDEA или PROJECT
│  (продукт, MVP, гипотеза, SaaS)
│
├─ Strategic thinking? ──────────────────────────> PROJECT
│  (стратегия, план, R&D, долгосрочно)
│
├─ Personal insight? ────────────────────────────> REFLECTION
│  (понял, осознал, философия)
│
└─ Content idea? ────────────────────────────────> IDEA
   (пост, тезис, контент)
```

---

## Business Client Detection

Entry mentions a known client (see business-context.md)?

```
├─ + deadline/urgency? → TASK (p1-p2) + client label
├─ + статус ("отправили КП", "выиграли")? → TASK + flag for CRM note
├─ + встреча/звонок? → TASK (p2) + [[client]] link
└─ просто упоминание? → Add [[client]] link only
```

### CRM Status Keywords (для информации в отчёте)

| Keywords | Интерпретация |
|----------|---------------|
| "подписали", "выиграли", "получили" | Позитивный исход |
| "отказали", "проиграли", "не пошли" | Негативный исход |
| "отправили КП", "подали" | В процессе |
| "ждём ответ", "на рассмотрении" | Ожидание |

---

## Apply Decision Filters

Перед сохранением спроси:
- Это масштабируется?
- Это можно автоматизировать?
- Это усиливает экспертизу или бренд?
- Это приближает к продукту или SaaS?

Если да на 2+ вопроса → повысить приоритет.

---

## Photo Entries

For `[photo]` entries:

1. Analyze image content via vision
2. Determine domain:
   - Screenshot клиентского материала → Client Work
   - Схема/диаграмма → AI & Tech или Product
   - Текст/статья → Learning
3. Add description to daily file

---

## Output Locations

| Category | Destination | Priority |
|----------|-------------|----------|
| task (client) | Todoist | p1-p2 |
| task (ops) | Todoist | p2-p3 |
| task (content) | Todoist | p3-p4 |
| idea | thoughts/ideas/ | — |
| reflection | thoughts/reflections/ | — |
| project | thoughts/projects/ | — |
| learning | thoughts/learnings/ | — |

---

## File Naming

```
thoughts/{category}/{YYYY-MM-DD}-short-title.md
```

Examples:
```
thoughts/ideas/2024-12-16-saas-pricing-model.md
thoughts/projects/2024-12-16-ai-agents-pipeline.md
thoughts/learnings/2024-12-16-claude-mcp-setup.md
```

---

## Thought Structure

Use preferred format:

```markdown
---
date: {YYYY-MM-DD}
type: {category}
domain: {Client Work|AI & Tech|Product|Agency Ops|Content}
tags: [tag1, tag2]
---

## Context
[Что привело к мысли]

## Insight
[Ключевая идея]

## Implication
[Что это значит для [Your Business]/продукта/стратегии]

## Next Action
[Конкретный шаг — не абстрактный]
```

---

## Anti-Patterns (ИЗБЕГАТЬ)

При создании мыслей НЕ делать:
- Абстрактные рассуждения без Next Action
- Академическая теория без применения к [Your Business]/продукту
- Повторы без синтеза (кластеризуй похожие!)
- Хаотичные списки без приоритетов
- Задачи типа "подумать о..." (конкретизируй!)

---

## MOC Updates

After creating thought file, add link to:
```
MOC/MOC-{category}s.md
```

Group by domain when relevant:
```markdown
## AI & Tech
- [[2024-12-16-claude-mcp-setup]] - MCP integration

## Product
- [[2024-12-16-saas-pricing-model]] - Pricing research
```


---

## Entity Cards Detection (people / companies / agreements / meetings / books / films / recipes / places / habits / wishlist / gifts)

В дополнение к thought-классификации (idea / task / learning / reflection / project) — entries могут описывать СУЩНОСТИ. Для каждой найденной сущности — create-or-update карточку.

### People

**Триггеры:** имя+контекст («встреча с X», «Y сказал», «звонил Z»)

**Действия:**
- Если people/SLUG.md существует → APPEND в «История взаимодействий»
- Если новое имя → create from templates/person-template.md
- Поля для извлечения: birthday («ДР X в [дата]»), family («жена Y», «сын», «дочь»), интересы («увлекается X», «любит Y»), компания («работает в X»)
- При упоминании компании → bidirectional: companies: [COMPANY-SLUG] в person + people: [PERSON-SLUG] в company

### Companies

**Триггеры:** название компании, бизнес/деал контекст

**Действия:**
- create-or-update companies/SLUG.md (slug из templates/company-template.md)
- Bidirectional links: people[] ↔ персоны companies[]

### Books / Films

**Триггеры (book):** «прочитал», «читаю», «книга X», «автор Y», «глава»
**Триггеры (film):** «посмотрел», «фильм/сериал», название с годом

**Действия:**
- create-or-update interests/books/SLUG.md или interests/films/SLUG.md
- Если паттерн «X посоветовал/рекомендует [название]»: set recommended_by: PERSON-SLUG И добавить запись в people/PERSON-SLUG.md секцию «Что советовал»

### Recipes

**Триггеры:** «приготовил», «рецепт», «кухня», ингредиенты

**Действия:** create-or-update recipes/SLUG.md. Если «рецепт от X» — set recommended_by.

### Places

**Триггеры (food):** кафе/ресторан/бар + город
**Триггеры (visit-later):** «хочу съездить», «классное место», «было бы интересно посетить» + топоним
**Триггеры (visited):** «был», «ездил», «сходил», «посетил», «свозил», «гуляли в» + конкретное место
**Триггеры (travel):** в календаре есть авиа/ж.д. событие — auto-create places/travels/YYYY-MM-DESTINATION.md со списком calendar_event_id-шек поездки

**Действия:**
- food: places/food/CITY/SLUG.md. Если «X порекомендовал» — set recommended_by.
- visit-later: places/visit-later/SLUG.md
- visited: places/visited/YYYY-MM-DD-SLUG.md (с кем был, впечатления, ссылки на attachments если есть)
- travel: связать с calendar event ID-шками, добавить заметки во время поездки

**ВАЖНО про visited:** если запись описывает посещённое место — создавай карточку в `places/visited/` ОТДЕЛЬНО от достижения. Достижение остаётся достижением, но место получает свою летопись.

### Habits

**Триггеры:** упомянуты ключевые слова из keywords: [] в существующих habits/SLUG.md

**Действия:**
- Найти соответствующую habit-карточку
- Проставить ✓ на сегодня (или ✗ если «не успел/не сделал»)
- Обновить streak и stats

### Wishlist (две подкатегории)

**Структура:**
- `wishlist/items/SLUG.md` — физические предметы (можно подарить): техника, гаджеты, аксессуары, книги в подарок
- `wishlist/experiences/SLUG.md` — опыт, активности, услуги (нельзя подарить как предмет): путешествия, обучения, события, концерты

**Триггеры (items):** «хочу [конкретный giftable item с ценой/брендом]» — предмет можно подержать в руках
**Триггеры (experiences):** «хочу попробовать/сходить/побывать на [событие/опыт]» — нематериальное желание

**Действия:**
- create-or-update wishlist/items/SLUG.md ИЛИ wishlist/experiences/SLUG.md, status: open
- Поле `shareable: true/false` — хочет ли пользователь чтобы это дарили (отдельная ось от items/experiences)
- Если уже куплено/случилось («нашёл/получил/купил/сходил X») — set status: fulfilled

**Различение:**
- «хочу Kindle ~40k» → `items/` (предмет)
- «хочу налокотник» → `items/`
- «хочу на римский фестиваль» → `experiences/`
- «хочу пройти курс по AI» → `experiences/`
- «хочу путешествовать в Рим» → `places/visit-later/` (там своя категория)

**Граница с places/visit-later:** если упомянуто конкретное место/город — это `places/visit-later/`. Если событие/активность без географии — это `wishlist/experiences/`.

### Agreements (договорённости / обязательства)

**Триггеры:** «договорились», «обещал», «должен прислать/сделать к», «жду от X», «взял на себя», «подтвердил что сделает», обязательство с суммой («выставит счёт на», «оплачу до»)

**Действия:**
- create-or-update `agreements/ГГГГ-ММ-ДД-slug.md` из templates/agreement-template.md
- Поля: `with` (wikilink на people/), суть, `direction` (my/their/mutual), `due`, `amount` (точная цифра, если звучала), `status: open`
- **Смена статуса существующей договорённости** (выполнена/отменена/перенесена): обнови `status` во frontmatter, а в `## History` ДОПИШИ строку с датой — старые строки НЕ удалять и НЕ переписывать
- MOC: добавь ссылку в MOC/MOC-agreements.md § Open (при закрытии — перенеси в § Closed)
- Bidirectional: у контрагента в people/*.md → ссылка в «Истории взаимодействий»

### Meetings (состоявшиеся встречи / созвоны)

**Триггеры:** «встретился с», «созвон с», «встреча с X (прошла)», «обсудили с», «был на встрече»

**Действия:**
- create-or-update `meetings/ГГГГ-ММ-ДД-slug.md` из templates/meeting-template.md
- Поля: `participants` (wikilinks people/), Итоги (3–7 пунктов фактов), Суммы и цифры (точные, если звучали), Следующие шаги
- Каждый следующий шаг-обязательство → отдельная agreement-карточка (см. выше) + взаимные ссылки
- MOC: добавь ссылку в MOC/MOC-meetings.md § Recent
- Bidirectional: у каждого участника в people/*.md «История взаимодействий» → ссылка на встречу
- НЕ создавать карточку для запланированной, но не состоявшейся встречи — это task

### Gifts (per-person)

**Триггеры:** «идея для X», «надо подарить X», «X любит Y» (где Y — потенциальный подарок)

**Действия:**
- create-or-update gifts/PERSON-SLUG.md
- Append в «Идеи»

### Ambiguity rule

Если не уверен в категории — **НЕ создавать** карточку, оставить в daily маркер:

    <!-- classification: ambiguous (book? recipe? mention?) — review -->

Лучше пропустить, чем создать ложную сущность.
