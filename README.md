# 🏗️ LifeBusinessSuit (LBS)

Guia completo da arquitetura do sistema LifeBusinessSuit (MailAPP, MoneyAPP, NotesAPP, TodoAPP), da plataforma central de notificações (LBS Notify) e instruções de deploy.

---

## 🏗️ Arquitetura de Sistemas

Este documento descreve detalhadamente a arquitetura global, as tecnologias utilizadas e as integrações do ecossistema **LifeBusinessSuit**, que engloba as aplicações: `MailAPP`, `MoneyAPP`, `NotesAPP` e `TodoAPP`.

### 🌐 1. Visão Geral da Arquitetura (Top-Level)

O ecossistema é baseado em arquitetura de **Microsserviços Containerizados** utilizando Docker e orquestrado através de scripts automatizados (`redeploy.sh`).
Todos os serviços comunicam-se de forma segura através da rede externa compartilhada do Docker chamada `awl_network`. 

#### Padrão Tecnológico Global
A stack de tecnologias é padronizada na maior parte dos projetos para otimizar o desenvolvimento e manutenção:

*   **Frontend**: Vue.js 3 (Composition API), Vite, Tailwind CSS, Pinia (Gerenciamento de Estado), Vue Router. PWA (Progressive Web App) configurado para uso offline e mobile.
*   **Backend**: Node.js, Express, TypeScript, Zod (Validação de schemas), Pino (Logging).
*   **ORM e Banco de Dados**: Drizzle ORM conectado ao PostgreSQL.
*   **Infraestrutura e Deploy**: Docker, Docker Compose, Cloudflare Tunnels (exposição segura na web).

### 💾 2. Persistência de Dados e Cache

#### 🐘 Banco de Dados (PostgreSQL)
A persistência primária e relacional de todas as aplicações é centralizada em uma única instância robusta do PostgreSQL.
*   **Container**: `awlsrvDB_postgres`
*   **Rede**: `awl_network`
*   **Isolamento lógico**: Apesar de compartilharem o mesmo SGBD para otimização de recursos da máquina host, cada aplicação (MoneyAPP, TodoAPP, etc.) geralmente possui seu próprio database (ou schema) lógico isolado. Não definimos containers de banco individuais dentro do `docker-compose.yml` de cada projeto para evitar overhead no host.

#### ⚡ Cache Local
O sistema faz uso de estratégias de Cache Local (In-memory caching) para evitar sobrecarga no banco de dados, especialmente para:
*   Sessões e Autenticação (verificação rápida de tokens/JWT em conjunto com o `LoginHub`).
*   Configurações recorrentes do usuário lidas pelo backend.
*   Rate limiting e mitigação de spam.
*   *Implementação*: O Cache é mantido ao nível de aplicação no Backend Node.js (via Map em memória ou bibliotecas como `node-cache` / `lru-cache`), garantindo respostas em microssegundos para requisições repetitivas, sem necessidade de um broker adicional como Redis (mantendo a infraestrutura enxuta).

### 🤖 3. Sistema de Notificações e Interação (Bots do Telegram)

Um diferencial chave do ecossistema LBS é a integração ubíqua com o Telegram. Cada módulo principal possui seu próprio **Bot dedicado**.

*   **Como funciona**: Containers independentes (ex: `app_moneyapp_bot`, `app_todoapp_bot`, `app_mailapp_bot`) rodam em paralelo aos backends e frontends.
*   **Comunicação**: O Bot se comunica com a API REST interna do backend do seu respectivo app na rede `awl_network` (ex: `http://moneyapp_backend:3000/api`).
*   **Funcionalidades**:
    *   **Notificações Push / Alertas**: Envio instantâneo de faturas a vencer, tarefas agendadas, novos e-mails importantes.
    *   **Comandos Interativos**: Permite ao usuário cadastrar despesas (MoneyAPP), adicionar tarefas (TodoAPP) ou responder e-mails (MailAPP) diretamente pelo chat do Telegram, sem precisar abrir o Frontend Web.
    *   **Integração IA**: O bot também faz parse da intenção do usuário utilizando inteligência artificial local (Ollama) ou APIs externas (Groq) para criar comandos por texto natural (ex: "gastei 50 no mercado hoje").

### 📦 4. Detalhamento dos Módulos e Padronização de Notificações (Skill de Bot)

Para garantir consistência na experiência do usuário e facilitar a manutenção, todos os Bots do ecossistema seguem uma **Padronização de Notificações (Cron & Push)**. O padrão estabelece que o agendamento (Cron) fica a cargo do Bot (ou acionado via webhook do Backend) e a interface é estritamente via Telegraf (Telegram API), possuindo botões Inline (`Markup.inlineKeyboard`) padronizados para silenciar (`TOGGLE_NOTIFY`) ou executar ações rápidas sem sair do chat.

