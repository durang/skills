#!/usr/bin/env bash
# GBrain stack maintenance — weekly cleanup + daily health alert.
# Subcommands:
#   cleanup : caches, journal vacuum, docker image prune, codex log purge,
#             stale gbrain-serve reaper. Weekly (Sun 15:00 UTC).
#   alert   : doctor score + disk check; Telegram alert on score drop >10
#             or disk >90%. Daily (16:20 UTC, after the 16:00 report).
# Both idempotent. State in ~/.gbrain/maintenance/.
set -u
HOME_DIR="$HOME"
# gbrain is a bun shim: without bun on PATH every call dies with
# "env: 'bun': No such file or directory" and the alert reports a
# false "score unavailable" (silent for 4 days, 2026-07-21..24).
export PATH="$HOME_DIR/.bun/bin:$HOME_DIR/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
STATE_DIR="$HOME_DIR/.gbrain/maintenance"
mkdir -p "$STATE_DIR"
LOG="$STATE_DIR/maintenance.log"
ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "$(ts) $*" >> "$LOG"; }

tg_send() {
  local msg="$1"
  local token
  token=$(python3 -c "import json; print(json.load(open('$HOME_DIR/.openclaw/openclaw.json'))['channels']['telegram']['botToken'])" 2>/dev/null)
  [ -z "$token" ] && { log "alert: no bot token"; return 1; }
  curl -sS -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    --data-urlencode "chat_id=1439730479" \
    --data-urlencode "text=$msg" >/dev/null 2>&1
}

cmd_cleanup() {
  log "cleanup: start"
  # Cron redirects open BEFORE the command runs: a missing log dir kills the
  # whole entry silently. This cost 10 days of sync and 292h of dream cycles
  # (2026-07-15..25). Recreate the dirs every week so it cannot recur.
  mkdir -p "$HOME_DIR/.gbrain/logs" "$HOME_DIR/.gbrain/maintenance" 2>/dev/null
  # 1. Safe caches (regenerate on demand)
  rm -rf "$HOME_DIR/.openclaw/agents/main/agent/codex-home/home/.cache"/* \
         "$HOME_DIR/.openclaw/agents/main/agent/codex-home/home/.npm/_cacache" 2>/dev/null
  pip cache purge >/dev/null 2>&1
  npm cache clean --force >/dev/null 2>&1
  # 2. Journald cap
  sudo journalctl --vacuum-size=300M >/dev/null 2>&1
  # 3. Docker: unused IMAGES only — never volumes (evolution postgres lives there)
  docker image prune -af >/dev/null 2>&1
  # 4. Codex log DB: purge >3d + vacuum (skip silently if locked).
  #    7d retention let it reach 685MB in 5 days (2026-08-01) — it is the
  #    single fastest-growing file on the box and holds only logs, no data.
  local db="$HOME_DIR/.openclaw/agents/main/agent/codex-home/logs_2.sqlite"
  if [ -f "$db" ]; then
    local cutoff=$(( $(date +%s) - 3*86400 ))
    timeout 120 sqlite3 "$db" "DELETE FROM logs WHERE ts < $cutoff; VACUUM;" 2>/dev/null \
      && log "cleanup: codex logs purged (<$cutoff)" \
      || log "cleanup: codex log purge skipped (locked/timeout)"
  fi
  # 5. Reap stale gbrain-serve MCP children (>48h). They are per-client stdio
  #    servers (wrapper/claude sessions); clients respawn them on demand.
  #    Excludes the Hermes watchdog-managed one only if young — same rule: >48h = stale.
  ps -eo pid,etimes,cmd | awk '/gbrain serve/ && !/awk/ && $2 > 172800 {print $1}' | while read -r pid; do
    kill "$pid" 2>/dev/null && log "cleanup: reaped stale gbrain serve pid=$pid"
  done
  log "cleanup: done — disk $(df -h / | awk 'NR==2{print $5}')"
}

cmd_alert() {
  local disk_pct score prev delta msg=""
  disk_pct=$(df -h / | awk 'NR==2{gsub("%","",$5); print $5}')
  # Doctor score (line: "Overall health score: N/100" or "Health score: N/100")
  score=$(cd "$HOME_DIR/gbrain" 2>/dev/null; timeout 300 "$HOME_DIR/.bun/bin/gbrain" doctor --summary 2>/dev/null \
    | grep -oE "(Overall health|Health) score:? *[0-9]+" | grep -oE "[0-9]+$" | tail -1)
  prev=$(cat "$STATE_DIR/last-score" 2>/dev/null || echo "")
  if [ -n "$score" ]; then
    echo "$score" > "$STATE_DIR/last-score"
    log "alert: score=$score prev=${prev:-none} disk=${disk_pct}%"
    if [ -n "$prev" ] && [ "$((prev - score))" -gt 10 ]; then
      msg="🚨 GBrain health cayó ${prev} → ${score}/100 (>10 pts). Corre /gbrain check."
    fi
  else
    log "alert: score unavailable"
    msg="⚠️ GBrain doctor no devolvió score (timeout o error). Corre /gbrain check."
  fi
  if [ "$disk_pct" -gt 90 ]; then
    msg="${msg:+$msg
}💾 Disco EC2 al ${disk_pct}%. Corre: bash ~/.openclaw/skills/gbrain/maintenance.sh cleanup"
  fi
  [ -n "$msg" ] && { tg_send "$msg"; log "alert: sent"; }
  return 0
}

case "${1:-}" in
  cleanup) cmd_cleanup ;;
  alert)   cmd_alert ;;
  *) echo "usage: $0 {cleanup|alert}"; exit 1 ;;
esac
