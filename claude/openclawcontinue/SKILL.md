---
name: openclawcontinue
description: "OpenClaw Optimizer — Analyzes your setup and tells you what to improve: free disk space, optimize RAM, fix security, enable features, recover disabled cron jobs, cleanup duplicates. Actionable steps with priority."
allowed-tools: Read Write Edit Bash Glob Grep Agent
user-invocable: true
distribute-to: [claude]
---

# /openclawcontinue — OpenClaw Optimizer & Action Plan

You are the OpenClaw optimization advisor. You analyze the current state and generate a prioritized action plan of improvements.

## What You Do

1. Read the existing dashboard at `$HOME/OPENCLAW_DASHBOARD.md` (if exists)
2. Run fresh diagnostics

## ADAPTIVE — Works on ANY OpenClaw installation

- Use `$HOME` and `~` for all paths (never hardcode a specific user path)
- Only suggest fixes for things that actually exist on THIS machine
- Detect the OpenClaw config at `~/.openclaw/openclaw.json`
- Only analyze plugins/agents/skills that are actually installed
3. Generate an ACTION PLAN with improvements, grouped by category

## Diagnostic Commands

```bash
# DISK ANALYSIS — what can be cleaned
du -sh ~/archive/clawd-legacy/ 2>/dev/null
du -sh ~/node_modules/ 2>/dev/null
du -sh ~/lossless-claw/node_modules/ 2>/dev/null
find /tmp/openclaw/ -name "*.log" -size +10M 2>/dev/null
find ~/.openclaw/agents/*/sessions/ -name "*.jsonl" -size +5M 2>/dev/null
du -sh ~/.openclaw/media/ ~/.openclaw/browser/ ~/.openclaw/completions/ 2>/dev/null

# RAM ANALYSIS
ps aux --sort=-%mem | head -10
free -m

# SECURITY GAPS
stat -c "%a %n" ~/.openclaw/openclaw.json ~/.openclaw/.env ~/.openclaw/secrets.env 2>/dev/null
grep -cE "sk-|gsk_|gho_|eyJ|AAF|bot[0-9]" ~/.openclaw/openclaw.json
grep -cE "sk-|gsk_|gho_|eyJ|AAF" ~/.config/systemd/user/openclaw-gateway.service

# DISABLED FEATURES
cat ~/.openclaw/cron/jobs.json | python3 -c "import sys,json; [print(j.get('name','?'), j.get('enabled',True)) for j in json.load(sys.stdin)]"
grep '"enabled": false' ~/.openclaw/openclaw.json

# AGENTS NOT IN CONFIG
ls ~/agents/ | while read d; do grep -q "\"$d\"" ~/.openclaw/openclaw.json || echo "NOT IN CONFIG: $d"; done

# DUPLICATE FILES
ls ~/skills/ | while read s; do [ -d ~/.agents/skills/$s ] && echo "DUPLICATE: $s"; done

# STALE SESSIONS
find ~/.openclaw/agents/*/sessions/ -name "*.jsonl" -mtime +30 2>/dev/null | wc -l

# OPENCLAW HEALTH
openclaw doctor 2>&1 | head -30
openclaw tasks audit 2>&1 | head -20
```

## Output Format

Write to stdout (don't create a file). Use this format:

```
╔══════════════════════════════════════════════════════════════╗
║  OPENCLAW OPTIMIZER — Action Plan                           ║
║  Scanned: YYYY-MM-DD HH:MM UTC                             ║
╚══════════════════════════════════════════════════════════════╝

🔴 CRITICAL (do now)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. [Problem] — [Impact] — [One-line fix command]

🟡 RECOMMENDED (this week)  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. [Improvement] — [Benefit] — [Command or steps]

🟢 NICE TO HAVE (when you have time)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. [Enhancement] — [Benefit]

💾 DISK RECOVERY PLAN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[Table of what can be deleted and how much space each saves]
Total recoverable: X.X GB

🧠 RAM OPTIMIZATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[Current top memory consumers]
[Suggestions to reduce]

📊 HEALTH SCORE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Security:  ██████████████████░░  XX%
Disk:      ██████████████████░░  XX%
Config:    ██████████████████░░  XX%  
Features:  ██████████████████░░  XX%
Overall:   ██████████████████░░  XX%
```

## Rules
1. Every suggestion must have a concrete command to execute
2. Show exact GB/MB that can be recovered
3. Prioritize by impact (biggest gains first)
4. Never suggest deleting active config or data
5. Be specific — "delete X" not "clean up some files"