#### 📧 MailAPP
Um cliente e gerenciador de e-mails avançado com recursos de IA.
*   **Tecnologias Específicas**: 
    *   **Proton Bridge Headless**: Container isolado para descriptografar caixas (ProtonMail) e expor conexões IMAP/SMTP em texto plano na `awl_network`.
    *   **Edge-TTS (Serviço em Python)**: Container `app_mailapp_tts` para geração de áudio (Text-to-Speech).
    *   **Ollama (IA Local)**: Conecta-se ao `server_ollama:11434` para tradução e resumo.
*   **Padrão de Notificação do Bot**:
    *   **Gatilhos**: Novo e-mail recebido (via IMAP IDLE ou polling agendado).
    *   **Ação de Push**: Notifica imediatamente o usuário sobre remetentes prioritários ou regras pré-definidas.
    *   **Formato Padrão UX**: Mensagem estruturada contendo [Remetente], [Assunto], [Resumo gerado por IA] e botões Inline para: "🔊 Ouvir Áudio (TTS)", "🗑️ Arquivar" ou "🔕 Silenciar Tópico".

#### 💰 MoneyAPP
Gerenciador financeiro pessoal e empresarial.
*   **Arquitetura**: Backend/Frontend separados (Node+Vue) ligados ao `awlsrvDB_postgres`.
*   **Padrão de Notificação do Bot**:
    *   **Gatilhos**: Rotina diária/semanal (via `startNotificationsCron`) mapeando contas a pagar/receber no dia e faturas de cartão prestes a fechar/vencer.
    *   **Ação de Push**: Alerta proativo matinal de "Resumo Financeiro" e alertas avulsos de vencimento.
    *   **Formato Padrão UX**: Ícones padronizados (🚨 para urgências, 💰 para saldo). Botões Inline que possibilitam dar baixa na despesa ("✅ Marcar como Pago"), "⏰ Adiar", ou o padrão (`TOGGLE_NOTIFY`) para silenciar. Inclui parseamento de áudio via IA para registrar gastos rápidos.

#### 📝 TodoAPP
Gerenciador de tarefas e rotinas.
*   **Arquitetura**: Segue padrão LBS, focado em checklists, hábitos e lembretes de calendário.
*   **Padrão de Notificação do Bot**:
    *   **Gatilhos**: Verificações temporais contínuas de tarefas com `due_date` (prazo) se aproximando (ex: alerta de 2 horas antes) ou rotinas diárias/hábitos.
    *   **Ação de Push**: Atua como um assistente incisivo para evitar a procrastinação, cobrando progresso.
    *   **Formato Padrão UX**: Mensagem com o nome da tarefa e nível de urgência. Ações Inline exigidas: "✅ Concluir", "⏳ Adianta 1 Hora", "🗓️ Adiar para Amanhã".

#### 📓 NotesAPP
Módulo focado em gestão do conhecimento e anotações rápidas.
*   **Arquitetura**: Módulo complementar de anotações e knowledge base (Zettelkasten).
*   **Padrão de Notificação do Bot**:
    *   **Gatilhos**: Lembretes espaçados (Spaced Repetition) ou anotações pontuais marcadas com `remind_at`.
    *   **Ação de Push**: Disparo diário da curadoria de "Notas para rever hoje" ou lembrete pontual.
    *   **Formato Padrão UX**: Bloco de citação (quote) com a prévia da nota e botões Inline: "📖 Abrir no App", "🔄 Rever em 7 dias", "🗑️ Arquivar".

#### 🔔 LBS Notify

Plataforma **central** de notificações da suite — não é um app com tela, é a infraestrutura de push que os outros quatro passam a usar.

*   **Containers**: `lbs_notify_api` (API) e `lbs_notify_worker` (fila) — a mesma imagem, com CMD diferente.
*   **Banco**: `lbsnotify` no `server_db_postgres`, com quatro tabelas (`notification_devices`, `notification_preferences`, `notifications`, `notification_deliveries`).
*   **Por que existe**: antes, TodoAPP, MoneyAPP e NotesAPP carregavam cada um a própria tabela `push_subscriptions`, o próprio par VAPID e o envio síncrono dentro do cron do bot — sem fila, sem idempotência, e apagando a inscrição revogada junto com a única pista de por que ela morreu.
*   **Fila sem Redis**: Outbox na própria tabela, com `FOR UPDATE SKIP LOCKED`. Idempotência por `event_id`, retry com backoff, opt-out e silêncio noturno por usuário.
*   **O Telegram não muda**: os bots continuam mandando mensagem como sempre. O Notify trata push — Web Push hoje, FCM quando existir app Android.
*   **Rollout gradual**: as flags `<APP>_NOTIFY_USE_CENTRAL` e `VITE_LBS_NOTIFY_URL` nascem desligadas. Com elas assim, nada muda no comportamento atual.

