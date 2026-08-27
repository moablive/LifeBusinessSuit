# 📊 LifeBusinessSuit — Overview de Estado

**Data da auditoria:** 2026-08-26
**Escopo:** os 4 apps da solution + camada de deploy
**Método:** um agente auditor independente por app (somente leitura), com verificação cruzada dos achados transversais.

---

## 1. Quadro-resumo

| App | Repo | Visibilidade | Branch | Último commit | Commits | Working tree | LOC | Containers |
|---|---|---|---|---|---|---|---|---|
| **LBSTTSAPP** | `moablive/LBSTTSAPP` | 🔒 privado | `master` | `27234d6` · 25/08 | 11 | limpo | ~5.3k | 3/3 up |
| **MoneyAPP** | `moablive/MoneyAPP` | ⚠️ **PÚBLICO** | `main` | `88f1af4` · 26/08 | 146 | limpo | ~21.1k | 3/3 up |
| **NotesAPP** | `moablive/NotesAPP` | 🔒 privado | `master` | `54818ae` · 26/08 | 25 | limpo | ~11.7k | 3/3 up |
| **TodoAPP** | `moablive/TodoAPP` | 🔒 privado | `main` | `2d943a0` · 26/08 | 50 | 3 modificados | ~13.5k | 3/3 up |

**Maturidade:** todos os quatro convergem para o mesmo perfil — *funcional em produção, engenharia imatura*. Zero testes automatizados, zero CI e zero linter efetivo nos 4. A única barreira de qualidade real é o `tsc --strict`, e apenas MoneyAPP e LBSTTSAPP o forçam no `docker build`.

**Ressalva:** NotesAPP está implantado mas ainda **não adotado** — o banco tem 1 nota, 2 workspaces e 2 usuários. É deploy funcional em pré-uso, não produção com carga.

---

## 2. 🔴 Achado crítico — credenciais de infraestrutura expostas publicamente

O arquivo `.claude/settings.local.json` foi versionado por engano em **MoneyAPP** e **TodoAPP**. Ele carrega, dentro de strings da lista `permissions.allow` (comandos `curl` e `psql` colados na allowlist):

- **2 tokens de API da Cloudflare** (prefixo `cfut_`), um deles com permissão de `purge_cache`
- **1 Cloudflare Zone ID**
- **A senha do superusuário PostgreSQL `admin_root`**, repetida em DSN e em `PGPASSWORD=` inline

### Por que isto é grave e não apenas desleixo

| Fato | Verificação |
|---|---|
| Os **mesmos dois tokens** estão nos dois repositórios | fingerprints SHA-256 idênticos (`eb747ea22e2a`, `02c7d85917ad`) |
| **`moablive/MoneyAPP` é um repositório PÚBLICO** | `gh repo view` → `PUBLIC` |
| O arquivo **está presente em `origin/main`** do repo público | `git cat-file -e origin/main:.claude/settings.local.json` → existe |
| Entrou em **2026-06-18** (`043f533`) e nunca saiu | 2 commits tocam o arquivo, ambos em `origin/main` |

Ou seja: **as credenciais estão publicamente legíveis no GitHub há ~2 meses.** Devem ser tratadas como comprometidas, independentemente de haver evidência de uso indevido.

### Ação necessária, nesta ordem

1. **Revogar os 2 tokens Cloudflare** no dashboard (não editar o arquivo primeiro — revogar primeiro).
2. **Rotacionar a senha do Postgres `admin_root`** e atualizar `shared.env` + os `.env` de cada app.
3. `git rm --cached .claude/settings.local.json` nos dois repos e adicionar ao `.gitignore`.
4. **Reescrever o histórico** (`git filter-repo` ou BFG) + force-push. Remover só no HEAD não adianta: o blob continua acessível por SHA e nos forks/caches do GitHub.
5. Considerar tornar `MoneyAPP` privado, ou ao menos auditar os logs de acesso da Cloudflare no período.

> **Nota:** `NotesAPP` também versiona um `apps/bot/.claude/settings.local.json`, mas **sem segredos** — só concede `Bash(docker exec *)`/`Bash(docker run *)`. Deve sair do versionamento por higiene, não por urgência. `LBSTTSAPP` não versiona nenhum.

