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
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID:?define TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$msg" >/dev/null 2>&1
}

# Promueve effective_date del frontmatter a la COLUMNA.
#
# POR QUE: el hook signal-detector SI escribe `effective_date:` en el
# frontmatter, pero gbrain no lo promueve a pages.effective_date — ni el put
# ni `extract timeline --include-frontmatter` lo hacen (verificado 2026-09-17).
# La columna es la que alimenta timeline density y la linea de tiempo, asi que
# sin esto cada pagina nueva nace sin posicion temporal: 0/51 el 2026-09-17.
# Prioriza frontmatter.effective_date (cuando PASO) sobre captured_at (cuando
# se capturo). Idempotente: sólo toca filas con la columna NULL.
cmd_backfill_dates() {
  local url
  url=$(python3 -c "import json;print(json.load(open('$HOME/.gbrain/config.json'))['database_url'])" 2>/dev/null)
  [ -z "$url" ] && { log "backfill_dates: sin database_url"; return 0; }
  local n1 n2
  n1=$(psql "$url" -tAc "UPDATE pages SET effective_date=(substring(frontmatter->>'effective_date' from '^[0-9]{4}-[0-9]{2}-[0-9]{2}'))::date, effective_date_source='date' WHERE deleted_at IS NULL AND effective_date IS NULL AND frontmatter->>'effective_date' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' AND (substring(frontmatter->>'effective_date' from '^[0-9]{4}-[0-9]{2}-[0-9]{2}'))::date BETWEEN '1990-01-01' AND CURRENT_DATE" 2>/dev/null | tr -dc '0-9')
  n2=$(psql "$url" -tAc "UPDATE pages SET effective_date=(substring(frontmatter->>'captured_at' from '^[0-9]{4}-[0-9]{2}-[0-9]{2}'))::date, effective_date_source='date' WHERE deleted_at IS NULL AND effective_date IS NULL AND frontmatter->>'captured_at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' AND (substring(frontmatter->>'captured_at' from '^[0-9]{4}-[0-9]{2}-[0-9]{2}'))::date BETWEEN '1990-01-01' AND CURRENT_DATE" 2>/dev/null | tr -dc '0-9')
  log "backfill_dates: ${n1:-0} desde effective_date + ${n2:-0} desde captured_at"
}

