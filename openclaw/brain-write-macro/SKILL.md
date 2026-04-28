---
name: brain-write-macro
description: "Explicit save macro — when user says 'guarda en gbrain' (and 23 phrase variants in ES/EN), automatically extract entities, decisions, originals, and links from the conversation and write them as gbrain pages. Companion to signal-detector (which captures passively per-message); brain-write-macro is the explicit user-triggered version that works in clients without hooks (Claude Desktop, claude.ai web, mobile)."
allowed-tools: Bash Read Write
user-invocable: false
companion-skills: signal-detector gbrain
custom-instructions-version: 2
custom-instructions-changelog: |
  v1 (2026-04-28 03:30): initial — phrase trigger, put_page, add_link, slug list confirm
  v2 (2026-04-28 05:42): added CHECK BEFORE WRITE (get_page+merge), explicit type frontmatter,
                          ASCII slug rules (no accents), trigger exclusions (file/Drive saves),
                          (new)/(enriched) markers in confirm output, error reporting on tool failure
upstream-status: |
  Not yet in gbrain core. As of 2026-04-28, gbrain has no native "save by phrase" mechanism — it has put_page (manual) + signal-detector skill (per-message ambient). This macro fills the gap for clients without hooks (Desktop/web/mobile).
  Auto-disable when: gbrain ships a `gbrain__save_conversation` tool OR a server-side phrase-trigger handler. Recheck via /gbrain Layer 11b which queries `gbrain --help` for those.
triggers:
  - guarda en gbrain
  - guarda esto en mi brain
  - guarda esto en gbrain
  - lo importante en mi brain
  - captura en gbrain
  - mete esto al brain
  - save to brain
  - save to gbrain
  - save this to brain
  - save this to gbrain
  - save the important things from this
  - guarda
distribute-to: [openclaw]
---

# /brain-write-macro — Explicit save by phrase (works on every client)

## Why this skill exists

**The capture gap:** GBrain has two automatic capture paths today:

1. **Claude Code CLI** → Stop hook (`~/.claude/settings.json` → `signal-detector.py`) fires at end of every turn, runs Haiku over the transcript, writes pages.
2. **Telegram (Harviz/OpenClaw)** → SOUL.md instructions tell the model to extract entities and call `gbrain__put_page` on every inbound message.