---

## 3. Estado operacional

**Os 12 containers do LBS estão no ar**, na rede externa `awl_network`, todos com `restart: unless-stopped`:

| App | backend | frontend | bot |
|---|---|---|---|
| MoneyAPP | ✅ 2h *(healthy)* | ✅ 8h | ✅ 2h |
| NotesAPP | ✅ 2h *(healthy)* | ✅ 8h | ✅ 2h |
| TodoAPP | ✅ 2h *(healthy)* | ✅ 3h | ✅ 2h |
| LBSTTSAPP | ✅ 8h *(healthy)* | ✅ 8h *(`:5173`)* | ✅ 8h |

Nenhum restart em loop, logs limpos. TodoAPP mostra atividade real (bot entregando lembretes, `calendar-sync` processando 129 eventos). Apenas o frontend do LBSTTSAPP publica porta no host (`5173`); os demais são acessados via Cloudflare Tunnel.

**Arquitetura confirmada:** nenhum app sobe Postgres próprio — todos anexam ao container compartilhado. Auth delegada ao LoginHUB em todos. Cache em memória, sem Redis.

---

## 4. Estado por app

### 💰 MoneyAPP — o mais maduro, e o mais exposto
PWA financeira: transações, contas, cartões com faturas isoladas, empréstimos, assinaturas, investimentos. 146 commits, 58 endpoints, 10 tabelas, 13 views. Bot com scan de comprovante por foto e comandos de voz.

- 🔴 Credenciais públicas (§2)
- 🔴 **`.pnpm-store` versionado: 19.848 dos 20.089 arquivos rastreados.** `.git` = 163 MB para ~21k LOC. Não está no `.gitignore`.
- 🟠 **4 migrations fora do `_journal.json`** (`0011`–`0014`, todas da transição para LoginHUB). O migrator do Drizzle lê só o journal — um banco recriado do zero **não** as recebe e diverge de produção.
- 🟠 `ALLOW_LEGACY_BOT_DELEGATION` ainda tem default `true`. O bot já repassa JWT desde `c695fe1`; o flag existe para ser desligado, e enquanto o default não muda o caminho de delegação cega segue aberto.
- 🟡 `db:generate`/`db:migrate`/`db:studio` da raiz filtram `@moneyapp/backend`, que não tem esses scripts — quem os tem é `@moneyapp/db`. Os três comandos estão quebrados.
- 🟡 Migrations não rodam no boot; é passo manual não documentado no compose.

### ✅ TodoAPP — o único com trabalho não commitado
Tarefas com grupos, recorrência, 3 views (Lista/Calendário/Kanban), Web Push VAPID, export/subscrição ICS, integração de leitura com o MoneyAPP.

- 🔴 Credenciais públicas via arquivo compartilhado (§2)
- 🟠 **3 arquivos modificados, +77/−20** — a feature `GET /api/integrations/moneyapp/status` (esconder camada MoneyAPP para quem não tem vínculo) está **completa ponta a ponta**, só falta o commit.
- 🟠 Colisão de numeração em migrations `0011`/`0013`/`0014`/`0015` — geradas pelo drizzle-kit misturadas com SQL manual no mesmo prefixo. Ordem de aplicação ambígua.
- 🟡 Código morto herdado do MoneyAPP: `investments.ts` (×2), `shares.ts`, `categories.ts`, dependência `argon2`. O `package.json` da raiz ainda se descreve como *"PWA de controle financeiro pessoal"*.
- 🟡 `CalendarView.vue` com **1.816 linhas** — concentra recorrência, camada MoneyAPP, feriados, busca e 3 modos de visualização.
- 🟡 README documenta `POST /api/auth/login`, rota **removida**; e diz que `user_id` é o `telegramId`, contrariando a migração para `loginhub_id`.

### 📓 NotesAPP — deploy funcional, mas o schema é de outro app
Notion + Obsidian: editor de blocos Tiptap, grafo de links bidirecionais, workspaces. 35 dias de vida, clonado do TodoAPP.