📖 Detalhes em [`LBSNotify/README.md`](LBSNotify/README.md) e [`LBSNotify/docs/ARCHITECTURE_DISCOVERY.md`](LBSNotify/docs/ARCHITECTURE_DISCOVERY.md).

---

## 🚀 5. Deploy

Tudo relacionado ao redeploy dos apps do LifeBusinessSuit fica na pasta `deploy/`. O sistema foi projetado para ser atualizado de forma simples e com "zero-downtime".

| Arquivo | O que é |
|---|---|
| `redeploy.sh` | Script que republica os projetos Docker (`docker compose up -d --build`). Descobre automaticamente os apps na pasta-mãe (`../*/docker-compose.yml`). |
| `redeploy-ui.mjs` | Servidor web local (Node, sem dependências) que serve o painel e faz streaming ao vivo da saída do `redeploy.sh`. |
| `redeploy-ui.html` | A interface do painel. |
| `start-ui.sh` | Gerencia o painel (`start`/`stop`/`restart`/`status`) em background, escutando no IP da VPN Tailscale. |

### Fluxo de Deploy e Integração (redeploy.sh)
1.  **Descoberta Automática**: Lê todas as pastas raiz que contém um `docker-compose.yml` (LBSTTSAPP, MoneyAPP, NotesAPP, TodoAPP).
2.  **Garantia de Rede**: Verifica e cria (se não existir) a rede `awl_network`.
3.  **Deploy Direcionado**: O usuário pode executar de forma interativa ou via script (ex: `deploy/redeploy.sh MoneyAPP`) para fazer pull das imagens mais recentes, build se necessário e recriar apenas os containers do projeto específico, sem afetar o restante do ecossistema.

### Linha de comando (sem painel)

Rode a partir da raiz do repositório (o script descobre os apps na pasta-mãe):

```bash
deploy/redeploy.sh              # menu interativo (ou TODOS)
deploy/redeploy.sh NotesAPP     # só um app
deploy/redeploy.sh --no-build NotesAPP
deploy/redeploy.sh --list
```

### Painel web

```bash
deploy/start-ui.sh            # menu interativo (start/stop/restart/status)
deploy/start-ui.sh start      # sobe em background
deploy/start-ui.sh status     # estado (PID, URL, últimas linhas do log)
deploy/start-ui.sh restart    # reinicia
deploy/start-ui.sh stop       # derruba
```

Sem argumento abre um **menu interativo**; em automação/sem terminal (cron, boot) sobe direto. O painel roda em background — PID em `deploy/.redeploy-ui.pid`, saída em `deploy/redeploy-ui.log`. Se uma instância órfã já estiver ocupando a porta (ex.: uma execução antiga), o script a detecta e adota/para em vez de estourar `EADDRINUSE`.

Depois abra **http://100.102.39.17:7878** em qualquer dispositivo da sua VPN Tailscale. O painel deixa você selecionar apps, ligar flags (`--no-build`, `--down`, `--pull`, `--prune`), ver o comando exato, rodar e acompanhar o log ao vivo, além do status dos containers.

Portas/hosts alternativos (valem para `start`/`restart`):

```bash
PORT=9000 deploy/start-ui.sh start        # outra porta
HOST=127.0.0.1 deploy/start-ui.sh start   # só localhost
```

O servidor só executa o `redeploy.sh` com argumentos validados (flags de uma allowlist + nomes de apps existentes) e roda via `spawn` sem shell — sem risco de injeção de comando.

---

## 🏷️ 6. Versionamento e aviso de nova versão

**Os quatro apps têm o mesmo mecanismo, implantado em 27/08/2026.** Ele resolve
um problema que só aparece com PWA instalado na tela inicial: o aparelho fica
semanas sem recarregar de verdade, então o redeploy sobe a versão nova e o
usuário continua rodando o bundle antigo — chamando rota que mudou e com bug já
corrigido, sem sinal nenhum de que está desatualizado.

| App | Versão nasce em | Aparece em |
|---|---|---|
| LBSNotify | `LBSNotify/VERSION` | `GET /health` (não tem frontend, então não há badge) |
| LBSTTSAPP | `LBSTTSAPP/VERSION` | badge no canto · `GET /health` · banner |
| MoneyAPP | `MoneyAPP/VERSION` | idem |
| NotesAPP | `NotesAPP/VERSION` | idem |
| TodoAPP | `TodoAPP/VERSION` | idem |

