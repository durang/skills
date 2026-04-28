# skills — durang's canonical skills monorepo

> One source of truth for my Claude Code + OpenClaw skills.
> Auto-classified, sync via git, integrated to `/gbrain` dashboard.
> Companion to [gbrain-http-wrapper](https://github.com/durang/gbrain-http-wrapper),
> [gbrain-skill](https://github.com/durang/gbrain-skill),
> [brain-write-macro](https://github.com/durang/brain-write-macro).

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

## Audit

Run `/gbrain bootstrap` (from the [gbrain-skill](https://github.com/durang/gbrain-skill))
to see if your local skills match the repo. If they don't, you'll see a clear diff with
suggested fix command.

## License

MIT.
