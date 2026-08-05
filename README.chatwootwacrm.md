# chatwootwacrm

Fork of [Chatwoot](https://github.com/chatwoot/chatwoot) with a native **Pipelines / Kanban** module inspired by [WACRM](https://github.com/ArnasDon/wacrm).

## What you get

- Full Chatwoot (inbox, contacts, channels, automations, …)
- **Pipelines** sidebar: multi-pipeline board, drag-and-drop deals, analytics, stage settings
- Deals linked to Chatwoot contacts/conversations (sidebar widget on the conversation panel)

## Stack

- Rails + Vue 3 (upstream Chatwoot)
- Postgres: **Supabase** (external)
- Redis: **Redis Cloud** or self-hosted (external)
- Deploy: Docker Compose on a VPS — see [docs/deploy-vps.md](docs/deploy-vps.md)

## Quick start (VPS)

```bash
cp .env.example .env   # fill SECRET_KEY_BASE, POSTGRES_*, REDIS_*
docker compose -f docker-compose.vps.yaml up -d --build
docker compose -f docker-compose.vps.yaml exec rails bundle exec rails db:chatwoot_prepare
```

Kanban UX reference (from WACRM): [docs/kanban-wacrm-reference/FEATURES.md](docs/kanban-wacrm-reference/FEATURES.md).

## License

Same as Chatwoot (MIT) for upstream code; Kanban additions are MIT as well.
