# Deploy Chatwoot + Kanban (Funis) — VPS nova (do zero)

Guia para o **Alex** instalar em uma **VPS limpa**. Branch: **`wa-vinicius`**.

## Arquitetura

| Peça | Onde roda |
|------|-----------|
| App web (`rails`) + worker (`sidekiq`) | VPS (Docker Compose) — [`docker-compose.vps.yaml`](../docker-compose.vps.yaml) |
| Postgres | Supabase (cloud) |
| Redis | Redis Cloud **ou** Redis em outra máquina (ver opcional no final) |

A VPS **não** sobe Postgres nem Redis localmente neste compose.

---

## Pré-requisitos (antes de clonar)

1. **VPS** com Ubuntu (ou similar), IP público, acesso SSH root/sudo.
2. **Domínio** apontando para o IP da VPS (ex.: `crm.seudominio.com`) — necessário para HTTPS e WhatsApp.
3. **Supabase** com projeto Postgres pronto. Use a connection string do **Session pooler** (não a direta, se o IP da VPS mudar com frequência). Anote:
   - host, porta, database, user, password
4. **Redis** (Cloud ou self-hosted) com host, porta e senha. Libere o **IP público da VPS** no allowlist do Redis Cloud **antes** do `db:chatwoot_prepare`.
5. Na VPS, instale Docker + Compose plugin:
   ```bash
   # Exemplo Ubuntu
   sudo apt update && sudo apt install -y ca-certificates curl git
   # Instale Docker Engine + Compose seguindo a doc oficial:
   # https://docs.docker.com/engine/install/ubuntu/
   docker --version
   docker compose version
   ```

---

## 1) Clone do repositório

```bash
cd /opt   # ou outro path permanente
sudo mkdir -p /opt && cd /opt
git clone <URL_DO_REPO> chatwootwacrm
cd chatwootwacrm
git checkout wa-vinicius
```

Confirme a branch:

```bash
git branch --show-current   # deve ser: wa-vinicius
```

---

## 2) Arquivo `.env`

```bash
cp .env.example .env
nano .env   # ou vim
```

Preencha **no mínimo** (produção):

```bash
# Segurança
SECRET_KEY_BASE=   # gerar: openssl rand -hex 64
RAILS_ENV=production

# URL pública (com HTTPS depois do proxy)
FRONTEND_URL=https://crm.seudominio.com
FORCE_SSL=true

# Postgres (Supabase Session pooler)
POSTGRES_HOST=aws-0-xxx.pooler.supabase.com
POSTGRES_PORT=5432
POSTGRES_DATABASE=postgres          # ou o nome do DB do projeto
POSTGRES_USERNAME=postgres.xxxxx
POSTGRES_PASSWORD=sua_senha
# Se aparecer EMAXCONNSESSION (pool_size: 15), use Transaction pooler:
# POSTGRES_PORT=6543
# POSTGRES_PREPARED_STATEMENTS=false

# Redis
REDIS_URL=redis://SEU_HOST_REDIS:6379
REDIS_PASSWORD=sua_senha_redis

# Signup: deixe false em produção se não quiser auto-cadastro aberto
ENABLE_ACCOUNT_SIGNUP=false
```

Gere a secret:

```bash
openssl rand -hex 64
# cole o resultado em SECRET_KEY_BASE=
```

**Não** commite o `.env`.

---

## 3) Firewall e allowlists

- Na VPS: liberar **22** (SSH), **80** e **443** (HTTP/HTTPS). A porta **3000** pode ficar só em `127.0.0.1` se o Nginx/Caddy estiver na mesma máquina.
- No **Redis Cloud**: allowlist com o IP público da VPS.
- No **Supabase**: se houver network restrictions, liberar o mesmo IP.

Teste Redis **antes** de preparar o banco (de uma máquina com acesso, ou depois do container subir — ver passo 5).

---

## 4) Build e start dos containers

```bash
cd /opt/chatwootwacrm
docker compose -f docker-compose.vps.yaml up -d --build
docker compose -f docker-compose.vps.yaml ps
```

