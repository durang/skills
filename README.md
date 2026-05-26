<div align="center">

# 🧠 /gbrain

### **One command to orchestrate your entire AI agent stack.**

[![Status](https://img.shields.io/badge/status-canonical-success?style=flat-square)](https://github.com/durang/skills)
[![Stack](https://img.shields.io/badge/stack-Claude_Code_+_OpenClaw_+_HERMES_+_GBrain-blue?style=flat-square)](https://github.com/durang/skills)
[![Layers](https://img.shields.io/badge/dashboard-25_sections-orange?style=flat-square)](https://github.com/durang/skills/tree/master/shared/gbrain)
[![Verified](https://img.shields.io/badge/lie--detector-25_claims-brightgreen?style=flat-square)](https://github.com/durang/skills/tree/master/shared/gbrain)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE)

**Type `/gbrain` once. Your entire multi-agent infrastructure updates canonically, safely, zero downtime.**

[Install](#-install) · [The Dashboard](#-the-dashboard--19-layers--6-sub-layers) · [Subcommands](#-subcommands) · [Philosophy](#-philosophy)

</div>

---

## ✨ What it does

```bash
$ /gbrain sync

## 1. Sincronizar monorepo skills
✅ Skills monorepo: al día (a1a1263)

## 2. Deploy skills (install.sh)
✅ 10 skills deployed → Claude Code + OpenClaw + HERMES

## 3. HERMES claw migrate (refresh skills, NO secrets)
✅ 70 migrated, 22 skipped safely

## 4. Validar SOUL.md canonical
⚠️ SOUL.md cambió tras migrate
✅ Auto-restaurado desde canonical (anti-overwrite guard)

## 5. Verificar md5 cross-runtime
| gbrain        | ✅ | ✅ | ✅ |
| whatsapp      | ✅ | ✅ | ✅ |
| openclawtrack | ✅ | n/a | ✅ |
| hermestrack   | ✅ | n/a | ✅ |

🟢 Stack canonical · 0 downtime · 0 broken brains
```

**One command. Five orchestrated steps. Zero broken brains.**

---

## 🤯 Why this exists

Running a real multi-agent stack — Claude Code CLI + OpenClaw Telegram bot + HERMES WhatsApp agent + GBrain knowledge base + dual-agent WhatsApp dashboard — used to mean:

- ❌ 5+ separate update commands across 3 runtimes
- ❌ `SOUL.md` overwritten by `hermes claw migrate` (silent destroyer)
- ❌ Skills out of sync between Claude Code, OpenClaw, HERMES
- ❌ Bot tokens accidentally migrated wrong place
- ❌ "Is my brain dead?" debugging 3x per week
- ❌ Stale `gbrain-skill` standalone repo + monorepo drift

**60+ hours of production debugging** distilled into:

✅ **`/gbrain sync`** — one canonical command, every runtime aligned
✅ **`/gbrain verify`** — 25-claim lie-detector (`never claim done on request-shape alone`)
✅ **Layer 19 AWS Infra** — CloudTrail + GuardDuty + Budget + DLM + MFA + EBS encryption all monitored
✅ **SOUL.md canonical guard** — auto-restores after any tool tries to overwrite
✅ **SEGURIDAD BLINDADA** — anti-prompt-injection 10-section block on every WhatsApp contact
✅ **Default-deny security** — 5 layers deep (bridge env → config.yaml → mention → profile .md → SOUL.md)

---

## 🎯 The Dashboard — 19 layers + 6 sub-layers

`/gbrain check` (or just `/gbrain`) renders a full markdown dashboard. Every claim is auto-verified by `/gbrain verify` (lie-detector). Any drift → 🔴 banner instantly.

| # | Layer | Mide |
|---|-------|------|
| 🚨 | **Alert banner** | stuck sessions, missing API keys, no fallbacks, queue >100, AWS drift, SOUL.md drift |
| 1 | Versiones | GBrain + OpenClaw vs latest |
| 2 | Runtime | Gateway, Telegram conns, model + fallbacks, MCP, SOUL.md |
| 3 | Doctor | `gbrain doctor --json` structured |
| 3b | Schema correlation | DB tables ↔ wrapper ↔ skills (silent migration drift) |
| 4 | Stats | pages, chunks, embedded, links, timeline, tags |
| 5 | Skills (OpenClaw) | signal-detector, brain-ops, etc. |
| 5b | HERMES integration | parallel runtime, MCP link, bot conflict detection |
| 6 | Capture 24h | pages/links/timeline + `gbrain__` MCP calls |
| 7 | Bugs upstream | tu versión vs known issues |
| 8 | News | últimas releases + PRs + issues |
| 9 | Snapshot diff | stats delta vs anterior |
| 10 | Archivos canónicos | SOUL/MEMORY/openclaw.json mtime |
| 11 | MCP Health | servers + binarios |
| 11b | Wrappers + Integrations | HTTP wrapper, recipes, OAuth clients |
| 12 | Stuck sessions | 1h rolling count |
| 13 | Process env audit | `*_API_KEY` count |
| 14 | Cron failure rate | 24h jobs-state |
| 14b | System crontab canonical | MANIFEST declarado vs real |
| 15 | Upstream changelog | últimos 15 commits ✅ / 🔜 |
| 16 | Upgrade Decision Engine | INSTALAR / ESPERAR / SKIP por tool |
| 17 | Upstream Features Watch | features nuevas + try-it |
| 17b | Skill propagation | satellite skills hints |
| 18 | MCP clients + custom instructions | ¿clients tienen reglas v3+? |
| 18b | Cross-runtime active model | live read OpenClaw / HERMES / Codex CLI |
| **19** | **☁️ AWS Infra Health** | **CloudTrail · GuardDuty · Budget · DLM · SG · EBS · IMDSv2 · root keys · MFA × 2 · SOUL.md canonical guard · GBrain stack page** |

**Every section** has a verifier. **Nothing is claimed done** without ground-truth check.

---

## 🛰️ Featured skills (also live in this monorepo)

| Skill | Purpose | Trigger |
|-------|---------|---------|
| 🧠 **[gbrain](shared/gbrain/)** | Health dashboard + orchestrator. 25 sections. Layer 19 AWS Infra. `/gbrain sync`. | `/gbrain`, `/gbrain sync`, `/gbrain verify` |
| 💬 **[whatsapp](shared/whatsapp/)** | Dual-agent dashboard. Default-deny security. SEGURIDAD BLINDADA 10-section anti-injection block. PDF auto-send. | `/whatsapp` |
| 🔍 **[openclawtrack](claude/openclawtrack/)** | Full OpenClaw infrastructure scan + visual dashboard | `/openclawtrack` |
| 🌀 **[hermestrack](claude/hermestrack/)** | HERMES agent dashboard + skills + cron + sessions | `/hermestrack` |
| 🛡️ **[openclaw-security](claude/openclaw-security/)** | Security hardening checklist for EC2 OpenClaw | `/openclaw-security` |
| ⚡ **[openclawcontinue](claude/openclawcontinue/)** | OpenClaw optimizer — actionable improvements with priority | `/openclawcontinue` |
| ✨ 9 more | GSAP, mmx-cli, brain-write-macro, signal-detector | varios |

---

## 🚀 Install

```bash
git clone https://github.com/durang/skills ~/skills
cd ~/skills
./install.sh   # auto-deploys all skills to Claude Code + OpenClaw + HERMES
```

That's it. Then in Claude Code:

```bash
/gbrain          # dashboard
/gbrain sync     # update everything canonically
/gbrain verify   # lie-detector all claims
```

---

## 🎛️ Subcommands

```bash
/gbrain                          # default = check (full 19-layer dashboard)
/gbrain sync                     # 🔄 ORCHESTRATOR: monorepo pull → install → hermes migrate → SOUL.md guard → md5 verify
/gbrain verify                   # 🔬 LIE-DETECTOR: re-checa cada claim vs ground truth (25 claims)
/gbrain fix                      # auto-fix safe issues (embed, extract, integrity)
/gbrain news                     # solo upstream releases/PRs
/gbrain bugs                     # bugs upstream que TE afectan
/gbrain compare                  # diff vs snapshot anterior
/gbrain save                     # guarda reporte en ~/brain/reports/
/gbrain bootstrap                # verify stack canonical
/gbrain principles               # operational rules
/gbrain manifest                 # canonical inventory
/gbrain manual                   # full manual
/gbrain custom-instructions      # genera CI block para claude.ai
/gbrain compound run             # 7th-phase compounding cycle (LLM-driven)
/gbrain compound dry-run         # preview proposals sin aplicar
/gbrain compound status          # confidence per category
/gbrain compound history         # last 10 cycles
```

---

## 🌙 Bonus: 7th-phase compounding engine

The brain grows **while you sleep**. After each `gbrain dream` cycle, `gbrain compound` runs an LLM-driven analyzer that detects patterns, links concepts, surfaces orphans, and proposes structural improvements. Each proposal has a confidence score. You can `dry-run` first, `revert` any change, or let it apply autopilot. The brain compounds — every night it's a little smarter than yesterday.

---

## 🧪 Philosophy

```
🟢 Canonical wins              — one source of truth per concept, never duplicate
🟢 Lie-detector everything     — every claim must have a programmatic verifier
🟢 Never claim done on shape   — verify ground truth after every state change
🟢 Fail-closed                 — bridges and agents refuse rather than guess
🟢 No half-implementations     — if it works, ship; if not, revert
🟢 Defense in depth            — 5 layers between attacker and damage
🟢 Auto-restore canonical      — protected copies that any tool tries to overwrite get reverted
```

---

## 📦 Structure

```
skills/
├── claude/              # Skills for Claude Code CLI       (~/.claude/skills/)
├── openclaw/            # Skills for OpenClaw / Telegram   (~/.openclaw/skills/)
├── shared/              # Skills for both runtimes
│   ├── gbrain/          ← THIS skill (canonical orchestrator)
│   └── whatsapp/        ← dual-agent + SEGURIDAD BLINDADA
├── .githooks/
│   ├── pre-commit       # auto-classifies new skills
│   └── post-merge       # auto-runs install.sh after git pull
└── install.sh           # idempotent, deploys to all runtimes
```

---

## 🔀 How distribution works — and how it differs from `claude-skills`

**This monorepo is personal infrastructure.** Edit a skill once; it auto-deploys to every runtime on *your* machine.

How the deploy works:
1. Each `SKILL.md` declares `distribute-to: [claude]`, `[openclaw]`, or `[claude, openclaw]` (or it's inferred from the `claude/` · `openclaw/` · `shared/` folder).
2. `install.sh` **copies** each skill to its runtime dir: `[claude]` → `~/.claude/skills/`, `[openclaw]` → `~/.openclaw/skills/`.
3. A cron (`*/30`) runs `git pull && install.sh`, so a commit here lands in your live runtimes within 30 min. HERMES inherits OpenClaw skills via a separate `hermes claw migrate` step.

**Overwrite rules (important — this is what keeps things from clobbering each other):**
- `install.sh` runs **without `--prune`** → it only *copies* the monorepo's own skills. It **never deletes** skills it doesn't own, so anything you install from elsewhere (e.g. a client product) is left untouched.
- ⚠️ **On a name collision, the monorepo wins.** If a skill name exists *both* here and in another repo, the `*/30` cron will overwrite the locally-installed copy with the version from here. Keep skill names unique across repos to avoid surprises.

### `durang/skills` (this monorepo) vs `durang/claude-skills`

| | **`durang/skills`** (here) | **`durang/claude-skills`** |
|---|---|---|
| Purpose | **Personal** — all your skills, auto-deployed to your stack | **Client-facing product** — what you install for clients |
| Auto-installs | ✅ cron `*/30` → `~/.claude/skills` + `~/.openclaw/skills` | ❌ installed per-client, manually |
| Flagship | `gbrain` + infra/dev skills | `track` ([◠‿◠] Scan — project intelligence) |

They are **separate by design and never touch each other.** A skill that lives *only* in `claude-skills` (like `track`) is fully isolated: the monorepo cron never sees it, so you can develop it and ship it to clients without ever disturbing your personal stack.

---

## 🔗 Related repos

- 🧠 [garrytan/gbrain](https://github.com/garrytan/gbrain) — the underlying brain database + CLI (by Garry Tan, CEO of YC)
- 🛰️ [durang/gbrain-http-wrapper](https://github.com/durang/gbrain-http-wrapper) — OAuth 2.1 + PKCE wrapper extending GBrain to web/mobile/Desktop
- 💬 [durang/whatsapp-monitor](https://github.com/durang/whatsapp-monitor) — companion repo with bridge patches, contact templates, security-blindada block, sync scripts
- 📦 ~~[durang/gbrain-skill](https://github.com/durang/gbrain-skill)~~ — **ARCHIVED 2026-05-17** — content moved canonically to `shared/gbrain/` here

---

<div align="center">

**Built by [@durang](https://github.com/durang).** MIT licensed.

_If you build multi-agent stacks, this skill saves you from yourself._ 🧠

</div>
