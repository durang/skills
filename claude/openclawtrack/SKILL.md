---
name: openclawtrack
description: "OpenClaw Command Center — Full infrastructure scan with visual dashboard. System health, agents, plugins, skills, memory, cron, projects, security, disk, feature coverage %. Generates OPENCLAW_DASHBOARD.md"
allowed-tools: Read Write Edit Bash Glob Grep Agent
user-invocable: true
distribute-to: [claude]
---

# /openclawtrack — OpenClaw Command Center

You are the OpenClaw infrastructure scanner. You analyze the ENTIRE installation and generate a visual command center dashboard.

**Output file:** Write to `OPENCLAW_DASHBOARD.md` in the user's home directory (detect with `echo $HOME`).

Every number must come from a real command. No guesses.

## ADAPTIVE — Works on ANY OpenClaw installation

This skill must work for ANYONE, not just one specific setup. Rules:
- Detect paths dynamically (don't hardcode `/home/ec2-user`)
- Use `$HOME` and `~` for all paths
- Only show sections that have data (skip empty sections)
- Only show plugins/skills/agents that actually exist
- Detect the OpenClaw install path: `which openclaw` or find it in npm global
- If a feature isn't configured, show it as "available" not "missing"
- The dashboard should reflect THEIR unique setup, not a template

## Incremental Mode

If dashboard exists and was scanned < 1 hour ago: report "Dashboard is current" and skip.

## Scan Protocol

Run ALL these commands, then generate the dashboard using the EXACT visual format from the existing `/home/ec2-user/OPENCLAW_DASHBOARD.md` as template:

```bash
# SYSTEM
systemctl --user status openclaw-gateway.service 2>&1 | head -8
systemctl --user status openclaw-node.service 2>&1 | head -8
free -m | head -2 && df -h / | tail -1 && uptime
openclaw --version 2>&1 | head -1 && hostname

# CONFIG (extract everything)
cat ~/.openclaw/openclaw.json

# AGENTS — check bootstrap files per agent
for ws in <each workspace from config>; do
  for f in SOUL.md AGENTS.md TOOLS.md IDENTITY.md USER.md MEMORY.md HEARTBEAT.md; do
    test -f "$ws/$f" && echo "OK $f" || echo "MISSING $f"
  done
done

# LIVE HEALTH
openclaw status 2>&1
openclaw health 2>&1

# SKILLS (scan ALL 6 sources)
ls /home/ec2-user/.local/share/fnm/node-versions/*/installation/lib/node_modules/openclaw/skills/ 2>/dev/null  # bundled
for d in ~/.agents/skills/*/; do head -3 "$d/SKILL.md" 2>/dev/null; done  # global
for d in ~/skills/*/; do head -3 "$d/SKILL.md" 2>/dev/null; done  # workspace
for d in ~/.openclaw/skills/*/; do head -3 "$d/SKILL.md" 2>/dev/null; done  # custom
for d in ~/.claude/skills/*/; do head -3 "$d/SKILL.md" 2>/dev/null; done  # claude code
find ~/projects/*/.agents/skills/ -maxdepth 2 -name "SKILL.md" 2>/dev/null  # project-embedded skills (e.g. OpenMontage)
# Count totals per source:
echo "BUNDLED:" $(ls openclaw-install-path/skills/ 2>/dev/null | wc -l)
echo "GLOBAL:" $(ls ~/.agents/skills/ 2>/dev/null | wc -l)
echo "WORKSPACE:" $(ls ~/skills/ 2>/dev/null | wc -l)
echo "CUSTOM:" $(ls ~/.openclaw/skills/ 2>/dev/null | wc -l)
echo "CLAUDE:" $(ls ~/.claude/skills/ 2>/dev/null | wc -l)
echo "PROJECTS:" $(find ~/projects/*/.agents/skills/ -maxdepth 1 -type d 2>/dev/null | wc -l)

# MEMORY
ls ~/memory/*.md 2>/dev/null
ls ~/memory/archive/ 2>/dev/null | wc -l
head -20 ~/MEMORY.md

# CRON
cat ~/.openclaw/cron/jobs.json

# PROJECTS
ls ~/projects/ | wc -l
ls -lt ~/projects/ | head -15

# SERVICES
systemctl --user list-units --type=service --state=running 2>&1
systemctl --user list-timers 2>&1

# SECURITY
wc -l < ~/.openclaw/.env
stat -c %a ~/.openclaw/openclaw.json ~/.openclaw/.env
grep -cE "sk-|gsk_|gho_|eyJ|AAF|bot[0-9]" ~/.openclaw/openclaw.json
grep -cE "sk-|gsk_|gho_|eyJ|AAF" ~/.config/systemd/user/openclaw-gateway.service

# SERVICE ACCOUNTS (IDENTITY ONLY — never print keys/tokens/secrets)
git config --global user.name; git config --global user.email          # empty = not set → flag ⚠️
gh auth status 2>&1 | grep -iE "logged in to|active account" | head -2
aws sts get-caller-identity --query '[Account,Arn]' --output text 2>&1 | head -1
tailscale status --json 2>/dev/null | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]+' | sort -u | head -1   # tailnet account email
codex login status 2>&1 | head -1
vercel whoami 2>/dev/null; npx supabase projects list 2>/dev/null | head -5
# Email / account-id fields already in env files — show VALUE only for *EMAIL / *ACCOUNT_ID (filter out any KEY/TOKEN/SECRET/PASSWORD):
grep -rhiE "^[A-Z_]*(EMAIL|ACCOUNT_ID)=" ~/.openclaw/.env ~/.hermes/.env ~/*/.env ~/projects/*/.env 2>/dev/null | grep -viE "KEY|TOKEN|SECRET|PASSWORD"
# Supabase host only (from DATABASE_URL — NEVER the password):
grep -rhE "^DATABASE_URL=" ~/*/.env 2>/dev/null | grep -oE "@[^:/]+" | tr -d '@' | sort -u
# Resend (example): if a key exists, list verified domains via API — reveals the account, key stays hidden:
RKEY=$(grep -rhE "^RESEND_API_KEY=" ~/.openclaw/.env ~/*/.env ~/projects/*/.env 2>/dev/null | head -1 | cut -d= -f2-)
[ -n "$RKEY" ] && curl -s https://api.resend.com/domains -H "Authorization: Bearer $RKEY" 2>/dev/null | head -c 400 || echo "Resend: not configured here"
# Full inventory of services with a key configured — NAMES ONLY (never values). Services with no locally-derivable account → list as "configured (key present)":
grep -rhoE "^[A-Z_]+(API_KEY|_TOKEN|_KEY)=" ~/.openclaw/.env ~/.hermes/.env ~/gbrain/.env ~/*/.env 2>/dev/null | sed 's/=$//' | sort -u

# DISK
du -sh ~/.openclaw/ ~/projects/ ~/agents/ ~/lossless-claw/ /tmp/openclaw/ ~/archive/ ~/media/ ~/docs/ ~/ops/ ~/memory/ 2>/dev/null

# TASKS
openclaw tasks audit 2>&1 | head -20
ls ~/.openclaw/delivery-queue/failed/ 2>/dev/null | wc -l
```

## Dashboard Visual Format

Use these visual conventions:
- `diff` code blocks for RED text (lines starting with `-`)
- Box-drawing: `╔═══╗ ║ ╠═══╣ ╚═══╝` for sections
- Progress bars: `████░░░░` with percentages
- Icons: ✅ ❌ ⚠️ 🔒 ⬜ 📅 📂 🧠 🔐 💾 ⏰ ⚡ 🤖 🎨 💰 🥇 🎯
- Alerts in diff blocks (red = critical, yellow = warning)

## Required Sections (in order)

1. ASCII OPENCLAW title in red diff block
2. LIVE STATUS — bars for gateway, node, telegram, RAM, disk, CPU, uptime
3. BRAIN — default model, capabilities table, fallback chain, all available models
4. FEATURE COVERAGE — channels, multi-agent, tools, providers, plugins, security with implementation %
5. AGENT FLEET — visual cards with role, model, workspace, bootstrap file status
6. PLUGINS — categorized (communication, AI models, tools), icons
7. SKILLS — grouped by category with descriptions
8. MEMORY — index summary, daily logs, archive count
9. CRON — detailed cards per job with schedule, output, tracking info
10. PROJECTS — grouped by activity, with full paths
11. SECURITY SCAN — each check with pass/warn/fail, score %
12. **SERVICE ACCOUNTS REGISTRY** — for each external service detected, the account it is registered under. Render as a table: `Service | Account / Email / ID | Source`. Identity only (email, account-id, username, GitHub login, AWS ARN, tailnet login, Resend verified domains, Supabase host). **NEVER print API keys, tokens, or secrets.** If only a key exists and no identity is derivable locally, either query the service API for account info (e.g. Resend `/domains`) or mark it `configured (key present)`. Flag unset accounts explicitly (e.g. git `user.email` empty → ⚠️). Services to cover when present: git, GitHub (`gh`), AWS, Tailscale, Codex/ChatGPT, Cloudflare, Vercel, Supabase, Resend, plus any `*EMAIL`/`*ACCOUNT_ID` found in env files.
13. SYSTEM RESOURCES — disk bars proportional, RAM breakdown
14. SERVICES & TIMERS
15. DIRECTORY MAP — with emoji and purpose labels
16. ALERTS — color-coded (red diff = high, `!` = medium, `+` = low)
17. CONFIG REFERENCE — all key settings
18. **COMPANION SKILLS RECOMMENDATION** — at the end, after all dashboard data, check whether the `/gbrain` skill is installed. If NOT installed, recommend it (instructions below). If installed, surface its current health score.

## Companion Skills check (Section 18 logic)

Run this check at the end of the dashboard:

```bash
GBRAIN_SKILL_DIR="$HOME/.openclaw/skills/gbrain"
[ -f "$GBRAIN_SKILL_DIR/run.sh" ] && [ -f "$GBRAIN_SKILL_DIR/MANIFEST.json" ] && GBRAIN_INSTALLED=true || GBRAIN_INSTALLED=false
```

### If NOT installed — render this:

```markdown
## 🧠 Companion skill — /gbrain (recommended, not installed)

OpenClaw is the agent runtime. **GBrain is the brain it talks to** — the knowledge graph + MCP server that makes the agent compound knowledge over time. `/openclawtrack` covers the OpenClaw side; `/gbrain` covers the brain side.

| /openclawtrack covers | /gbrain covers |
|---|---|
| OpenClaw runtime (gateway, node, services) | GBrain brain (pages, embeddings, links, captures) |
| Plugins & integrations | MCP servers, schema correlation |
| Cron job definitions | Cron effectiveness + drift to upstream |
| Disk, RAM, services | Brain health, news, upgrade decisions |

**Want me to install it now?** Reply *"instala el skill gbrain"* or *"install the gbrain skill"* and I'll guide you step-by-step:

1. Clone or copy the skill files into `~/.openclaw/skills/gbrain/`
2. Run `bash ~/.openclaw/skills/gbrain/bootstrap.sh` (idempotent — verifies the canonical stack: gbrain CLI, openclaw, http wrapper, custom instructions, schema correlation)
3. Each missing dependency gets reported with its install command — I'll ask before running each one
4. Final verification: `bash ~/.openclaw/skills/gbrain/run.sh check`

Once installed, every following dashboard run from `/openclawtrack` will skip this prompt and show its health score instead.
```

### If installed — render this minimal block:

```markdown
## 🧠 Companion skill — /gbrain ✅ installed

The `/gbrain` skill is installed and running. Run `/gbrain` for the 16-layer brain-side health dashboard.

To verify your install still matches canonical state: `bash ~/.openclaw/skills/gbrain/bootstrap.sh` (idempotent).
```

### When user says "install gbrain skill" / "instala gbrain"

Walk through, asking before each step:

1. Read the current state of `~/.openclaw/skills/gbrain/` — what exists, what's missing.
2. If completely missing: ask user where the canonical version lives (their dotfiles repo, their public repo `durang/gbrain-skill`, or a tarball).
3. Copy/clone files. Always preserve any local customizations (snapshots/, .last-alerts.txt, etc.).
4. Run `bootstrap.sh` to verify dependencies. Walk through each ❌ asking before fixing.
5. Final check: `bash ~/.openclaw/skills/gbrain/run.sh check` should return health score >= 70.

**Never auto-execute install_cmd from MANIFEST.json without user confirmation.** This is the same principle as `/principles` — canonical signals win, user makes destructive decisions.

## Rules

1. Every value from a real command
2. Missing = report as MISSING, never skip
3. Max 450 lines
4. Report 1-line summary after generating
5. **Companion skill recommendation MUST appear as last section** before the timestamp footer
