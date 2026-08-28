# Rollout do LBS Notify — plano de execução

Levantamento feito em **28/08/2026**. Este documento existe porque o Notify está
construído, republicado e **entregando zero notificação**: as quatro flags estão
em `false` e `VITE_LBS_NOTIFY_URL` está vazio nos quatro frontends.

A conclusão do levantamento é a que importa para dimensionar o trabalho:

> **Não falta código. Falta configuração.**

## O que já está pronto (verificado, não presumido)

| Item | Estado | Como foi conferido |
|---|---|---|
| `lbs_notifyapp_api` + `lbs_notifyapp_worker` | no ar, API `healthy` | `docker ps` |
| Chaves por app (`LBS_NOTIFY_KEY_TODO/MONEY/NOTES/TTS`) | **as quatro geradas** no `.env` do Notify | `grep` das chaves |
| Chave distribuída para cada app | **as quatro presentes**, 64 chars | `.env` de cada app |
| Cliente do frontend | `apps/frontend/src/lib/lbsNotifyClient.ts` nos 4 | `grep -rl` |
| Cliente ligado na UI | `composables/usePush.ts` consome nos 4 | `grep -rl` |
| Backend/bot lê a flag | Money e Todo no bot, Notes e TTS no backend | `grep -rl NOTIFY_USE_CENTRAL` |
| `VITE_LBS_NOTIFY_URL` chega ao build | `ARG`+`ENV` no Dockerfile e `build.args` no compose, nos 4 | `grep` do Dockerfile e do compose |

Ou seja: os passos 1 e 2 de *"Integrando um app"* do README **já foram feitos para
os quatro apps**. O que resta é o passo 3 (preencher a URL) e o 4 (virar a flag),
e ambos dependem de uma coisa que não existe ainda: **a borda pública**.

## O que falta

1. **Hostname público no túnel Cloudflare.** Sem ele o aparelho não tem como
   registrar a inscrição — `VITE_LBS_NOTIFY_URL` não tem valor para receber.
2. **Preencher `VITE_LBS_NOTIFY_URL`** no `.env` de cada app, um por vez.
3. **Virar `<APP>_NOTIFY_USE_CENTRAL=true`**, um por vez, depois do anterior.

---

## Fase 0 — destravar a verificação ✅ CONCLUÍDA em 28/08/2026

Feita no commit `c490b8a` do `LBS_NotifyAPP` (branch `main`). Registrada aqui
porque explica **por que existe uma linha de base** para as fases seguintes.

O `LBS_NotifyAPP/scripts/smoke-test.sh` estava quebrado desde a padronização
`LBS_*` de 27/08. A linha 24 fixava `API=lbs_notify_api`, que é o **nome do
serviço** no compose; o `docker exec` precisa do **`container_name`**, que virou
`lbs_notifyapp_api`. O script morria em `✗ container lbs_notify_api nao esta
rodando` sem executar nenhuma verificação — o serviço estava correto o tempo
todo e não havia como saber.

Corrigidos junto os dois nomes de container desatualizados no
`LBS_NotifyAPP/README.md` (linhas 56 e 220). A linha do `curl` **não** mudou, de
propósito: ali `lbs_notify_api` é *alias de rede*, que segue válido de dentro da
`awl_network`. O que mudou foi só o nome do container.

**Resultado da linha de base** — todas as verificações passam:

```
✔ GET /health responde 200        ✔ 1a emissao -> 202, duplicated=false
✔ sem credencial -> 401           ✔ reemissao  -> 200, duplicated=true
✔ chave errada -> 403             ✔ chave VAPID publica -> 200
✔ app desconhecido -> 403         ✔ devices sem token -> 401
✔ payload invalido -> 400         ✔ notificacao processada -> cancelled (sem aparelho)
✔ source falsificado -> 403       ✔ entrega registrada -> skipped
```

As duas últimas linhas são o diagnóstico deste plano em uma frase: a cadeia
funciona ponta a ponta e **cancela por não haver aparelho inscrito**. É isso que
as Fases 1 e 2 resolvem.

Para reconferir a qualquer momento:

```bash
bash LBS_NotifyAPP/scripts/smoke-test.sh
```

---

## Fase 1 — publicar a borda

**Onde:** dashboard Cloudflare Zero Trust (**é sua, não dá para fazer daqui**).

O `network_cloudflared_tunnel` sobe com `TUNNEL_TOKEN` e `tunnel run` — o ingress
é gerenciado remotamente, não há arquivo de config local para editar.

