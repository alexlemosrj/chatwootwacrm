# Schema reference — pipelines / stages / deals

Adapt FKs to Chatwoot (`account_id` → accounts.id, `contact_id` → contacts.id, etc.).

## pipelines

- id (uuid/bigint PK)
- account_id (NOT NULL, FK accounts, CASCADE)
- name (string, NOT NULL)
- created_at, updated_at

## pipeline_stages

- id
- pipeline_id (FK pipelines CASCADE)
- name (NOT NULL)
- position (integer, NOT NULL, default 0)
- color (string, default `#3b82f6`)
- created_at, updated_at
- index on pipeline_id

## deals

- id
- account_id (NOT NULL)
- pipeline_id (FK pipelines CASCADE)
- stage_id (FK pipeline_stages)
- contact_id (nullable, FK contacts SET NULL)
- conversation_id (nullable, FK conversations SET NULL)
- assignee_id (nullable, FK users SET NULL) — was `assigned_to` in WACRM
- title (NOT NULL)
- value (decimal 12,2, default 0)
- currency (string, default `USD`)
- notes (text)
- expected_close_date (date)
- status (string: `open` | `won` | `lost`, default `open`)
- created_at, updated_at
- indexes: pipeline_id, stage_id, account_id, assignee_id, contact_id

## TypeScript shapes (WACRM)

```ts
interface Pipeline {
  id: string
  account_id: string
  name: string
  created_at: string
}

interface PipelineStage {
  id: string
  pipeline_id: string
  name: string
  position: number
  color: string
  created_at: string
}

type DealStatus = 'open' | 'won' | 'lost'

interface Deal {
  id: string
  account_id: string
  pipeline_id: string
  stage_id: string
  contact_id: string | null
  conversation_id?: string | null
  assigned_to?: string | null  // → assignee_id in Chatwoot
  title: string
  value: number
  currency: string
  notes?: string | null
  expected_close_date?: string | null
  status: DealStatus
  created_at: string
  updated_at: string
}
```
