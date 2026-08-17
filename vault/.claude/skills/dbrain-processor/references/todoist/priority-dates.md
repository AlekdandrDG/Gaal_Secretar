---
type: note
last_accessed: 2026-07-17
relevance: 0.56
tier: cold
---
# Todoist — приоритеты и даты

## Priority by Domain

| Domain | Default | Override |
|--------|---------|----------|
| Client Work | p1-p2 | — |
| Agency Ops (urgent) | p2 | — |
| Agency Ops (regular) | p3 | — |
| Content (с дедлайном) | p2-p3 | — |
| Product/R&D | p4 | масштабируемость → p3 |
| AI & Tech | p4 | автоматизация → p3 |

### Priority Keywords

| Keywords | Priority |
|----------|----------|
| срочно, критично, дедлайн клиента | p1 |
| важно, приоритет, до конца недели | p2 |
| нужно, надо, не забыть | p3 |
| (strategic, R&D, long-term) | p4 |

### Priority Boost

Если запись матчит 2+ фильтра → +1 уровень приоритета:
- Это масштабируется?
- Это можно автоматизировать?
- Это усиливает экспертизу?
- Это приближает к продукту/SaaS?

## Date Mapping

| Context | dueString |
|---------|-----------|
| Client deadline | точная дата |
| Urgent ops | today / tomorrow |
| This week | friday |
| Next week | next monday |
| Strategic/R&D | in 7 days |
| Not specified | in 3 days |

### Russian → dueString

| Russian | dueString |
|---------|-----------|
| сегодня | today |
| завтра | tomorrow |
| послезавтра | in 2 days |
| в понедельник | monday |
| в пятницу | friday |
| на этой неделе | friday |
| на следующей неделе | next monday |
| через неделю | in 7 days |
| 15 января | January 15 |

## Task Title Style

Прямота, ясность, конкретика.

✅ «Отправить презентацию [Client A]» · «Созвон с командой по AI-агентам»
❌ «Подумать о презентации» · «Что-то с клиентом»