Hostname sugerido, seguindo o padrão dos outros apps
(`todo.` / `money.` / `loginhub.astralwavelabel.com`):

| Campo | Valor |
|---|---|
| Subdomain | `notify` |
| Domain | `astralwavelabel.com` |
| Service | `http://notify_api:3000` |

O `Service` usa o alias de rede, não o nome do container: o cloudflared está na
`awl_network` e o `lbs_notifyapp_api` responde por `notify_api` e
`lbs_notify_api` lá dentro.

### ⚠ O cuidado que não pode ser pulado nesta fase

`/internal/v1` e `/v1` são montados **no mesmo Express, na mesma porta 3000**
(`LBS_NotifyAPP/src/api/app.ts:38-40`). Publicar a raiz de `notify_api:3000` expõe à internet
a API interna de emissão de eventos — aquela que faz um app emitir notificação
como se fosse outro. Ela não fica aberta: o `service-auth.ts` exige
`x-lbs-app` + `x-lbs-key` e compara em tempo constante com `timingSafeEqual`.
Mas é uma chave estática de 64 hex virando superfície de internet **sem
necessidade nenhuma** — nenhum cliente externo precisa do `/internal/v1`.

Faça uma das duas, na criação do hostname:

- **Path na regra de ingress**: publique só `/v1/*`. É o mais limpo. Repare que
  isso deixa `/health` inacessível de fora — o healthcheck do compose é interno,
  então não quebra nada.
- **Regra de WAF** bloqueando `/internal/*` no hostname `notify.`.

Critério de saída: de **fora** da rede, `GET https://notify.astralwavelabel.com/v1/push/public-key`
devolve a chave VAPID pública, e `GET .../internal/v1/events` devolve bloqueio do
Cloudflare (não um `401` do Express — se vier `401`, a regra não pegou).

---

## Por que o TTS vai primeiro

Os quatro apps não são equivalentes como cobaia. O **TTS não tem caminho legado
de push nenhum** — o `LBS_TTSAPP/apps/frontend/src/composables/usePush.ts:13` registra em
comentário: *"não há tabela `push_subscriptions`, nem rota `/api/push/*`, nem par
VAPID"*, e não existe dependência `web-push` no `package.json` do TTS.

| App | Caminho legado | Consequência de ir primeiro |
|---|---|---|
| **TTS** | **nenhum** | sem duplicata, sem regressão possível |
| Todo / Notes | tabela + 1 rota cada | duplicata durante o corte |
| Money | tabela + 2 rotas | duplicata durante o corte |

Nos outros três, ligar o Notify cria uma janela em que o aparelho recebe a mesma
notificação duas vezes. No TTS não existe janela: hoje ele não manda push
nenhum, então tudo que aparecer veio do Notify e nada pode piorar. É o teste
mais limpo possível da cadeia inteira — borda, registro, fila, worker, entrega —
sem nenhuma variável legada no meio.

O preço é que o TTS também não tem para onde voltar: o rollback dele é "volta a
não receber push", que é exatamente o estado de hoje. Nenhuma perda.

---

## Fase 2 — primeiro aparelho registrado (só TTS)

**Antes de começar, responda:** o celular é Android ou iPhone?

- **Android/Chrome** — Web Push funciona direto no navegador.
- **iPhone** — o Safari **só entrega push para PWA instalado na tela de início**.
  Aberto como aba comum, o `PushManager` nem existe e o botão de ativar não
  aparece. Instale o TTS na tela de início **antes** de julgar que o rollout
  falhou. Não há nada no código tratando esse caso, e o servidor não tem como
  perceber: um aparelho que nunca se inscreveu é indistinguível de um que não
  existe.

Passos:

```bash
# 1. preencher no .env do LBS_TTSAPP (e SÓ nele)
VITE_LBS_NOTIFY_URL='https://notify.astralwavelabel.com'

# 2. republicar COM build — VITE_* é baked no bundle, restart não basta
PROJECTS_ROOT=/mnt/nvme2tb/docker-services \
  /mnt/nvme2tb/docker-services/server/dashboard/scripts/redeploy.sh \
  LifeBusinessSuit/LBS_TTSAPP
```

Depois: abra o TTS no celular, ative a notificação, e confirme o registro.

```sql
-- o aparelho chegou?
SELECT id, app_scope, channel, is_active, last_seen_at
  FROM notification_devices WHERE app_scope = 'tts';
```