Espere `rails` e `sidekiq` ficarem `Up`. Acompanhe o build se necessário:

```bash
docker compose -f docker-compose.vps.yaml logs -f rails
```

---

## 5) Validar Redis (obrigatório antes do prepare)

```bash
docker compose -f docker-compose.vps.yaml exec rails \
  bundle exec rails runner 'puts Redis.new(url: ENV["REDIS_URL"], password: ENV["REDIS_PASSWORD"].presence).ping'
```

Esperado: `PONG`.

Se falhar (`WRONGPASS`, timeout, connection refused): **não** rode o passo 6. Corrija senha/URL/allowlist e teste de novo.

---

## 6) Preparar banco (migrate + seeds de config)

Com Redis em `PONG`:

```bash
docker compose -f docker-compose.vps.yaml exec rails \
  bundle exec rails db:chatwoot_prepare
```

Isso cria as tabelas (incluindo **pipelines / stages / deals** do Kanban) e carrega configs de feature flags.

### Por que Redis precisa estar ok aqui

`db:chatwoot_prepare` (e `db:migrate`) roda `ConfigLoader`, que grava `ACCOUNT_LEVEL_FEATURE_DEFAULTS`. Se o Redis falhar no meio, as contas nascem **sem feature flags** e a sidebar esconde Contatos, Relatórios, Campanhas, Central de Ajuda e **Configurações → Caixas de entrada** (WhatsApp).

Se isso acontecer depois, use a seção **Recovery de menus** no final.

---

## 7) Proxy HTTPS (Nginx ou Caddy)

Aponte o domínio para `127.0.0.1:3000` (container `rails`).

Exemplo mínimo **Caddy** (`/etc/caddy/Caddyfile`):

```
crm.seudominio.com {
  reverse_proxy 127.0.0.1:3000
}
```

Exemplo mínimo **Nginx** (depois de emitir certificado com Certbot):

```nginx
server {
  listen 443 ssl http2;
  server_name crm.seudominio.com;

  # ssl_certificate / ssl_certificate_key via Certbot

  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
```

Confirme que `FRONTEND_URL` no `.env` é exatamente a URL HTTPS pública. Se mudar o `.env`:

```bash
docker compose -f docker-compose.vps.yaml up -d --force-recreate
```

---

## 8) Primeiro acesso e configuração

1. Abra `https://crm.seudominio.com` e crie a conta admin (ou use o fluxo de signup conforme `ENABLE_ACCOUNT_SIGNUP`).
2. Na sidebar devem aparecer: **Caixa de Entrada, Conversas, Funis, Contatos, Relatórios, Campanhas, Central de Ajuda, Configurações**.
3. **Configurações → Caixas de entrada** → conectar WhatsApp.
4. Abra **Funis**: na primeira visita a conta recebe um funil padrão (*Sales Pipeline*) com 5 etapas.
5. Em perfil/conta, idioma **Português (Brasil)** — labels do Kanban em pt-BR (*Funis*, *Adicionar funil*, *Adicionar negócio*, etc.).

---

## 9) Super Admin — master cria clientes (multi-tenant SaaS)

Modelo: **você (master)** provisiona cada cliente; **o cliente** entra no app, conecta WhatsApp e usa Funis/CRM sozinho.

| Quem | Onde | Faz o quê |
|------|------|-----------|
| Master (`SuperAdmin`) | `/super_admin` | Cria Accounts, Users e vincula o cliente como administrator |
| Cliente | `/app` | Login próprio, WhatsApp, Funis, conversas |

URL do painel master:

`https://SEU_DOMINIO/super_admin`

No dashboard `/app`, usuários `SuperAdmin` também veem **Console de Super Admin** (ícone castelo) no menu do perfil — igual ao Chatwoot padrão. É preciso **logout/login** depois de promover alguém a SuperAdmin para o item aparecer.

Login do Super Admin é **separado** do dashboard (Devise em `/super_admin`), mesmo e-mail/senha se o usuário for `type: SuperAdmin`.

### Criar o primeiro Super Admin na VPS

