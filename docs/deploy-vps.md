# Deploy Chatwoot + Kanban on a VPS (Docker)

## Architecture

- **VPS:** Docker Compose runs `rails` (web) + `sidekiq` (worker) only — see [`docker-compose.vps.yaml`](../docker-compose.vps.yaml)
- **Postgres:** Supabase (cloud)
- **Redis:** Redis Cloud (or self-hosted — see below)

## First-time setup

1. Clone the repo on the VPS and checkout your branch.
2. Copy env:
   ```bash
   cp .env.example .env
   # Fill SECRET_KEY_BASE (openssl rand -hex 64), FRONTEND_URL,
   # POSTGRES_HOST/PORT/DATABASE/USERNAME/PASSWORD (Supabase Session pooler),
   # REDIS_URL + REDIS_PASSWORD
   ```
3. Allowlist the VPS public IP in Redis Cloud (and Supabase network restrictions if any).
4. Build and start:
   ```bash
   docker compose -f docker-compose.vps.yaml up -d --build
   docker compose -f docker-compose.vps.yaml exec rails bundle exec rails db:chatwoot_prepare
   ```
5. Put Nginx/Caddy in front with TLS pointing to `127.0.0.1:3000` (or expose 3000 carefully).
6. Open `FRONTEND_URL`, create admin account, configure inboxes.

## Swap Redis Cloud → Redis on another VPS

Redis data is ephemeral (queues/cache). No dump required.

1. On Redis VPS:
   ```bash
   docker run -d --name chatwoot-redis --restart unless-stopped \
     -p 6379:6379 \
     redis:7-alpine redis-server --requirepass 'STRONG_PASSWORD'
   ```
2. Firewall: allow 6379 only from Chatwoot VPS IP.
3. Update Chatwoot `.env`:
   ```bash
   REDIS_URL=redis://NEW_HOST:6379
   REDIS_PASSWORD=STRONG_PASSWORD
   ```
4. `docker compose -f docker-compose.vps.yaml up -d --force-recreate`
5. Smoke-test login / messaging / Sidekiq logs.
6. Delete old Redis Cloud instance.

## Pipelines (Kanban)

After deploy, open **Pipelines** in the sidebar. First visit seeds a default Sales Pipeline with five stages.