- 🔴 **`.pnpm-store` versionado: 22.000 dos 22.190 arquivos.** `.git` = 180 MB para 11,7k LOC.
- 🔴 **A cadeia de migrations Drizzle é do MoneyAPP e é inaplicável.** `0000_*.sql` cria `accounts`, `loans`, `transactions` — **nenhuma migration cria a tabela `notes`**. `__drizzle_migrations` tem 0 linhas: o migrator nunca rodou. O schema real veio de `init.sql` + `migrate.sql` + `alter.ts`. **O passo 3 do README (`pnpm db:migrate`) corromperia um ambiente novo.**
- 🔴 **Vazamento de stack trace ao cliente.** `apps/backend/src/app.ts` tem o comentário *"don't leak stack traces"* e logo abaixo devolve `details` e `stack` no JSON de erro 500.
- 🟠 **Lembretes nunca disparam.** Existe `notes.remind_at`, `reminder_settings`, `push_subscriptions`, e `web-push` instalado — mas não há cron, `setInterval` nem worker em lugar nenhum. Funcionalidade configurável e inerte.
- 🟠 `esbuild` fixado em `0.21.5` por `pnpm.overrides` — faixa afetada por **GHSA-67mh-4wv8-2f99** (impacto restrito a dev server), corrigida em 0.25.0. O override é justamente o que impede a correção subir.
- 🟡 11 `.sql` órfãos alterando `tasks`/`task_groups`, tabelas que não existem aqui. `packages/loginhub-*` são código morto, com 2 `.tgz` binários commitados.
- 🟡 `NODE_ENV=development` no bot em produção (`env_file` vence o `ENV` do Dockerfile).
- 🟡 `package.json` da raiz ainda diz `"name": "todoapp"` / *"controle financeiro pessoal"*.

### 🔊 LBSTTSAPP — o mais enxuto e o mais limpo
Text-to-speech: recebe texto, foto ou PDF, detecta idioma via Ollama, traduz e sintetiza voz com `edge-tts`. 12 idiomas, 3 velocidades.

- ✅ **Nenhum segredo commitado.** `.gitignore` correto, `.env` nunca apareceu no histórico.
- ✅ Sem `.pnpm-store` versionado — 63 arquivos rastreados, `.git` de 44 MB.
- 🟠 **`.env.example` desatualizado.** Faltam `DB_NAME` (obrigatório, com `${DB_NAME:?}` no compose), `TELEGRAM_BOT_USERNAME` e `BACKEND_API_URL`. Um clone limpo seguindo o exemplo **falha ao subir**.
- 🟠 **Consome schema que não versiona:** `telegram.routes.ts` consulta `user_settings` e `telegram_link_tokens`, definidas pelos apps irmãos. Deploy em banco novo quebra silenciosamente.
- 🟡 `multer` 1.4.5-lts.2 — linha *deprecated* com CVEs de DoS, e é justamente ela que recebe upload de arquivo do usuário. `pdf-parse` 1.1.4 sem manutenção, processando PDF não confiável.
- 🟡 Locks conflitantes (`package-lock.json` + `pnpm-lock.yaml` + `pnpm-workspace.yaml`) e `npm install --legacy-peer-deps` no Dockerfile em vez de `npm ci` — build não reproduzível.

---

## 5. Padrões transversais

### 5.1 Gitlinks fantasma — a solution não é clonável

Os 4 apps estão registrados no repo-pai como **gitlinks (modo `160000`)**, mas **não existe `.gitmodules`**. Pior: o `.gitignore` da raiz contém `**/.git`, o que impede qualquer registro de submódulo funcionar.

Consequência: **quem clonar `LifeBusinessSuit` recebe 4 diretórios vazios.** O backup não é um backup.

E os 4 ponteiros estão defasados:

| App | Ponteiro no pai | HEAD real | |
|---|---|---|---|
| LBSTTSAPP | `31959a69` | `27234d6d` (25/08) | defasado |
| MoneyAPP | `a960fa83` | `88f1af42` (26/08) | defasado |
| NotesAPP | `c9522471` | `54818aea` (26/08) | defasado |
| TodoAPP | `ed896618` | `2d943a07` (26/08) | defasado |