Depois do `db:chatwoot_prepare` e com Redis ok:

```bash
docker compose -f docker-compose.vps.yaml exec rails bundle exec rails runner '
  email = "admin@seudominio.com"   # ajuste
  password = "SenhaForteAqui!"     # ajuste
  u = User.find_by(email: email)
  if u
    u.update!(type: "SuperAdmin", password: password)
    u.confirm unless u.confirmed?
  else
    u = SuperAdmin.new(name: "Master", email: email, password: password)
    u.skip_confirmation!
    u.save!
  end
  puts "SuperAdmin ok: #{u.email} id=#{u.id}"
'
```

### Fluxo para liberar um cliente novo (obrigatório completo)

Criar só a Account **não basta**. Sem User + AccountUser administrator, ninguém entra na conta.

1. Abrir `/super_admin` e entrar com o master.
2. **Accounts** → New → nome da empresa do cliente (ex.: Pantoja).
3. **Users** → New → nome, e-mail e senha do cliente (ex.: Thiago).
4. Abrir a Account criada → **Account Users** → Add → selecionar o User → role **administrator**.
5. Entregar ao cliente: URL do app (`FRONTEND_URL`), e-mail e senha.
6. O cliente faz login em `/app` → **Configurações → Caixas de entrada** → WhatsApp → usa **Funis**.

O master **não precisa** estar vinculado à Account do cliente para o SaaS funcionar. Só vincule o master como `AccountUser` se quiser abrir a conta do cliente no seletor de contas do `/app` para suporte.

### Checklist rápido pós-criação

- Cliente loga e vê menus (Contatos, Funis, Configurações → Caixas de entrada).
- Se menus faltarem nessa Account, rode o **Recovery de menus** (seção abaixo) — features padrão por conta.

---

## Funis (Kanban)

- Menu: **Funis**.
- Funil padrão: New Lead → Qualified → Proposal Sent → Negotiation → Won.
- Dá para criar funis, negócios, arrastar entre etapas e editar etapas nas configurações do funil.
- Traduções pt-BR já vêm na branch; não depende do Crowdin para o básico.

---

## Recovery de menus (se sumirem Contatos / WhatsApp / etc.)

Só depois de Redis responder `PONG`:

```bash
docker compose -f docker-compose.vps.yaml exec rails bundle exec rails runner '
  ConfigLoader.new.process
  names = InstallationConfig.find_by!(name: "ACCOUNT_LEVEL_FEATURE_DEFAULTS")
    .value.select { |f| f["enabled"] || f[:enabled] }.map { |f| f["name"] || f[:name] }
  Account.find_each { |a| a.enable_features!(*names) }
  puts "Accounts updated: #{Account.count}; features enabled: #{names.size}"
'
```

Hard refresh no browser.

---

## Opcional: Redis self-hosted em outra VPS

Dados do Redis são efêmeros (filas/cache).

```bash
# Na VPS do Redis
docker run -d --name chatwoot-redis --restart unless-stopped \
  -p 6379:6379 \
  redis:7-alpine redis-server --requirepass 'SENHA_FORTE'
```

Firewall: porta **6379** só do IP da VPS do Chatwoot.

No `.env` do Chatwoot:

```bash
REDIS_URL=redis://IP_DO_REDIS:6379
REDIS_PASSWORD=SENHA_FORTE
```

```bash
docker compose -f docker-compose.vps.yaml up -d --force-recreate
# teste PONG de novo; se menus falharem, rode o Recovery
```

---

## Comandos úteis

```bash
docker compose -f docker-compose.vps.yaml logs -f rails
docker compose -f docker-compose.vps.yaml logs -f sidekiq
docker compose -f docker-compose.vps.yaml ps
docker compose -f docker-compose.vps.yaml exec rails bundle exec rails c
```

---

## Não faça

- Não rode `db:chatwoot_prepare` com Redis com senha errada ou IP bloqueado.
- Não deixe `FRONTEND_URL` em `http://0.0.0.0:3000` em produção.
- Não commite `.env`.
