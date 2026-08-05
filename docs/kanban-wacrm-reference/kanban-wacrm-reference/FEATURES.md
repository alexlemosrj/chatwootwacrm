# Kanban WACRM — Reference Spec (for Chatwoot native port)

Source: previous Next.js WACRM tree (removed after this extraction).
Target: implement natively in Chatwoot (Rails + Vue 3).

## Features (v1 DoD)

| Feature | Behavior |
|---------|----------|
| Multi-pipeline | Dropdown selector; create new pipeline |
| Default seed | On empty account: "Sales Pipeline" + 5 stages |
| Default stages | New Lead, Qualified, Proposal Sent, Negotiation, Won (fixed colors/positions) |
| Drag deals across stages | Optimistic UI; persist `deals.stage_id` |
| Keyboard drag | Supported in WACRM via dnd-kit KeyboardSensor |
| Stage column totals | Sum of deal values in column |
| Deal cards | Title, contact initials, value, close date, won/lost badges, assignee avatar |
| Add deal | Header + per-column button → form sheet |
| Edit deal | Click card |
| Won / Lost / Reopen | Via form (`status`: open\|won\|lost) |
| Assignee | Agent/user dropdown |
| Currency per deal | ISO code; default from account |
| Account default currency | Settings |
| Stage management | Name, color swatches, reorder, add, delete (block if deals remain) |
| Delete pipeline | Cascades stages/deals |
| Analytics strip | Count, pipeline value, avg, weighted (stage probability 10%→100%), won/lost MTD |
| Filters | Not in v1 (pipeline switch only) |
| Intra-column reorder | Not in v1 |
| Realtime board | Not in v1 |

## Original WACRM file map (removed)

- `src/app/(dashboard)/pipelines/page.tsx` — orchestration
- `src/components/pipelines/pipeline-board.tsx` — DnD board
- `src/components/pipelines/deal-card.tsx`
- `src/components/pipelines/deal-form.tsx`
- `src/components/pipelines/pipeline-settings.tsx`
- `src/components/pipelines/pipeline-analytics.tsx`
- `src/lib/currency.ts`
- Migrations: `001` (tables), `002` (assignee + status), `021` (default_currency)

## Chatwoot mapping

| WACRM | Chatwoot |
|-------|----------|
| `accounts` | `Account` |
| `contacts` | `Contact` |
| `conversations` | `Conversation` |
| `profiles` / assignee | `User` via `AccountUser` |
| Supabase RLS | Rails account-scoped controllers |
| React + @dnd-kit | Vue 3 + SortableJS / vue-draggable-plus |

## Seed stages (colors)

1. New Lead — `#94a3b8` — position 0 — weight ~10%
2. Qualified — `#3b82f6` — position 1 — ~30%
3. Proposal Sent — `#8b5cf6` — position 2 — ~50%
4. Negotiation — `#f59e0b` — position 3 — ~70%
5. Won — `#22c55e` — position 4 — ~100%