**But Claude Desktop, Claude.ai web, and Claude.ai mobile have NEITHER.** Anthropic does not expose hooks for those clients (verified 2026-04-28: [Claude Code hooks docs](https://code.claude.com/docs/en/hooks-guide) — hooks are CLI-only). The model only writes to gbrain if:
- The user pegs Custom Instructions in their claude.ai account telling it to, OR
- The user explicitly asks: "guarda esto en mi brain"

This skill defines the **canonical behavior** for the explicit-phrase trigger so agents anywhere (Telegram, mobile via Custom Instructions, future MCP clients) implement it identically.

## Trigger phrases (ES + EN)

Activate when user message matches any of these **EXACTLY or as a clear intent variation**:

| Spanish | English |
|---|---|
| `guarda en gbrain` | `save to brain` |
| `guarda esto en mi brain` | `save this to brain` |
| `guarda esto en gbrain` | `save this to gbrain` |
| `lo importante en mi brain` | `save the important things` |
| `captura en gbrain` | `capture to gbrain` |
| `mete esto al brain` | `dump this in the brain` |
| `guarda` (after substantive turn) | `save` (after substantive turn) |

**Pattern matching rule:** any natural-language combination of the verbs `guardar/save/capture/store/dump` + `gbrain/brain/memory` triggers the macro. Don't require exact match — match by intent.

## Behavior (canonical procedure — copy-paste this into any agent's system prompt)

**Execute this exact sequence WITHOUT asking the user for details. Infer everything from the conversation.**

### When NOT to trigger

- File/document save commands: "guarda este archivo", "save the file", "save the doc", "guarda en Drive", "guarda en Notion". Brain capture only.
- Operational noise: pure "ok", "sí", "thanks", "/status".

### Procedure

**Step 1 — SCAN this entire conversation (every turn) for:**
- **People named WITH attributes** (role, company, location, age, contact, notable detail). **Skip name-only mentions** like "I told John" with no other detail.
- **Companies/funds/startups WITH attributes** (industry, stage, founders, location).
- **Decisions** the user took or stated ("vamos con X", "decidí Y", "let's go with Z", "no, mejor W", "descartamos…", "elegí…").
- **Originals** — original ideas, theses, or strategic insights the user framed (not generic Q&A — only the user's own framings). Preserve their **exact phrasing** in compiled_truth.

**Step 2 — SLUG RULES (always):**
- Always kebab-case, lowercase, ASCII only. **NO accents:** `sergio-duran`, NOT `sergio-durán`.
- Format:
  - `people/firstname-lastname`
  - `companies/<name>`
  - `decisions/<short-summary>`
  - `originals/<short-kebab>`

**Step 3 — CHECK BEFORE WRITE (avoid duplicates) — DO NOT SKIP:**
- Before each `gbrain__put_page`, call `gbrain__get_page` with `fuzzy: true` on the slug.
- If the page exists: READ its current `compiled_truth`, then call `gbrain__put_page` with the **merged content** (existing + new attributes from this conversation).
- If not found: write fresh.

**Step 4 — WRITE PAGES with required frontmatter:**
- `gbrain__put_page slug:"people/<...>"      type:"person"     title:"<Full Name>"`
- `gbrain__put_page slug:"companies/<...>"   type:"company"    title:"<Company Name>"`
- `gbrain__put_page slug:"decisions/<...>"   type:"decision"   title:"<one-line summary>"`
- `gbrain__put_page slug:"originals/<...>"   type:"original"   title:"<short header>"`

**Step 5 — CREATE LINKS for cross-references with `gbrain__add_link`:**
- Person works at Company → `from:"people/x" to:"companies/y" type:"works_at"`
- Person co-founded Company → `type:"founded"`
- Fund invested in Company → `type:"invested_in"`
- Person met with Person → `type:"met_with"`
- Person advised Person → `type:"advised"`
- Person collaborates with Person → `type:"collaborates_with"`

**Step 6 — CONFIRM with the actual slugs you wrote AFTER all tool calls succeed:**

```
✅ Guardado en gbrain:
- people/mike-shapiro (new)
- people/jason-X (enriched)
- companies/elafris (new)
- companies/digital-kozak-llc (new)
- decisions/proposed-pool-split-33-30-30-10 (new)
- originals/insurance-vertical-thesis (new)
- 4 links: mike→elafris (founded), mike→digital-kozak (founded), jason→pool-split (proposed), ...
```

The `(new)` / `(enriched)` markers come from Step 3: if `get_page` returned a page, it's `enriched`; if not found, it's `new`.

## CRITICAL RULES — anti-hallucination

1. **NEVER respond "guardado" / "saved" / "listo" / "done" without listing actual slugs** you called `put_page` on. That is hallucination. If you didn't call the tool, don't claim you did.
2. **NEVER ask "qué quieres que guarde?" / "what should I save?".** Infer from the conversation. Better to write 8 pages and let the user prune than to write 0 and ask.
3. **If a `put_page` or `add_link` call returns an error, report it explicitly:**
   ```
   ❌ Failed: people/mike-shapiro — error: <exact error message>
   ```
   Do NOT pretend it worked. Do NOT silently retry without telling the user.
4. **For `originals` (the user's ideas), preserve exact phrasing in compiled_truth, not paraphrase.** Voice matters. The user uses gbrain to retrieve their own words later, not your summary of their words.
5. **One reply at the end with the slug list.** No commentary mid-process. No "let me check..." messages between tool calls.
6. **NEVER write pages with no attributes.** A `people/john` with empty body is just noise. Skip name-only mentions entirely.

## Verifying capture (debug for the user)

If user later asks "¿se guardó?" / "did it save?":
1. Run `gbrain__search` with the most distinctive entity name.
2. Or `gbrain__get_page` on the slug you reported.
3. Show first 100 chars of compiled_truth as proof.

If the page does NOT exist: the previous capture failed silently. Apologize and retry.

## Where this skill is referenced

- `~/SOUL.md` Iron Rules section — references this skill by name
- `~/.openclaw/skills/gbrain/run.sh` Layer 11b — detects if this skill is installed + checks upstream gbrain for native replacement
- `~/.openclaw/skills/RESOLVER.md` (or AGENTS.md routing) — routes user phrase intents here

## Auto-deprecation conditions

Disable this skill (move to `archive/`) when ANY of these become true:

1. **gbrain CLI ships a `gbrain save-conversation` command** that does this server-side.
2. **gbrain MCP server adds a `save_conversation` tool** that the model can discover and call.
3. **gbrain integrations registry adds a built-in `phrase-trigger` recipe** that supersedes this skill.

The `/gbrain` Layer 11b runs `gbrain --help | grep -iE "save-conv|save_conversation|phrase-trigger"` weekly — if it finds anything, it suggests deprecating this skill.

## Upstream contribution path (TODO)

Convert this to a gbrain recipe (similar to PR #481 `claude-code-capture`):

```
recipes/brain-write-macro.md       # the recipe (frontmatter + install instructions)
recipes/brain-write-macro/
  install.sh                        # writes Custom Instructions snippet + SOUL.md ref
  brain-write-macro.json            # pattern-matched phrases, agent-agnostic
```

When ready, open PR `durang/gbrain-pr-claude-code-capture:add-brain-write-macro` → `garrytan/gbrain:master`.

## See also

- `~/.openclaw/skills/signal-detector/SKILL.md` — passive per-message capture (CLI + Telegram)
- `~/.openclaw/skills/gbrain/SKILL.md` — health dashboard that monitors this skill's effectiveness
- `~/gbrain-http-wrapper/` — HTTP wrapper for Desktop/web/mobile (this skill must work for those clients)
- Custom Instructions block at https://claude.ai → Settings → Profile (the actual injection point for non-CLI clients)
