---
name: hermestrack
description: "Hermes Command Center — Full HERMES Agent installation scan with visual dashboard. Status, MCP servers, skills (89 bundled + custom), memory providers, cron, sessions, gateways (Telegram/Discord/Slack), insights, providers, security, disk. Generates HERMES_DASHBOARD.md. Companion to openclawtrack — both feed into /gbrain Layer 17b for central orchestration."
allowed-tools: Read Write Edit Bash Glob Grep Agent
user-invocable: true
distribute-to: [claude]
---

# /hermestrack — Hermes Command Center

You are the HERMES Agent infrastructure scanner. Analyze the ENTIRE HERMES installation and generate a visual command center dashboard. Companion to `/openclawtrack` — same pattern, adapted to HERMES.

**Output file:** Write to `HERMES_DASHBOARD.md` in the user's home directory (detect with `echo $HOME`).

Every number must come from a real command. No guesses.

## ADAPTIVE — Works on ANY HERMES installation

Rules (mirror `/openclawtrack`):
- Detect paths dynamically (don't hardcode `/home/ec2-user`)
- Use `$HOME` for all paths
- Only show sections with data (skip empty sections)
- Detect HERMES install: `which hermes` or `~/.local/bin/hermes`
- HERMES home: `~/.hermes/` (config.yaml, .env, hermes-agent/, sessions/, skills/, memories/, cron/)
- If a feature isn't configured, show "available" not "missing"

## Incremental Mode

If `HERMES_DASHBOARD.md` exists and was scanned < 1 hour ago: report "Dashboard is current" and skip.

## Scan Protocol

Run ALL these commands, then generate the dashboard.

### SYSTEM
```bash
hermes --version
hermes status 2>&1 | head -50
hermes doctor 2>&1 | head -40
ps -ef | grep -E "hermes" | grep -v grep | head -10
systemctl --user list-units --type=service --state=running 2>&1 | grep -i hermes
free -m | head -2
df -h / | tail -1
uptime
```

### CONFIG
```bash
ls ~/.hermes/
head -100 ~/.hermes/config.yaml
# Don't dump .env values — only count keys + show first 4 chars
grep -cE "^[A-Z_]+_API_KEY|^[A-Z_]+_TOKEN" ~/.hermes/.env
```

### MCP SERVERS (this is critical — gbrain integration)
```bash
hermes mcp list
hermes mcp tools gbrain 2>&1 | head -50    # 41 tools de gbrain
# Verify gbrain serve works
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"hermestrack","version":"0.1"}}}' | timeout 5 gbrain serve | head -1
```

### MODEL + PROVIDER
```bash
grep -A 3 "^model:" ~/.hermes/config.yaml | head -10
hermes model 2>&1 | head -20
hermes auth 2>&1 | head -15
hermes fallback list 2>&1 | head -10
```

### SKILLS (89 bundled + imported from OpenClaw + custom)
```bash
ls ~/.hermes/skills/ 2>/dev/null
ls ~/.hermes/skills/openclaw-imports/ 2>/dev/null | head -30
hermes skills list 2>&1 | head -40
```

### MESSAGING GATEWAYS
```bash
hermes gateway status 2>&1 | head -10
# Telegram, Discord, Slack, WhatsApp, Signal — show only configured
grep -E "TELEGRAM_BOT_TOKEN|DISCORD_BOT_TOKEN|SLACK_TOKEN|WHATSAPP|SIGNAL" ~/.hermes/.env 2>/dev/null | sed 's/=.*/=***/' | head -10
```

### MEMORY + GBRAIN INTEGRATION
```bash
ls ~/.hermes/memories/ 2>/dev/null
ls ~/.hermes/SOUL.md 2>/dev/null
# Check memory provider config
hermes memory status 2>&1 | head -15
# gbrain stats (the actual brain)
gbrain stats 2>&1 | head -10
```

### CRON
```bash
hermes cron list 2>&1 | head -20
ls ~/.hermes/cron/ 2>/dev/null
crontab -l 2>/dev/null | grep -E "hermes|gbrain|compound" | head -10
```

### SESSIONS
```bash
hermes sessions list 2>&1 | head -15
ls ~/.hermes/sessions/ 2>/dev/null | wc -l
ls ~/.hermes/logs/ 2>/dev/null | head -5
```

### DASHBOARD WEB
```bash
hermes dashboard --status 2>&1 | head -10
ss -tlnp 2>/dev/null | grep ":9119" | head -3
```

### INSIGHTS
```bash
hermes insights 2>&1 | head -30
```

### CUSTOM PROVIDERS (XAI, MiniMax, etc. heredados de OpenClaw)
```bash
grep -A 2 "custom_providers:" ~/.hermes/config.yaml | head -30
```

### SECURITY
```bash
stat -c %a ~/.hermes/.env ~/.hermes/config.yaml 2>/dev/null
grep -cE "ALLOWED_USER_IDS|allowed_users" ~/.hermes/config.yaml ~/.hermes/.env 2>/dev/null
```

### MIGRATION REPORT (qué heredó de OpenClaw)
```bash
ls ~/.hermes/migration/openclaw/ 2>/dev/null | head -3
cat ~/.hermes/migration/openclaw/*/report.json 2>/dev/null | python3 -m json.tool 2>/dev/null | head -30
```

## Dashboard Visual Format

Use the same conventions as `/openclawtrack`:
- `diff` code blocks for RED text
- Box-drawing: `╔═══╗ ║ ╠═══╣ ╚═══╝`
- Progress bars: `████░░░░` with percentages
- Icons: ✅ ❌ ⚠️ 🔒 ⬜ 📅 📂 🧠 🔐 💾 ⏰ ⚡ 🤖 🎨 💰 🥇 🎯
- Alerts in diff blocks (red = critical, yellow = warning)

## Required Sections (in order)

1. ASCII HERMES title in green diff block
2. LIVE STATUS — bars for hermes process, dashboard, gateway (Telegram), MCP gbrain, RAM, disk, uptime
3. BRAIN INTEGRATION — model, provider, gbrain MCP tools count, fallback chain
4. MCP SERVERS — table with name, transport, tools count, status
5. SKILLS — bundled (89), imported from OpenClaw (24), custom (count by category)
6. MESSAGING GATEWAYS — Telegram (with bot username if visible), Discord, Slack, WhatsApp, Signal — show ✅ for configured
7. MEMORY — SOUL.md present, memories/ entries, daily memory dates
8. CRON — HERMES cron jobs with schedule + last run + status
9. SESSIONS — count, recent
10. CUSTOM PROVIDERS — XAI, MiniMax, etc. with source (imported / native)
11. SECURITY SCAN — file permissions, allowed user IDs configured, exposure check
12. MIGRATION FROM OPENCLAW — which 30+ items imported, when, where
13. DASHBOARD WEB — port, host, accessible URL (Tailscale or localhost)
14. RESOURCE USAGE — RAM consumed by hermes process, disk usage of ~/.hermes/
15. ALERTS — color-coded (red diff = high, `!` = medium, `+` = low)
16. CROSS-REFERENCE — comparison row vs OpenClaw (same skill loaded? same MCP server? different bot tokens?)

## Cross-skill correlation (this is the key differentiator)

End the dashboard with this section:

### Cross-stack consistency check
- Same gbrain MCP server in both HERMES and OpenClaw? ✅/❌
- Different Telegram bot tokens? ✅ (must be different) / ❌ (CRITICAL — they'll fight)
- Same SOUL.md inherited? ✅
- Same skills loaded in both? Show diff
- Both feeding the same Postgres brain? ✅

This section feeds back into `/gbrain` Layer 17b skill propagation.

## Rules

1. Every value from a real command — no guesses
2. Missing = report as MISSING with command to fix
3. Max 450 lines
4. Report 1-line summary after generating
5. NEVER print API key values — only first 4 chars + "..."
6. NEVER print bot tokens — only show ✅/❌

## Triggers

`/hermestrack`, `revisa hermes`, `hermes status`, `hermes infrastructure`, `salud hermes`
