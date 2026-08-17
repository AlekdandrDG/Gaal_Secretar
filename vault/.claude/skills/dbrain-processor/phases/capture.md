---
type: note
last_accessed: 2026-05-05
relevance: 0.1
tier: archive
---
# Phase 1: CAPTURE

Read daily entries, classify them, and output structured JSON.

## Input
- `daily/{DATE}.md` — today's entries
- `goals/3-weekly.md` — current week focus
- `goals/2-monthly.md` — monthly priorities
- `goals/1-yearly-2026.md` — yearly goals

## Task

1. Read `daily/{DATE}.md`
2. For each entry (## HH:MM [type] block), classify:
   - **task** — actionable item → will become Todoist task
   - **idea** → will be saved to thoughts/ideas/
   - **reflection** → thoughts/reflections/
   - **learning** → thoughts/learnings/
   - **project** → thoughts/projects/
   - **crm_update** — mentions business client → update CRM
   - **agreement** — договорённость/обязательство (кто-то кому-то что-то должен) → agreements/
   - **meeting** — состоявшаяся встреча/созвон с итогами → meetings/
   - **skip** — already processed or not actionable
3. Detect entity mentions (company names, people, projects)
4. Align with goals (which goal does this serve?)

## Output Format

Print ONLY valid JSON (no markdown, no explanation):

```json
{
  "date": "2026-02-19",
  "one_big_thing": "[Client A] NCP: POST-LAUNCH stabilization",
  "entries": [
    {
      "time": "10:30",
      "type": "voice",
      "content": "Called Acme Corp about the project, discussed KPI",
      "classification": "task",
      "task_content": "Follow-up Acme Corp: send KPI report",
      "task_priority": 2,
      "task_due": "tomorrow",
      "entities": ["business/crm/acme-corp"],
      "goal_alignment": "ONE Big Thing"
    },
    {
      "time": "14:00",
      "type": "text",
      "content": "AI agents need layered memory",
      "classification": "idea",
      "title": "AI agents need layered memory with decay scoring",
      "description": "Pattern from analysis. Active memories decay if unused.",
      "category": "ideas",
      "tags": ["ai", "agents", "memory"],
      "entities": [],
      "goal_alignment": "yearly/AI Development"
    }
  ],
  "stats": {
    "total_entries": 5,
    "tasks": 2,
    "thoughts": 2,
    "crm_updates": 1,
    "agreements": 0,
    "meetings": 0,
    "skipped": 0
  }
}
```

## Classification Rules

### Task indicators
- "нужно", "надо", "сделать", "позвонить", "отправить", "подготовить"
- Deadline mentions (завтра, в пятницу, до конца недели)
- Follow-up mentions

### Thought indicators
- Insights, patterns, observations
- "понял что", "интересно что", "заметил"
- No clear action required

### CRM indicators
- Company name mention (known clients from CRM)
- Deal/project status change
- Meeting/call with client

### Agreement indicators
- «договорились», «обещал», «должен прислать/сделать к», «жду от», «взял на себя»
- Обязательство с суммой или сроком («выставит счёт на X», «оплачу до пятницы»)
- Fields: agreement_with (имена), agreement_what, agreement_direction (my|their|mutual), agreement_due, agreement_amount (если звучала)
- Одна запись может дать И meeting И agreements — классифицируй как meeting, договорённости укажи в meeting_next_steps

### Meeting indicators
- «встретился с», «созвон с», «обсудили с», «был на встрече» — встреча СОСТОЯЛАСЬ
- Запланированная встреча — это task, НЕ meeting
- Fields: meeting_participants (имена), meeting_outcomes (3–7 фактов), meeting_next_steps, meeting_amounts (точные цифры, если звучали)

### Process goal formulation
When creating task_content, prefer PROCESS over OUTCOME:
- WRONG: "Закрыть сделку с Acme Corp"
- RIGHT: "Отправить follow-up Acme Corp: KPI отчёт за февраль"

### Prose-as-title for thoughts
When creating thought titles, use CLAIMS not topic labels:
- WRONG: "Agent Memory System" (topic label)
- RIGHT: "AI agents need layered memory with decay scoring" (specific claim)
Test: "Since [[title]], ..." should read naturally.

## Important
- Mark entries with `<!-- ✓ processed -->` as "skip"
- Output ONLY JSON — no explanation, no markdown wrapping
