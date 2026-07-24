#!/usr/bin/env bash
# =============================================================================
# start-ui.sh — Gerencia o painel web do redeploy (start/stop/restart/status).
#
# O painel escuta no IP da VPN Tailscale (auto-detectado) — acessível de
# qualquer dispositivo do seu tailnet, SEM exposição à internet pública.
# Roda em background (PID em .redeploy-ui.pid, saída em redeploy-ui.log).
#
#   ./start-ui.sh                  # SEM argumento: menu interativo
#   ./start-ui.sh start            # sobe em background (IP Tailscale, porta 7878)
#   ./start-ui.sh stop             # derruba o painel
#   ./start-ui.sh restart          # reinicia
#   ./start-ui.sh status           # estado atual (PID, URL, últimas linhas do log)
#
# Overrides de bind (valem para start/restart):
#   PORT=9000 ./start-ui.sh start        # outra porta
#   HOST=127.0.0.1 ./start-ui.sh start   # só localhost
#   HOST=0.0.0.0 ./start-ui.sh start     # TODAS as interfaces (cuidado: LAN)
# =============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MJS="$DIR/redeploy-ui.mjs"
PIDFILE="$DIR/.redeploy-ui.pid"
LOG="$DIR/redeploy-ui.log"
PORT="${PORT:-7878}"

# IP Tailscale: usa o do CLI se disponível, senão o fixo conhecido. Respeita HOST.
resolve_host() {
  local h="${HOST:-$(tailscale ip -4 2>/dev/null | head -1 || true)}"
  printf '%s' "${h:-100.102.39.17}"
}

current_pid() { cat "$PIDFILE" 2>/dev/null || true; }
alive()       { local p="${1:-}"; [[ -n "$p" ]] && kill -0 "$p" 2>/dev/null; }
is_running()  { alive "$(current_pid)"; }

# PID que está ESCUTANDO na porta $PORT (independente do PID file). Cobre o caso
# de uma instância órfã (ex.: uma execução antiga em foreground) que o PID file
# não conhece — foi o que causou o EADDRINUSE.
pid_on_port() {
  if command -v ss >/dev/null 2>&1; then
    ss -H -ltnp "sport = :$PORT" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1
  elif command -v lsof >/dev/null 2>&1; then
    lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null | head -1
  elif command -v fuser >/dev/null 2>&1; then
    fuser "$PORT/tcp" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | head -1
  fi
}
cmd_of()    { ps -p "${1:-0}" -o args= 2>/dev/null | head -c 80; }
is_our_ui() { [[ -n "${1:-}" ]] && tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null | grep -q "redeploy-ui.mjs"; }

show_url() {                 # $1 = host (opcional)
  local host="${1:-$(resolve_host)}" shown
  shown="$host"; [[ "$host" == "0.0.0.0" ]] && shown="<este-host>"
  echo "  URL: http://$shown:$PORT   (acessível pelos dispositivos da sua VPN Tailscale)"
}

start() {
  if is_running; then
    echo "▶ Painel já está rodando (PID $(current_pid)). Use 'restart' para reiniciar."
    show_url; return 0
  fi

  # PID file não sabe de nada, mas a porta pode estar ocupada por um órfão.
  local pport; pport="$(pid_on_port || true)"
  if [[ -n "$pport" ]]; then
    if is_our_ui "$pport"; then
      echo "$pport" > "$PIDFILE"
      echo "▶ Painel já estava rodando fora de controle na porta $PORT — adotei o PID $pport."
      show_url; return 0
    fi
    echo "✗ Porta $PORT já está em uso pelo PID $pport:" >&2
    echo "    $(cmd_of "$pport")" >&2
    echo "  Pare esse processo ou use outra porta:  PORT=9000 $0 start" >&2
    exit 1
  fi

  command -v node >/dev/null 2>&1 || { echo "✗ node não encontrado no PATH." >&2; exit 1; }
  [[ -f "$MJS" ]] || { echo "✗ $MJS não encontrado." >&2; exit 1; }

  local host; host="$(resolve_host)"
  HOST="$host" PORT="$PORT" nohup node "$MJS" >"$LOG" 2>&1 < /dev/null &
  local pid=$!
  echo "$pid" > "$PIDFILE"

  sleep 1                    # dá um instante e confirma que subiu
  if ! is_running; then
    echo "✗ Falhou ao subir. Últimas linhas do log:" >&2
    tail -n 12 "$LOG" >&2 2>/dev/null || true
    rm -f "$PIDFILE"; exit 1
  fi
  echo "✔ Painel de redeploy iniciado (PID $pid)."
  show_url "$host"
  echo "  Log: $LOG"
}

stop() {
  local pid; pid="$(current_pid)"
  if ! alive "$pid"; then
    # Fallback: pode estar rodando órfão na porta (fora do PID file).
    local pport; pport="$(pid_on_port || true)"
    if [[ -n "$pport" ]] && is_our_ui "$pport"; then
      pid="$pport"
      echo "▶ Painel órfão encontrado na porta $PORT (PID $pid)."
    else
      echo "▶ Painel não está rodando."; rm -f "$PIDFILE"; return 0
    fi
  fi
  kill -TERM "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5; do alive "$pid" || break; sleep 1; done
  if alive "$pid"; then
    echo "⚠ Não encerrou com SIGTERM — forçando SIGKILL."
    kill -KILL "$pid" 2>/dev/null || true
  fi
  rm -f "$PIDFILE"
  echo "✔ Painel parado (PID $pid)."
}

status() {
  local pid; pid="$(current_pid)"
  if ! alive "$pid"; then
    local pport; pport="$(pid_on_port || true)"
    [[ -n "$pport" ]] && is_our_ui "$pport" && pid="$pport"
  fi
  if alive "$pid"; then
    echo "✔ Painel RODANDO (PID $pid)."
    show_url
    echo "  Log: $LOG"
    if [[ -f "$LOG" ]]; then
      echo "  ── últimas linhas do log ──"
      tail -n 8 "$LOG" | sed 's/^/    /'
    fi
  else
    echo "✗ Painel PARADO."
    rm -f "$PIDFILE" 2>/dev/null || true
    return 1        # convenção: 'status' de serviço parado retorna não-zero
  fi
}

menu() {
  # Estado atual em uma linha, para contexto.
  if is_running || { p="$(pid_on_port || true)"; [[ -n "$p" ]] && is_our_ui "$p"; }; then
    echo "Estado: RODANDO na porta $PORT."
  else
    echo "Estado: PARADO."
  fi
  echo "Painel de redeploy — escolha uma opção:"
  echo "   1) start     — sobe o painel"
  echo "   2) stop      — derruba o painel"
  echo "   3) restart   — reinicia"
  echo "   4) status    — mostra o estado"
  echo "   q) sair"
  printf '▶ Opção: '
  read -r ans
  case "$ans" in
    1|start)   start ;;
    2|stop)    stop ;;
    3|restart) stop; start ;;
    4|status)  status ;;
    q|Q|sair|"") echo "Cancelado." ;;
    *) echo "Opção inválida: '$ans'" >&2; exit 1 ;;
  esac
}

case "${1:-}" in
  start)     start ;;
  stop)      stop ;;
  restart)   stop; start ;;
  status)    status ;;
  -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  "")        # sem argumento: menu se for terminal; senão, start (automação/boot)
    if [[ -t 0 ]]; then menu; else start; fi ;;
  *) echo "Uso: $(basename "$0") {start|stop|restart|status}  (ou sem argumento p/ menu)" >&2; exit 1 ;;
esac