**Decisão necessária:** ou virar submódulos de verdade (criar `.gitmodules`, remover `**/.git` do ignore), ou assumir monorepo e absorver os apps como diretórios normais. O estado atual é o pior dos dois mundos.

### 5.2 O que os 4 têm em comum

| Padrão | LBSTTS | Money | Notes | Todo |
|---|---|---|---|---|
| Testes automatizados | ❌ | ❌ | ❌ | ❌ |
| CI (`.github/workflows`) | ❌ | ❌ | ❌ | ❌ |
| ESLint configurado | ❌ | ❌ | ❌ | ❌ |
| Script `lint` **declarado mas quebrado** | — | ⚠️ | ⚠️ | ⚠️ |
| `typecheck` funcional | ✅ | ✅ | ✅ | ✅ |
| `.env.example` da raiz | ⚠️ incompleto | ❌ ausente | ❌ ausente | ❌ ausente |
| README manda `cp .env.example .env` | — | ✅ | ✅ | ✅ |
| Migrations fora do journal | — | 4 | 11 | 4 |
| `packages/db/package-lock.json` (resíduo npm) | — | ✅ | ✅ | ✅ |
| `.githooks/post-commit` órfão (aponta p/ `AI_context/` inexistente, `core.hooksPath` vazio) | — | ✅ | ✅ | ✅ |
| Bot com `vendor/` duplicando pacotes do workspace | — | ✅ | ✅ | ✅ |
| TODO/FIXME reais no código | 0 | 0 | 0 | 0 |

Três achados merecem destaque por serem sistêmicos:

1. **Três dos quatro READMEs instruem `cp .env.example .env` para um arquivo que não existe.** Onboarding quebrado em toda a suite.
2. **Todos os monorepos pnpm têm resíduo de npm** e bots que duplicam código em `vendor/` por causa do build context isolado. Divergência entre a cópia e o pacote é fonte silenciosa de bug.
3. **Nenhum app tem um único `TODO`/`FIXME` real.** Combinado com comentários densos em português que explicam *o porquê* das decisões, isso indica disciplina alta de escrita — o que torna a ausência total de testes ainda mais destoante.

### 5.3 Caminhos mortos pós-migração de servidor

Referências a diretórios e containers que não existem mais:

- `/mnt/docker-services/...` → hoje é `/mnt/nvme2tb/docker-services/...` — citado no README do **LBSTTSAPP** e no README + `settings.local.json` do **TodoAPP**
- `awlsrvDB_postgres` → hoje é `server_db_postgres` — no `docker-compose.yml` e no `apps/bot/README.md` do **MoneyAPP**
- README da solution documenta **MailAPP**, que não existe em disco; o quarto app é o **LBSTTSAPP**

> Conforme a regra global de sincronia, os caminhos `/mnt/docker-services` e `awlsrvDB_postgres` são candidatos à variável `MORTOS` do `awlskills-drift`.

### 5.4 Documentação da solution desatualizada

O `README.md` da raiz descreve a arquitetura com precisão (rede `awl_network`, Postgres compartilhado, padrão de notificações dos bots, fluxo do `redeploy.sh`), mas lista os módulos como *MailAPP, MoneyAPP, NotesAPP, TodoAPP*. O MailAPP não está na solution; o LBSTTSAPP, que está e roda, não é mencionado.

---

## 6. Riscos consolidados por severidade

### 🔴 Crítico
1. **2 tokens Cloudflare + senha do superusuário Postgres expostos em repo público** há ~2 meses (MoneyAPP; mesmos tokens em TodoAPP)
2. **A solution não é clonável** — gitlinks sem `.gitmodules`, agravados por `**/.git` no `.gitignore`
3. **NotesAPP: `pnpm db:migrate` destrói ambiente novo** — migrations são do MoneyAPP, nenhuma cria `notes`
4. **NotesAPP: stack trace vazando** em resposta 500 de produção