cmd_cleanup() {
  log "cleanup: start"
  cmd_backfill_dates
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
  # Leer el score de --json, NO de texto. `doctor --summary` dejó de imprimir
  # "Health score: N" en algún release (verificado roto el 2026-09-17 en
  # 0.50.5.0) y el grep devolvía vacío ⇒ la alerta mandaba un falso
  # "doctor no devolvió score" todos los días. --json expone health_score
  # como campo estable.
  score=$(cd "$HOME_DIR/gbrain" 2>/dev/null; timeout 600 "$HOME_DIR/.bun/bin/gbrain" doctor --json 2>/dev/null \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('health_score',''))" 2>/dev/null | tr -dc '0-9')
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

# ── autofix: ataca los BACKLOGS que `run.sh fix` no toca ──────────────
# POR QUÉ EXISTE: `/gbrain fix` corre embed/extract/migraciones, pero deja
# intactos los dos backlogs que hunden el doctor score:
#   conversation_facts_backlog  (~1965 páginas el 2026-09-27)
#   extract_atoms_backlog       (~2731 páginas)
# Sin esto el score se queda clavado en 25/100 aunque no haya UN solo FAIL.
#
# ENTREGA INCREMENTAL: cada pieza se manda a Telegram EN CUANTO termina, no
# al final. Un timeout en la pieza 3 no debe tragarse las piezas 1 y 2.
# NO usa `/gbrain sync` para SOUL.md: sync restaura desde canonical y el vivo
# suele ir ADELANTE (el 2026-09-27 habría borrado las reglas R7 v4.3).
cmd_autofix() {
  local t0 score_before score_after
  t0=$(date +%s)
  score_before=$(cd "$HOME_DIR/gbrain" 2>/dev/null; timeout 600 "$HOME_DIR/.bun/bin/gbrain" doctor --json 2>/dev/null \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('health_score',''))" 2>/dev/null | tr -dc '0-9')
  [ -z "$score_before" ] && score_before="?"
  log "autofix: start score=$score_before"

  # 1) atoms pendientes
  if timeout 3000 gbrain extract --stale --catch-up >>"$LOG" 2>&1; then
    tg_send "🧠 autofix 1/3 — atoms al día"; log "autofix: atoms ok"
  else
    tg_send "⚠️ autofix 1/3 — atoms falló (ver $LOG)"; log "autofix: atoms FAIL"
  fi

  # 2) conversation facts
  if timeout 3000 gbrain extract-conversation-facts >>"$LOG" 2>&1; then
    tg_send "🧠 autofix 2/3 — conversation facts al día"; log "autofix: facts ok"
  else
    tg_send "⚠️ autofix 2/3 — facts falló (ver $LOG)"; log "autofix: facts FAIL"
  fi

  # 3) links + timeline (--source db: el filesystem sólo ve ~2k de 30k páginas)
  if timeout 1800 gbrain extract all --source db >>"$LOG" 2>&1; then
    tg_send "🧠 autofix 3/3 — links + timeline extraídos"; log "autofix: extract ok"
  else
    tg_send "⚠️ autofix 3/3 — extract falló (ver $LOG)"; log "autofix: extract FAIL"
  fi

  # SOUL.md: sólo REPORTA el drift. Restaurar es decisión humana — la copia viva
  # puede ser la buena (ver nota arriba).
  local sl sc
  sl=$(md5sum "$HOME_DIR/.hermes/SOUL.md" 2>/dev/null | cut -d' ' -f1)
  sc=$(md5sum "$HOME_DIR/.hermes/canonical/SOUL.md" 2>/dev/null | cut -d' ' -f1)
  if [ -n "$sc" ] && [ "$sl" != "$sc" ]; then
    tg_send "📜 SOUL.md difiere del canónico. NO lo toqué — revisa el diff antes de restaurar: diff ~/.hermes/canonical/SOUL.md ~/.hermes/SOUL.md"
  fi

  score_after=$(cd "$HOME_DIR/gbrain" 2>/dev/null; timeout 600 "$HOME_DIR/.bun/bin/gbrain" doctor --json 2>/dev/null \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('health_score',''))" 2>/dev/null | tr -dc '0-9')
  [ -z "$score_after" ] && score_after="?"
  local mins=$(( ($(date +%s) - t0) / 60 ))
  tg_send "✅ autofix terminado en ${mins}min · score ${score_before} → ${score_after}"
  log "autofix: done score=$score_before->$score_after ${mins}min"
  return 0
}


# ── backup: pg_dump semanal del brain, VALIDADO por conteo ────────────────────
# pg_dump contra un servidor MÁS NUEVO que él (Supabase es PG 17.6, el cliente del EC2
# es 15) sale con exit 0 y deja un .gz de 20 bytes: un respaldo que parece respaldo.
# El 2026-09-28 pasó exactamente eso, y el segundo intento se cortó a 9MB. Por eso:
# cliente PG17 en docker, y el archivo solo cuenta si el CONTENIDO cuadra con la base
# viva (tablas + filas de pages), no si existe o pesa algo.
# Nota: cleanup (dom 15:00) hace `docker image prune`, así que la imagen se vuelve a
# bajar en cada corrida; docker run la baja solo.
cmd_backup() {
  local dir="$HOME_DIR/backups/gbrain-db" keep=2 url out envf rc tables=0 rows=0 live free_g why=""
  mkdir -p "$dir"; chmod 700 "$dir"; rm -f "$dir"/*.partial
  url="${GBRAIN_DATABASE_URL:-${DATABASE_URL:-}}"
  if [ -z "$url" ]; then tg_send "🔴 backup del brain: sin GBRAIN_DATABASE_URL en el entorno"; log "backup: no url"; return 1; fi
  free_g=$(df -BG --output=avail "$HOME_DIR" | tail -1 | tr -dc '0-9')
  if [ "${free_g:-0}" -lt 2 ]; then tg_send "🔴 backup del brain omitido: solo ${free_g}G libres"; log "backup: low disk ${free_g}G"; return 1; fi
  out="$dir/gbrain-db-$(date -u +%Y%m%d-%H%M).sql.gz"
  envf=$(mktemp /var/tmp/pgenv.XXXXXX); chmod 600 "$envf"; printf 'PGURL=%s\n' "$url" > "$envf"
  log "backup: start -> $out"
  timeout 3000 docker run --rm --env-file "$envf" postgres:17-alpine sh -c 'pg_dump "$PGURL" --no-owner --no-acl' 2>"$dir/last-error.log" | gzip -6 > "$out.partial"
  rc=${PIPESTATUS[0]}
  rm -f "$envf"
  if [ "$rc" -ne 0 ]; then why="pg_dump salió con código $rc"
  elif ! gzip -t "$out.partial" 2>/dev/null; then why="gzip corrupto"
  else
    read -r tables rows < <(zcat "$out.partial" | awk '/^CREATE TABLE /{t++} /^COPY public\.pages /{f=1;next} f&&/^\\\.$/{f=0} f{r++} END{print t+0, r+0}')
    live=$(cd "$HOME_DIR/gbrain" 2>/dev/null; timeout 120 "$HOME_DIR/.bun/bin/gbrain" stats 2>/dev/null | awk '/^Pages:/{print $2; exit}')
    if [ "${tables:-0}" -lt 50 ]; then why="solo ${tables:-0} tablas en el dump"
    elif [ -z "${live:-}" ] || [ "$live" -lt 1 ]; then why="no pude leer el conteo vivo para validar"
    elif [ $(( ${rows:-0} * 100 )) -lt $(( live * 95 )) ]; then why="el dump trae ${rows:-0} filas de pages y la base viva tiene $live"; fi
  fi
  if [ -n "$why" ]; then
    rm -f "$out.partial"
    log "backup: FAIL — $why | $(head -c 200 "$dir/last-error.log" 2>/dev/null | tr '\n' ' ' | sed -E 's#postgres(ql)?://[^ ]+#<url>#g')"
    tg_send "🔴 respaldo del brain FALLÓ: $why. Se conservan los anteriores."
    return 1
  fi
  mv "$out.partial" "$out"; chmod 600 "$out"
  ls -1t "$dir"/gbrain-db-*.sql.gz 2>/dev/null | tail -n +$((keep+1)) | xargs -r rm -f
  log "backup: ok $(du -h "$out" | cut -f1) tables=$tables pages=$rows live=$live"
  tg_send "✅ respaldo del brain: $(du -h "$out" | cut -f1) · $tables tablas · $rows filas de pages (vivo: $live) · se conservan $keep"
  return 0
}


case "${1:-}" in
  cleanup) cmd_cleanup ;;
  backfill-dates) cmd_backfill_dates ;;
  alert)   cmd_alert ;;
  autofix) cmd_autofix ;;
  backup)  cmd_backup ;;
  *) echo "usage: $0 {cleanup|alert|backfill-dates|autofix|backup}"; exit 1 ;;
esac