**Cada app tem o próprio `VERSION`** — a suite não versiona em bloco. A
comparação que acende o aviso é sempre dentro do mesmo app: o bundle contra o
`/health` dele. Um app em `0.0.7` e outro em `0.0.2` é estado normal.

### O fluxo, igual nos quatro

```
VERSION (0.0.1)                       ← fonte da verdade, versionada no git
   │  node scripts/bump-version.mjs
   ▼
0.0.2 + APP_BUILD_DATE
   │
   └─▶ .env  (APP_VERSION, APP_BUILD_DATE)   ← o --env-file do redeploy.sh
              │
              ├─▶ backend  APP_VERSION       → GET /health
              └─▶ frontend VITE_APP_VERSION  → build-arg, congelado no bundle
                             │
                             ▼
                   useVersionCheck compara os dois, a cada 5 min e ao
                   voltar o foco para o app
                             │  divergiu?
                             ▼
                   UpdateBanner: "Nova versão disponível"  [Depois] [Atualizar agora]
```

### Publicar uma versão nova

```bash
cd MoneyAPP && node scripts/bump-version.mjs   # 0.0.1 -> 0.0.2
cd .. && deploy/redeploy.sh MoneyAPP           # o --build é o padrão
```

O `--build` **não é opcional aqui**: a versão do front é build-arg, congelada
pelo `vite build` dentro da imagem. Um `redeploy.sh --no-build` republica o
container com o bundle anterior, e o app passa a anunciar uma versão que não é
a dele. O backend, esse, lê `APP_VERSION` em runtime e acompanha na hora.

### Três decisões que valem para toda a suite

- **O aviso sugere, não executa.** Recarregar sozinho jogaria fora formulário
  meio preenchido. Quem decide é o usuário, no banner.
- **O `nginx.conf` de cada front encaminha `/health` ao backend.** Sem essa
  `location` o caminho cai no *SPA fallback* e devolve o `index.html` — JSON
  esperado, HTML recebido, e o banner nunca aparece, sem erro no console.
- **Sem `APP_VERSION` no ambiente, a checagem se desliga.** Em dev não há
  baseline, e comparar contra a versão real do backend só geraria falso
  positivo.

O detalhamento de cada app está no README dele, na seção *Versionamento e aviso
de nova versão*.

---

---

## 🔥 7. Hot reload (modo dev)

Os quatro apps têm um `docker-compose.dev.yml` que devolve o hot reload sem
tocar no caminho de produção. **Ele é sobreposição:** `docker compose up -d`
sozinho e o `redeploy.sh` continuam subindo produção — build multi-stage, front
por nginx, sem volume de código. Só entra em modo dev quem passa `-f` nos dois
arquivos.

```bash
cd MoneyAPP && pnpm docker:dev        # atalho nos três apps pnpm
# LBSTTSAPP (sem package.json na raiz):
cd LBSTTSAPP && docker compose --env-file ../shared.env --env-file .env \
  -f docker-compose.yml -f docker-compose.dev.yml up
```

Editou no host, o container reage: `tsx watch` reinicia o backend em ~1 s e o
Vite troca o módulo no navegador.

| App | Frontend (Vite) | Backend (direto) |
|---|---|---|
| LBSTTSAPP | `:5181` | `:5081` |
| MoneyAPP | `:5182` | `:5082` |
| NotesAPP | `:5183` | `:5083` |
| TodoAPP | `:5184` | `:5084` |

Portas distintas de propósito: dá para subir mais de um app em dev ao mesmo
tempo sem colisão. Em modo dev o acesso é por essas portas, **não** pelo domínio
público — o túnel da Cloudflare aponta para o nginx, que não sobe em dev.

### As armadilhas, todas comentadas nos arquivos

- **Volumes anônimos de `node_modules` são obrigatórios.** O bind mount da raiz
  cobriria o `node_modules` do container pelo do host, resolvido para outra
  plataforma. Workspace novo em `apps/` ou `packages/` = linha nova na âncora.
- **Imagem de dev com nome próprio** (sufixo `-dev`). Sem isso o compose
  reaproveita a imagem de produção com o mesmo nome, ignora o `target:` e o
  container sobe com o nginx, morrendo em `pnpm: not found`.
- **Em dev o nginx sai, e o proxy `/api` vai junto.** Quem encaminha passa a ser
  o Vite, via `DEV_API_TARGET`.
- **Rebuild continua necessário** para mudança em `package.json`, `Dockerfile`,
  `.env` ou compose — e com `down -v`, porque o volume anônimo sobrevive ao
  `--build` com o `node_modules` antigo.
- **O bot do LBSTTSAPP fica de fora**: é Python, sem watcher. O código está
  montado, mas quem aplica é `docker restart lbs_ttsapp_bot`.
