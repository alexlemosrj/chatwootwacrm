# Chatwoot CRM Pro — Port Plan (v4.18.0)

## Objective

Build the next InfinityAI Chatwoot image on top of Chatwoot OSS v4.18.0 and port the native CRM/Kanban capabilities from:

- `alexlemosrj/chatwootwacrm` (native Chatwoot integration)
- `alexlemosrj/InfinityAI_System` (richer CRM/Kanban UX and domain)

The external KanbanWoot stack is considered legacy and must remain untouched until the native CRM has been validated in production.

## Non-negotiable rules

1. Base product is Chatwoot OSS v4.18.0.
2. Do not replace upstream Chatwoot files wholesale with old fork files.
3. Apply minimal patches to upstream files.
4. All CRM data is account-scoped using `account_id`.
5. Existing accounts and all future accounts must receive CRM availability automatically.
6. No destructive database migration.
7. Production rollout only after build, migrations and multi-account tests pass.
8. KanbanWoot is removed only after data/integration verification and backup.

## Phase 1 scope — CRM Pro

### Pipeline
- Multiple pipelines per account
- Create, rename and delete pipeline
- Default pipeline provisioning
- One default pipeline per account
- Dynamic stages
- Stage color
- Stage order
- Optional default probability
- Won/lost semantic stage support

### Deal
- Pipeline and stage
- Contact
- Conversation
- Assignee
- Title
- Value
- Currency
- Expected revenue
- Probability
- Priority stars
- Expected close date
- Status: open / won / lost
- Notes
- Campaign source / UTM metadata
- Custom attributes

### Activities
Types:
- call
- whatsapp
- meeting
- followup
- task
- email

States:
- planned
- completed
- cancelled

Activities may be attached to a deal and/or contact and assigned to a Chatwoot user.

### Chatter / History
Maintain an account-scoped CRM event timeline for:
- stage changes
- status changes
- assignment changes
- internal notes
- activity creation/completion
- system events

Do not duplicate Chatwoot messages. Conversation messages remain sourced from Chatwoot conversations/messages.

## Proposed Rails domain

### pipelines
- id
- account_id
- name
- is_default
- created_at
- updated_at

Constraints:
- account FK
- unique/default constraints enforced per account

### pipeline_stages
- id
- pipeline_id
- name
- position
- color
- default_probability
- is_won
- is_lost
- created_at
- updated_at

### deals
- id
- account_id
- pipeline_id
- pipeline_stage_id
- contact_id nullable
- conversation_id nullable
- assignee_id nullable
- title
- value
- currency
- expected_revenue
- probability
- priority_stars
- expected_close_date
- status
- notes
- campaign_source
- utm_data jsonb
- custom_attributes jsonb
- created_at
- updated_at

### crm_activities
- id
- account_id
- deal_id nullable
- contact_id nullable
- assignee_id nullable
- activity_type
- title
- start_at
- due_at
- completed_at nullable
- status
- notes
- created_at
- updated_at

### crm_events
- id
- account_id
- deal_id nullable
- contact_id nullable
- actor_id nullable
- event_type
- metadata jsonb
- created_at

## Multi-account isolation

Every top-level CRM record is scoped to `Current.account`.

Controllers must never fetch CRM records by global ID alone.

Examples:

```ruby
Current.account.pipelines.find(params[:id])
Current.account.deals.find(params[:id])
Current.account.crm_activities.find(params[:id])
```

Cross-account references must be rejected in model/service validation.

## Provisioning

### Existing accounts

After schema migration, run an idempotent backfill:

```ruby
Account.find_each do |account|
  Crm::ProvisionAccount.call(account)
end
```

### Future accounts

Provision through the account creation lifecycle/event system.

The API index endpoint should still call an idempotent provisioning guard as a fallback.

## Default pipeline

Default stages should be conservative and editable:

1. Novo Lead
2. Qualificado
3. Proposta
4. Negociação
5. Ganho

No customer-specific labels may be hard-coded.

## Frontend

Port the richer CRM behavior from InfinityAI_System into Chatwoot Vue components.

Views:
- Kanban
- Table

Kanban:
- drag/drop deals
- search
- stage totals
- deal count
- activity health
- contact
- assignee
- value
- priority
- expected close date

Deal detail:
- progress/stage bar
- won/lost
- commercial fields
- notes
- source/UTM
- linked Chatwoot contact
- linked Chatwoot conversation
- activities
- CRM history

## Chatwoot integration points

New files should be preferred where possible.

Upstream files that require minimal patches include:
- `app/models/account.rb`
- `config/routes.rb`
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`
- `app/javascript/dashboard/store/index.js`
- `app/javascript/dashboard/store/mutation-types.js`
- locale indexes/settings

Never replace these files with versions from the old fork.

## Permissions

Initial requirement:
- administrators and agents can access CRM according to account membership
- CRM permissions must not accidentally grant Chatwoot Settings/admin access

A dedicated CRM permission layer can be added later if required.

## Test gates

Backend:
- account isolation
- CRUD pipelines/stages/deals
- invalid cross-account references rejected
- default provisioning is idempotent
- stage deletion blocked when deals exist
- won/lost transitions
- activities
- event timeline

Frontend:
- routes
- sidebar visibility
- pipeline creation
- stage editing/reorder
- deal drag/drop with rollback on failure
- Kanban/table switching
- deal detail
- linked conversation/contact

Deployment:
- image builds
- assets compile
- `rails db:prepare` succeeds against a copy of production database
- backfill is idempotent
- both current accounts receive independent default pipelines
- no regression in inbox/conversations/reports/settings

## KanbanWoot retirement

Do not remove before native CRM validation.

Retirement checklist:
1. Identify whether KanbanWoot persists any business state outside Chatwoot.
2. Export/backup anything required.
3. Confirm account 2 native CRM.
4. Confirm account 6 native CRM.
5. Confirm no webhook/automation depends on KanbanWoot.
6. Rotate the exposed Chatwoot API token used by the old React build.
7. Remove KanbanWoot stack.
8. Remove its DNS/Traefik route if no longer needed.

## Deferred scope

Explicitly deferred:
- Clickmax-like marketing suite
- landing page builder
- checkout
- affiliate system
- membership/course hosting

These should not expand the v4.18 CRM migration.
