# Deploy Chatwoot + Kanban (Funis) na VPS — guia para o Alex

Branch a usar: **`wa-vinicius`**

Stack:

- **VPS:** Docker Compose com `rails` (web) + `sidekiq` (worker) — arquivo [`docker-compose.vps.yaml`](../docker-compose.vps.yaml)
- **Postgres:** Supabase (cloud)
- **Redis:** Redis Cloud **ou** Redis self-hosted (ver seção no final)

---

## A) Atualizar uma VPS que já está rodando Chatwoot

Use este fluxo se a instalação já existe e você só precisa puxar o Kanban / Funis desta branch.

```bash
# 1) Entre na pasta do projeto na VPS
cd /caminho/do/chatwootwacrm   # ajuste o path real

# 2) Baixe o código e mude para a branch
git fetch origin
git checkout wa-vinicius
git pull origin wa-vinicius

# 3) Rebuild e recreate dos containers (aplica JS/Vue + gems)
docker compose -f docker-compose.vps.yaml up -d --build --force-recreate

# 4) Rode migrações (cria tabelas pipelines / pipeline_stages / deals)
docker compose -f docker-compose.vps.yaml exec rails bundle exec rails db:migrate

# 5) Confirme que Redis está saudável (obrigatório — ver seção "Redis e menus sumindo")
docker compose -f docker-compose.vps.yaml exec rails bundle exec rails runner 'Redis.new(url: ENV["REDIS_URL"], password: ENV["REDIS_PASSWORD"].presence).ping'
# Esperado: "PONG"
```

### Checklist pós-update

1. Abra o `FRONTEND_URL` e faça login.
2. Na sidebar devem aparecer: **Caixa de Entrada, Conversas, Funis, Contatos, Relatórios, Campanhas, Central de Ajuda, Configurações**.
3. Em **Configurações → Caixas de entrada** deve ser possível conectar WhatsApp.
4. Abra **Funis** (Pipelines): na primeira visita o sistema cria um funil padrão (*Sales Pipeline*) com 5 etapas.
5. Idioma pt-BR: em Configurações de perfil/conta, confirme o idioma; labels do Kanban devem aparecer em português (*Funis*, *Adicionar funil*, *Adicionar negócio*, etc.).

Se **Contatos / Relatórios / Campanhas / Caixas de entrada** sumiram da sidebar, pule para a seção **Redis e menus sumindo** abaixo e rode o recovery.

---

## B) Primeira instalação (VPS do zero)

1. Clone e checkout:
   ```bash
   git clone <URL_DO_REPO> chatwootwacrm
   cd chatwootwacrm
   git checkout wa-vinicius
   ```

2. Env:
   ```bash
   cp .env.example .env
   ```
   Preencha no mínimo:
   - `SECRET_KEY_BASE` → `openssl rand -hex 64`
   - `FRONTEND_URL` → URL pública com HTTPS (ex.: `https://crm.seudominio.com`)
   - `POSTGRES_HOST` / `POSTGRES_PORT` / `POSTGRES_DATABASE` / `POSTGRES_USERNAME` / `POSTGRES_PASSWORD` (Supabase **Session pooler**)
   - `REDIS_URL` + `REDIS_PASSWORD`

3. Liberar o IP público da VPS no allowlist do Redis Cloud e, se houver, nas network restrictions do Supabase.

4. Subir:
   ```bash
   docker compose -f docker-compose.vps.yaml up -d --build
   docker compose -f docker-compose.vps.yaml exec rails bundle exec rails db:chatwoot_prepare
   ```

   **Crítico:** `db:chatwoot_prepare` só pode rodar com **Redis acessível**. Esse rake (e o `db:migrate`) chama `ConfigLoader`, que grava `ACCOUNT_LEVEL_FEATURE_DEFAULTS` em `installation_configs`. Se o Redis falhar (ex.: `WRONGPASS`), as contas nascem **sem feature flags** e a sidebar esconde Contatos, Relatórios, Campanhas, Central de Ajuda e **Configurações → Caixas de entrada** (WhatsApp).

5. Coloque Nginx ou Caddy na frente com TLS apontando para `127.0.0.1:3000` (ou exponha 3000 com cuidado).

6. Abra `FRONTEND_URL`, crie o admin, configure caixas de entrada (WhatsApp) e teste **Funis**.

---

## Redis e menus sumindo (recovery)

Depois que o Redis estiver saudável (`PONG`), rode:

```bash
docker compose -f docker-compose.vps.yaml exec rails bundle exec rails runner '
  ConfigLoader.new.process
  names = InstallationConfig.find_by!(name: "ACCOUNT_LEVEL_FEATURE_DEFAULTS")
    .value.select { |f| f["enabled"] || f[:enabled] }.map { |f| f["name"] || f[:name] }
  Account.find_each { |a| a.enable_features!(*names) }
  puts "Accounts updated: #{Account.count}; features enabled: #{names.size}"
'
```

Recarregue o browser (hard refresh). Os menus devem voltar.

---

## Pipelines / Kanban (Funis)

- Menu na sidebar: **Funis**.
- Primeira visita na conta cria o funil padrão com etapas: New Lead → Qualified → Proposal Sent → Negotiation → Won.
- É possível adicionar funis, negócios, arrastar entre etapas e abrir configurações do funil (renomear / etapas).
- Traduções pt-BR estão no frontend; não depende do Crowdin para o básico do Kanban.

---

## Trocar Redis Cloud → Redis em outra VPS

Dados do Redis são efêmeros (filas/cache). Não precisa de dump.

1. Na VPS do Redis:
   ```bash
   docker run -d --name chatwoot-redis --restart unless-stopped \
     -p 6379:6379 \
     redis:7-alpine redis-server --requirepass 'SENHA_FORTE'
   ```
2. Firewall: liberar 6379 **somente** do IP da VPS do Chatwoot.
3. No `.env` do Chatwoot:
   ```bash
   REDIS_URL=redis://IP_OU_HOST_DO_REDIS:6379
   REDIS_PASSWORD=SENHA_FORTE
   ```
4. Recreate:
   ```bash
   docker compose -f docker-compose.vps.yaml up -d --force-recreate
   ```
5. Smoke-test: login, mensagens, logs do Sidekiq. Se menus sumirem, rode o recovery da seção acima.
6. Desative a instância antiga no Redis Cloud.

---

## Comandos úteis

```bash
# Logs
docker compose -f docker-compose.vps.yaml logs -f rails
docker compose -f docker-compose.vps.yaml logs -f sidekiq

# Status
docker compose -f docker-compose.vps.yaml ps

# Console Rails
docker compose -f docker-compose.vps.yaml exec rails bundle exec rails c

# Ping Redis
docker compose -f docker-compose.vps.yaml exec rails bundle exec rails runner 'puts Redis.new(url: ENV["REDIS_URL"], password: ENV["REDIS_PASSWORD"].presence).ping'
```

---

## O que NÃO fazer

- Não rode `db:chatwoot_prepare` / `db:migrate` com Redis com senha errada ou IP bloqueado.
- Não commite `.env` (segredos).
- Não force-push em `main`/`master` sem alinhamento com o time.