### 🟠 Alto
5. `.pnpm-store` versionado em MoneyAPP (19.848 arq.) e NotesAPP (22.000 arq.) — **343 MB de `.git` combinados**
6. Migrations fora do journal / com numeração colidida nos 3 monorepos — banco recriado do zero diverge de produção
7. `ALLOW_LEGACY_BOT_DELEGATION=true` por default no MoneyAPP
8. NotesAPP: lembretes configuráveis que nunca disparam (sem scheduler)
9. LBSTTSAPP: `.env.example` incompleto quebra deploy limpo; consome schema que não versiona

### 🟡 Médio
10. Zero testes / CI / lint nos 4 apps — a suite inteira depende de `tsc` e do dono
11. `multer` 1.x *deprecated* na rota de upload do LBSTTSAPP
12. `esbuild` 0.21.5 travado por override no NotesAPP (GHSA-67mh-4wv8-2f99)
13. TodoAPP com feature completa não commitada
14. Deps ~1 major atrás em toda a linha (Express 4, Pinia 2, Vite 5, Tailwind 3, drizzle 0.33)

### 🟢 Baixo / higiene
15. Código morto e resíduo de copy-paste (MoneyAPP→TodoAPP→NotesAPP)
16. `.githooks/post-commit` órfão nos 3 monorepos
17. Caminhos mortos pós-migração (§5.3)
18. `logo.png` de 2,9 MB no TodoAPP; `package.json` com nome/descrição errados em NotesAPP e TodoAPP
19. Identidades git duplicadas (`Moab` / `moablive`) no MoneyAPP

---

## 7. Plano de ação sugerido

**Hoje**
1. Revogar os 2 tokens Cloudflare e rotacionar a senha do Postgres `admin_root`
2. Remover `.claude/settings.local.json` do versionamento em MoneyAPP e TodoAPP; adicionar ao `.gitignore`
3. Corrigir o vazamento de stack trace no `app.ts` do NotesAPP
4. Corrigir o passo 3 do README do NotesAPP antes que alguém rode `pnpm db:migrate`

**Esta semana**
5. Reescrever o histórico de MoneyAPP e NotesAPP de uma vez só: remove os segredos **e** o `.pnpm-store` (~343 MB) na mesma operação
6. Decidir submódulos vs. monorepo e consertar os gitlinks
7. Commitar a feature pendente do TodoAPP
8. Desligar `ALLOW_LEGACY_BOT_DELEGATION`
9. Criar os `.env.example` que os READMEs prometem (3 apps) e completar o do LBSTTSAPP

**Backlog**
10. Resolver as cadeias de migrations nos 3 monorepos
11. Instalar o ESLint que os 3 `pnpm lint` prometem — ou remover o script
12. CI mínima rodando `typecheck` (o Dockerfile do MoneyAPP já exige; hoje o erro só aparece no `docker build`)
13. Primeiros testes onde o bug custa caro: regras de dinheiro do MoneyAPP (saldo denormalizado, `freezeBalance`, quitação de empréstimo, projeção de recorrências)
14. Implementar o scheduler de lembretes do NotesAPP
15. Atualizar o README da solution (MailAPP → LBSTTSAPP) e limpar os caminhos mortos

---

## Anexo — dados brutos

```
APP              ARQS PNPMSTORE       .git      DISCO
LBSTTSAPP          63        0        44M       461M
MoneyAPP        20089    19848       163M       571M
NotesAPP        22190    22000       180M       594M
TodoAPP           193        0        13M       261M
```

**Containers LBS** (todos `running`):
`lbs_{money,notes,todo,tts}app_{backend,frontend,bot}` — 12/12

**Camada de deploy** (`deploy/`): `redeploy.sh` descobre apps por `*/docker-compose.yml`, garante a rede `awl_network`, roda `docker compose up -d --build` com `--env-file ../shared.env --env-file .env`. Painel web em `redeploy-ui.mjs` (porta 7878, Tailscale), com allowlist de flags e `spawn` sem shell. `deploy/notify.env` (Telegram) e `shared.env` (12 chaves, incl. `JWT_SECRET`, `DB_DSN`, `GROQ_API_KEY`) corretamente fora do git.

---

*Auditoria somente leitura — nenhum arquivo dos apps foi modificado. Este documento é a única escrita.*
