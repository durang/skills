# skills — durang's canonical skills monorepo

> **Canonical source of truth** for my Claude Code + OpenClaw + HERMES skills.
> One repo, one install, orchestrated by `/gbrain sync`.
>
> Companion to [gbrain-http-wrapper](https://github.com/durang/gbrain-http-wrapper)
> and [whatsapp-monitor](https://github.com/durang/whatsapp-monitor).
>
> _Note: [gbrain-skill](https://github.com/durang/gbrain-skill) was archived 2026-05-17 — its content lives in `shared/gbrain/` here._

## Highlight skills

| Skill | Purpose | Trigger |
|-------|---------|---------|
| **[gbrain](shared/gbrain/)** | Canonical health dashboard + orchestrator. 19 layers + Layer 19 AWS Infra + `/gbrain sync` updates everything. | `/gbrain`, `/gbrain sync`, `/gbrain verify` |
| **[whatsapp](shared/whatsapp/)** | WhatsApp dual-agent dashboard (OpenClaw + Hermes), default-deny security, SEGURIDAD BLINDADA. | `/whatsapp` |
| **[openclawtrack](claude/openclawtrack/)** | OpenClaw full infrastructure scan + visual dashboard | `/openclawtrack` |
| **[hermestrack](claude/hermestrack/)** | HERMES agent dashboard + skills + cron + sessions | `/hermestrack` |
| **[openclaw-security](claude/openclaw-security/)** | Security hardening checklist for EC2 OpenClaw installs | `/openclaw-security` |
| **[openclawcontinue](claude/openclawcontinue/)** | OpenClaw optimizer — actionable improvements with priority | `/openclawcontinue` |

## `/gbrain` — 19 main layers + 6 sub-layers (25 sections)

`/gbrain check` renders a markdown dashboard. Every layer is auto-verified by `/gbrain verify` (lie-detector). Drift in any → red alert banner.

| # | Layer | Mide |
|---|-------|------|
| 🚨 | Alert banner | stuck sessions, missing API keys, no model fallbacks, queue >100, public TLS desync, AWS drift, SOUL.md drift |
| 1 | Versiones | GBrain + OpenClaw vs latest published |
| 2 | Runtime | Gateway, Telegram conns, npm loops, model + fallbacks, MCP, SOUL.md directive |
| 3 | Doctor | `gbrain doctor --json` structured |
| 3b | Schema correlation | DB tables ↔ wrapper ↔ skills (detecta migration drift silencioso) |
| 4 | Stats | pages, chunks, embedded, links, timeline, tags |
| 5 | Skills (OpenClaw) | signal-detector, brain-ops, etc. |
| 5b | HERMES integration | parallel runtime, skills, MCP link, bot conflict detection |
| 6 | Capture 24h | pages/links/timeline + `gbrain__` MCP calls |
| 7 | Bugs upstream | cross-reference tu versión vs known issues |
| 8 | News | últimas releases + PRs + issues |
| 9 | Snapshot diff | stats delta vs snapshot anterior |
| 10 | Archivos canónicos | SOUL.md / MEMORY.md / openclaw.json mtime |
| 11 | MCP Health | servers registrados + binarios en disco |
| 11b | Wrappers + Integrations | HTTP wrapper, recipes, OAuth clients, source coverage |
| 12 | Stuck sessions | 1h rolling count |
| 13 | Process env audit | `*_API_KEY` count en openclaw-node |
| 14 | Cron failure rate | 24h jobs-state.json |
| 14b | System crontab canonical | MANIFEST.json declarados vs crontab real |
| 15 | Upstream changelog | últimos 15 commits ✅ instalado / 🔜 pendiente |
| 16 | Upgrade Decision Engine | INSTALAR / ESPERAR / SKIP por tool |
| 17 | Upstream Features Watch | features nuevas, try-it commands |
| 17b | Skill propagation | satellite skills propagation hints |
| 18 | MCP clients + custom instructions | ¿clientes tienen reglas v3+? |
| 18b | Cross-runtime active model | live read OpenClaw / HERMES / Codex CLI |
| **19** | **AWS Infra Health** (NEW 2026-05-15) | **CloudTrail, GuardDuty, Budget, DLM, SG, EBS, IMDSv2, root keys, sergio-admin MFA, root MFA, SOUL.md canonical guard, GBrain stack page** |

## `/gbrain` subcommands

```bash
/gbrain                          # default = check (dashboard 19 layers)
/gbrain sync                     # 🔄 orquestador: monorepo pull → install → hermes migrate → SOUL.md auto-restore → md5 verify
/gbrain verify                   # 🔬 lie-detector — re-checa cada claim vs ground truth (25 claims)
/gbrain fix                      # auto-fix safe issues (embed --stale, extract, integrity, migrations)
/gbrain news                     # solo upstream releases/PRs/issues
/gbrain bugs                     # bugs upstream que TE afectan
/gbrain compare                  # diff vs snapshot anterior
/gbrain save                     # guarda reporte en ~/brain/reports/gbrain-YYYY-MM-DD.md
/gbrain bootstrap                # verifica entire stack canonical
/gbrain principles               # operational rules
/gbrain manifest                 # canonical inventory
/gbrain manual                   # full manual con casos de uso
/gbrain custom-instructions      # genera bloque CI para claude.ai
/gbrain compound run             # 7th-phase compounding cycle (LLM-driven)
/gbrain compound dry-run         # preview proposals
/gbrain compound status          # confidence per category
/gbrain compound history         # last 10 cycles
```

## Structure

```
skills/
├── claude/              # Skills for Claude Code CLI (~/.claude/skills/)
├── openclaw/            # Skills for OpenClaw / Harviz Telegram (~/.openclaw/skills/)
├── shared/              # Skills for both (installed to both directories)
├── .githooks/
│   ├── pre-commit       # Auto-classifies new skills, asks only when ambiguous
│   └── post-merge       # Auto-runs install.sh after git pull
└── install.sh           # Idempotent. Copies repo → target dirs based on frontmatter
```

## Day-to-day workflow

### Create a new skill

```bash
cd ~/skills
mkdir -p claude/my-new-skill
vim claude/my-new-skill/SKILL.md       # write the skill
git add . && git commit -m "Add my-new-skill"
# Hook: subdir already says claude/ → no question, auto-tagged distribute-to: [claude]
git push                                # share to repo + Mac
./install.sh                            # apply locally (also runs auto via post-merge on pull)
```

### Sync to a new machine (Mac, fresh EC2, etc.)

```bash
git clone git@github.com:durang/skills.git ~/skills
cd ~/skills
./install.sh                            # idempotent — fills ~/.claude/skills/ and ~/.openclaw/skills/
```

That's it. 5 minutes from zero to a fully populated skills system.

## Auto-classification rules (so the hook doesn't ask)

| Where you put the skill | distribute-to applied |
|---|---|
| `claude/<name>/` | `[claude]` |
| `openclaw/<name>/` | `[openclaw]` |
| `shared/<name>/` | `[claude, openclaw]` |
| Root level + name starts with `gsap-`, `mcp-`, `claude-` | `[claude]` |
| Root level + name starts with `brain-`, `signal-`, `*-detector`, `*-ingest` | `[openclaw]` |
| Root level + ambiguous | hook asks `[c/o/b/s]`, default = sensible guess from history |

## Scripts

| Command | What it does |
|---|---|
| `./install.sh` | Apply current state — copy skills to local dirs (idempotent) |
| `./install.sh --interactive` | Tag any orphan skills (no `distribute-to:` set) |
| `./install.sh --prune` | Remove skills from local dirs that were deleted from the repo |
| `./install.sh --dry-run` | Show what would happen without applying |

## Current inventory

| Track | Skills |
|---|---|
| `claude/` (12) | gsap-core, gsap-frameworks, gsap-performance, gsap-plugins, gsap-react, gsap-scrolltrigger, gsap-timeline, gsap-utils, mmx-cli, openclaw-security, openclawcontinue, openclawtrack |
| `openclaw/` (2) | brain-write-macro, signal-detector |
| `shared/` (1) | gbrain (canonical health dashboard + 7th-phase compounding engine) |

`shared/gbrain/` mirrors the standalone [gbrain-skill](https://github.com/durang/gbrain-skill) repo — same `run.sh`, `compound/`, `MANIFEST.json`, `MANUAL.md`, `PRINCIPLES.md`, `bootstrap.sh`. The standalone repo carries extra docs (ARCHITECTURE.md, CAPTURE.md, INSTALL.md, PHASE_4_GUIDE.md, etc.) intended for outside users; this monorepo carries the operational core that gets deployed to `~/.openclaw/skills/gbrain/`.

## Audit

Run `/gbrain bootstrap` (from the [gbrain-skill](https://github.com/durang/gbrain-skill))
to see if your local skills match the repo. If they don't, you'll see a clear diff with
suggested fix command.

## License

MIT.
