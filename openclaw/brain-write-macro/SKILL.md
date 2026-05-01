---
name: brain-write-macro
description: "Explicit save macro — when user says 'guarda en gbrain' (and 23 phrase variants in ES/EN), automatically extract entities, decisions, originals, and links from the conversation and write them as gbrain pages. Companion to signal-detector (which captures passively per-message); brain-write-macro is the explicit user-triggered version that works in clients without hooks (Claude Desktop, claude.ai web, mobile)."
allowed-tools: Bash Read Write
user-invocable: false
companion-skills: signal-detector gbrain
custom-instructions-version: 3
custom-instructions-changelog: |
  v1 (2026-04-28 03:30): initial — phrase trigger, put_page, add_link, slug list confirm
  v2 (2026-04-28 05:42): added CHECK BEFORE WRITE (get_page+merge), explicit type frontmatter,
                          ASCII slug rules (no accents), trigger exclusions (file/Drive saves),
                          (new)/(enriched) markers in confirm output, error reporting on tool failure
  v3 (2026-05-01 22:00): R1 conflict-flag (no overwrite when get_page returns contradicting field —
                          append "## Posible contradicción" block instead),
                          R2 source-tracking (frontmatter `sources: [{date, channel, session_id}]`
                          replaces the old "merged-from-chatbot" tag pattern),
                          extended page types (concept, project, recipe, source) and link types
                          (owns, collaborates_with, superseded_by, mentioned_in, subject_of,
                          negotiating, advises) — to be hydrated dynamically from gbrain via
                          `/gbrain custom-instructions --adaptive`,
                          meta-content guard (rule 7) — never write a page whose body describes
                          the conversation rather than the entity.
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

**Step 3.5 — R1 CONFLICT FLAG (NO overwrite on contradiction):**
- If a field in the existing page (status, role, company, location, dates, amounts) **contradicts** the new value from this conversation, do NOT overwrite. Instead, append a block at the end of the page:
  ```
  ## Posible contradicción (YYYY-MM-DD)
  - **Field**: <field name, e.g. "status">
  - **Valor anterior**: <old value>
  - **Valor nuevo**: <new value>
  - **Source**: <channel, e.g. "claude.ai web session">
  - **Acción**: verificar con Sergio
  ```
- Reason: silent overwrite from a partial-context client (claude.ai web, chatbot) is the same class of bug as truncating data — the user must arbitrate.
- Confirm output marks these as `(conflict-flagged)` instead of `(enriched)`.

**Step 4 — WRITE PAGES with required frontmatter:**
- `gbrain__put_page slug:"people/<...>"      type:"person"     title:"<Full Name>"`
- `gbrain__put_page slug:"companies/<...>"   type:"company"    title:"<Company Name>"`
- `gbrain__put_page slug:"decisions/<...>"   type:"decision"   title:"<one-line summary>"`
- `gbrain__put_page slug:"originals/<...>"   type:"original"   title:"<short header>"`
- `gbrain__put_page slug:"projects/<...>"    type:"project"    title:"<Project Name>"`
- `gbrain__put_page slug:"concepts/<...>"    type:"concept"    title:"<Concept Header>"`
- `gbrain__put_page slug:"recipes/<...>"     type:"recipe"     title:"<Recipe Header>"`

**Step 4.5 — R2 SOURCE TRACKING (every put_page includes provenance):**
- Add to frontmatter (append to array if exists, do not replace):
  ```yaml
  sources:
    - date: YYYY-MM-DD
      channel: claude-ai-web | claude-code | telegram | hermes | openclaw
      session_id: <opaque short id>
  ```
- Reason: when a page is wrong, you need to know which client wrote it so you can fix the upstream client. Tags like `merged-from-chatbot` are unstructured and not queryable.

**Step 5 — CREATE LINKS for cross-references with `gbrain__add_link`:**
- Person works at Company → `from:"people/x" to:"companies/y" type:"works_at"`
- Person co-founded Company → `type:"founded"`
- Fund invested in Company → `type:"invested_in"`
- Person met with Person → `type:"met_with"`
- Person advised Person → `type:"advised"`
- Person collaborates with Person → `type:"collaborates_with"`
- Company owns Company → `type:"owns"`
- Person/Company subject_of Decision/Project → `type:"subject_of"`
- Page mentioned_in Source → `type:"mentioned_in"`
- Page A superseded_by Page B (rename/consolidation) → `type:"superseded_by"`
- Person negotiating with Person/Company → `type:"negotiating"`
- Person advises Company → `type:"advises"`

**NOTE:** This list is the static fallback. The canonical, brain-aware list comes from `gbrain custom-instructions --adaptive` which queries the live page/link types from your brain and injects them into the snippet. Use that whenever possible.

**Step 6 — CONFIRM with the actual slugs you wrote AFTER all tool calls succeed:**

```
✅ Guardado en gbrain:
- people/mike-shapiro (new)
- people/jason-prescott (enriched)
- people/sarah-chen (conflict-flagged: status "advisor" vs "investor")
- companies/elafris (new)
- companies/digital-kozak-llc (new)
- decisions/proposed-pool-split-33-30-30-10 (new)
- originals/insurance-vertical-thesis (new)
- 4 links: mike→elafris (founded), mike→digital-kozak (founded), jason→pool-split (proposed), ...
```

Markers come from Step 3 / Step 3.5:
- `(new)` — `get_page` returned 404, page written fresh
- `(enriched)` — `get_page` found existing page, content merged
- `(conflict-flagged)` — `get_page` found existing page with a field that contradicts the new value; "Posible contradicción" block appended; user must verify

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
7. **NEVER write meta-content as if it were the entity.** A page `people/jason-prescott` whose body is "User initiated export request..." is wrong — the body is a description of the conversation, not the person. If you don't have substantive attributes about the entity, **don't write the page**. This rule was added 2026-05-01 after a claude.ai web session created 3 such meta-pages in one turn.
8. **NEVER overwrite a contradicting field silently** (R1). Always flag with the contradiction block. The user is the only authority that can resolve facts.

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