Se `notification_devices` ficar vazio, o problema é Fase 1 ou o PWA do iPhone —
não adianta seguir para a Fase 3.

---

## Fase 3 — virar a flag do TTS

```bash
# .env do LBS_TTSAPP
TTS_NOTIFY_USE_CENTRAL='true'
```

Republique o TTS de novo. A partir daqui o push sai pelo Notify — e no caso do
TTS, é a **primeira vez** que sai push.

```bash
docker logs -f lbs_notifyapp_worker
```

```sql
SELECT status, count(*) FROM notifications GROUP BY status;   -- fila andando?
```

**Aqui não há duplicata** — é a vantagem de ter começado pelo TTS. Se chegar
notificação repetida nesta fase, é bug de verdade, não o efeito esperado do
corte gradual.

Deixe rodando **alguns dias** antes da Fase 4. O ponto do rollout gradual é ter
um app de cada vez sob observação; virar os quatro no mesmo dia joga fora a
única vantagem do desenho.

---

## Fase 4 — replicar nos três com caminho legado

Mesma sequência das Fases 2 e 3, um app por vez, esperando entre eles:

| Ordem | App | Flag | Onde a flag é lida |
|---|---|---|---|
| 2º | `LBS_TodoAPP` | `TODO_NOTIFY_USE_CENTRAL` | `apps/bot/src/utils/push.ts` |
| 3º | `LBS_MoneyAPP` | `MONEY_NOTIFY_USE_CENTRAL` | `apps/bot/src/cron/notifications.ts` |
| 4º | `LBS_NotesAPP` | `NOTES_NOTIFY_USE_CENTRAL` | `apps/backend/src/notify/reminders.ts` |

**A partir daqui a duplicata volta a ser esperada.** Estes três têm
`push_subscriptions` e `/api/push/*` vivos: entre a Fase 2 e a Fase 3 de cada
um, o mesmo aparelho pode estar inscrito nos dois lados e receber duas vezes.
Some na Fase 5. Está documentado em
[`ARCHITECTURE_DISCOVERY.md` §2.3](LBS_NotifyAPP/docs/ARCHITECTURE_DISCOVERY.md).

**Rollback** nestes três: volte a flag para `'false'` e republique. O caminho
legado nunca foi removido — `push_subscriptions`, as rotas `/api/push/*` e o
`sendPushToUser` continuam intactos. É por isso que o corte é reversível.

Cada aparelho precisa **reativar a notificação em cada app**. Não é evitável e
não é esquecimento: uma `PushSubscription` nasce amarrada à chave VAPID que a
criou, e o Notify assina com outro par. As inscrições antigas dos apps **não
podem** ser importadas.

---

## Fase 5 — aposentar o legado

**Não se aplica ao TTS** — ele nunca teve legado para aposentar. Vale para Todo,
Money e Notes.

Só quando o `push_subscriptions` de um app parar de receber entrega por semanas.
Aí sim: derrubar a tabela, as rotas `/api/push/*` e o `sendPushToUser` daquele
app. É o passo que elimina a duplicata.

Não tem pressa e não tem volta — faça um app por vez, e só depois que o Notify
tiver histórico de entrega bem-sucedida para aquele `app_scope`.

---

## Fora de escopo: FCM / Android nativo

O canal FCM está **escrito e desligado** (`LBS_NOTIFY_FCM_ENABLED=false`). O
schema já carrega `fcm_token` ao lado das colunas de Web Push. O que falta não é
código do Notify — é **um app Android que não existe**, mais a conta de serviço
do Firebase (`FCM_SERVICE_ACCOUNT_FILE`, `FCM_PROJECT_ID`).

Enquanto o app nativo não existir, isto não é uma fase deste plano. Ver
[`ANDROID_FCM_INTEGRATION.md`](LBS_NotifyAPP/docs/ANDROID_FCM_INTEGRATION.md).

---

## Resumo dos pontos de parada

Não avance de fase sem o critério da anterior:

| Fase | Não siga se… |
|---|---|
| 0 | ✅ concluída em 28/08/2026 — linha de base verde |
| 1 | `/internal/v1` responder de fora com `401` do Express em vez de bloqueio do Cloudflare |
| 2 | `notification_devices` continuar vazio para `app_scope = 'tts'` |
| 3 | a fila em `notifications` acumular `status` de falha |
| 4 | o app anterior não tiver alguns dias de entrega estável |
