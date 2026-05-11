---
name: brain-write-macro
description: "Explicit save macro — when user says 'guarda en gbrain' (and 23 phrase variants in ES/EN), automatically extract entities, decisions, originals, and links from the conversation and write them as gbrain pages. Companion to signal-detector (which captures passively per-message); brain-write-macro is the explicit user-triggered version that works in clients without hooks (Claude Desktop, claude.ai web, mobile)."
allowed-tools: Bash Read Write
user-invocable: false
companion-skills: signal-detector gbrain
custom-instructions-version: 4.1
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
  v4 (2026-05-11 01:50): R5 SEARCH side rule made PREFLIGHT and BROAD — fires on bare "busca"
                          (not only "busca en gbrain"), on recall verbs ("qué tenía sobre X",
                          "recuérdame Y"), and on implicit references to user's own data.
  v4.1 (2026-05-11 02:00): R5 phrasing restored to Sergio's elegant pre-v4 catch-all
                            "or asks about past conversations / people / companies / decisions /
                            projects / tasks" — covers same breadth as v4 in 1 line vs 3 sections.
                            ChatGPT snippet hybrid: keeps tight pre-v4 structure + adds R3 task,
                            R4 proactive, SKIP rule, full link types. ~1450 chars (vs 1100 pre-v4
                            and 1800 v4-fragmented).
                          R3 task-type added (slug `tasks/<short>`, frontmatter status:
                          pending|in_progress|done|blocked, optional priority/estimated_hours/due_date).
                          R4 PROACTIVE detection without explicit phrase trigger — when model
                          detects future project, actionable task, decision, or recurring entity
                          WITH NEW substantive attributes, offer ONE LINE: "Detecté X. ¿Guardo
                          como <type>/<slug>?" and wait for yes/no. Never auto-write proactively.
                          Tasks vs daily-task-manager: tasks/ = captura/pendientes futuros; cuando
                          se atacan, promover al daily-task-manager flow. Done tasks stay with
                          timestamp, not auto-archived.
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

**But Claude Desktop, Claude.ai web, ChatGPT, and Codex CLI have NO automatic hooks.** The model only writes to gbrain if:
- The user pastes Custom Instructions telling it to, OR
- The user explicitly says: "guarda en gbrain"

This skill defines the **canonical behavior** for the explicit-phrase trigger so all clients implement it identically.

### Client delivery map (where instructions live per client)

| Client | How rules are delivered | Format |
|---|---|---|
| **Claude Code CLI** | Stop hook (signal-detector.py) — automatic | Full v3 (embedded in Haiku prompt) |
| **claude.ai web/app** | Settings → Profile → Custom Instructions | Full v3 (via `/gbrain custom-instructions`) |
| **ChatGPT App** | Settings → Personalización → Custom Instructions | Compact v3 (~780 chars, trigger: "guarda en gbrain") |
| **Codex CLI** | `~/AGENTS.md` (gbrain section) | Full v3 (read automatically) |
| **OpenClaw / Telegram** | SOUL.md + this skill loaded as skill | Full v3 (model reads SKILL.md) |
| **Hermes** | Inherited via `hermes claw migrate` | Full v3 (imported skill) |
| **Cron** (compound/dream) | Direct CLI calls | N/A (writes via gbrain CLI) |

### R2 source-tracking channels (valid values)

`claude-code-stop-hook`, `claude-ai-web`, `codex-cli`, `chatgpt-app`, `openclaw`, `hermes`, `cron-compound`, `cron-dream`

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

### When NOT to trigger (save side)

- File/document save commands: "guarda este archivo", "save the file", "save the doc", "guarda en Drive", "guarda en Notion". Brain capture only.
- Operational noise: pure "ok", "sí", "thanks", "/status".

### R5 SEARCH side rule (v4.1 — PREFLIGHT, runs BEFORE everything else, all clients)

**This is a PREFLIGHT rule. Apply BEFORE thinking, BEFORE answering, BEFORE save side.**

**Canonical phrasing (use this exact wording in client snippets — proven elegance + breadth):**

> When user says "busca", "busca en gbrain", "busca en mi brain", "search gbrain", "search my brain", **or asks about past conversations / people / companies / decisions / projects / tasks** — ALWAYS call `gbrain__search` (or `gbrain__query` for hybrid) FIRST. Never answer from model memory alone.

The **"or asks about past..."** clause is the catch-all that covers implicit references like "¿quién es X?", "qué decidí sobre Y", "recuérdame Z", "qué pasó con W", "what did we agree on" — any question whose answer lives in the user's personal data.

**When in doubt: search first.** The cost of an unnecessary `gbrain__search` call is tiny. The cost of answering from model memory and being wrong is high.

If gbrain returns empty, say so explicitly: *"No encontré nada en gbrain sobre X. ¿Lo guardamos?"* — don't invent. Optionally connect to R4 proactive detection by offering to create the page.

**Why this phrasing**: Sergio's pre-v4 ChatGPT snippet already had this catch-all working well. v4 initially fragmented it into 3 verbose categories which lost elegance and char budget without adding coverage. v4.1 restores the elegant phrasing while keeping the PREFLIGHT positioning + the "when in doubt, search" tiebreaker.

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
- `gbrain__put_page slug:"tasks/<...>"       type:"task"       title:"<one-line action>"`
  - **R3 task frontmatter** (v4): `status: pending|in_progress|done|blocked`, optional `priority: low|medium|high`, `estimated_hours`, `due_date: YYYY-MM-DD`.
  - **Lifecycle**: `tasks/` = captura inicial / pendientes futuros. Cuando el usuario los ataca activamente, se promueven al flujo del skill `daily-task-manager`. Done tasks quedan con timestamp; no auto-archivadas.
  - **vs daily-task-manager**: ese skill es el flujo diario activo. `tasks/<slug>` aquí es el punto de entrada — captura primero, ataca después.

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

## R4 PROACTIVE detection (v4 — without explicit phrase trigger)

When the user is NOT explicitly saying "guarda", but the conversation contains a substantive signal, **offer ONE LINE** to the user:

| Pattern | Trigger | Offer |
|---|---|---|
| **A — future project** | "quiero hacer X eventualmente", "deberíamos armar Y", "no urge pero algún día Z", "estaría bueno construir W" | *"Detecté un proyecto. ¿Lo guardo como `projects/<slug>`?"* |
| **B — actionable task** | "tengo que hacer X", "no olvidar Y", "pendiente: Z", "luego hago W" | *"Detecté una tarea. ¿Lo guardo como `tasks/<slug>`?"* |
| **C — decision** | "decidí X", "vamos con Y", "mejor Z que W", "descartamos V" | *"Detecté una decisión. ¿Lo guardo como `decisions/<slug>`?"* |
| **D — recurring entity** | Same person/company in 3+ turns AND with at least ONE NEW substantive attribute (role, company, location, event, decision) — NOT casual mention repetition | *"Estamos hablando bastante de X. ¿Guardo página con lo nuevo?"* |

**Behavior rules**:
- Show ONE LINE only. Wait for yes/no.
- NEVER auto-write proactively. Always confirm.
- If user says yes, run the full Procedure (Step 1-6) for that ONE detected item.
- If user ignores the offer (doesn't reply to it), don't repeat. Don't bug.
- Apply quality filter: pattern D requires NEW substantive attribute, not just repetition. "Mi mamá llamó / mi mamá cocinó / mi mamá vino" without new info → don't offer.

**Why proactive instead of fully automatic**: silent auto-writes from a partial-context client (claude.ai web, ChatGPT) are how garbage gets into the brain. The user is the only authority on what's worth keeping. The 1-line offer is cheap; the user prunes by replying yes/no.

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

## Ownership map — who owns what for custom instructions

This is the canonical answer to "where do the Claude.ai custom instructions live?":

| Component | Role | File |
|---|---|---|
| **`brain-write-macro`** (this skill) | **SOURCE OF TRUTH** for the rules. Frontmatter `custom-instructions-version` is the spec version. The Procedure section IS the custom instructions content. When you bump the version here, every other component below must update or it goes out of sync. | `~/skills/openclaw/brain-write-macro/SKILL.md` |
| **`signal-detector`** (sister skill) | Mirrors the same rules for the per-message Stop hook (Claude Code CLI). Phases 2.5/2.6/2.7 align 1:1 with brain-write-macro Steps 3.5/4.5 + rule 7. | `~/skills/openclaw/signal-detector/SKILL.md` |
| **`gbrain` skill** (`run.sh`) | EMITS the snippet via `/gbrain custom-instructions [--adaptive]`. Reads spec version from THIS file's frontmatter. `--adaptive` injects live page/link types from the brain DB. | `~/skills/shared/gbrain/run.sh` (subcommand `custom-instructions`) |
| **`gbrain-http-wrapper`** | SERVES the snippet over HTTP at `/.well-known/mcp/custom-instructions` for clients that can't run a CLI (claude.ai web/app). Same content, JSON-wrapped, served from `https://<wrapper-url>/mcp/.well-known/mcp/custom-instructions`. | `~/gbrain-http-wrapper/src/server.ts` |
| **`/gbrain custom-instructions-applied.flag`** | Tracks which version the user has actually pasted into claude.ai → Profile. Layer 18 in `/gbrain check` compares spec vs applied and flags out-of-sync. | `~/.gbrain/custom-instructions-applied.flag` |
| **Layer 18 in `/gbrain check`** | Visualizes all 4 clients (Claude Code CLI, OpenClaw/Telegram, HERMES, Claude.ai web) and which ones are at the current spec version. | `~/skills/shared/gbrain/run.sh` (Layer 18 block) |

**To bump the spec (e.g. v3 → v4):**
1. Edit this file's `custom-instructions-version` frontmatter and changelog.
2. Edit the snippet inside `~/skills/shared/gbrain/run.sh` (subcommand `custom-instructions`, the `cat <<'EOF' ... EOF` block).
3. Edit the snippet inside `~/gbrain-http-wrapper/src/server.ts` (the `/.well-known/mcp/custom-instructions` handler).
4. Edit `signal-detector/SKILL.md` if the change affects per-message capture.
5. `cd ~/skills && bash install.sh` propagates skills to install dirs.
6. `sudo systemctl restart gbrain-http-wrapper.service` reloads the HTTP endpoint.
7. `hermes claw migrate --overwrite --yes --skill-conflict overwrite` for HERMES.
8. User pastes new snippet in claude.ai; `echo <new-version> > ~/.gbrain/custom-instructions-applied.flag`.
9. `/gbrain check` Layer 18 should show all 4 ✅ and `/gbrain integrate claude.ai` should show "in sync".

The reason `brain-write-macro` is the source of truth (and not, say, `gbrain` skill): this skill is the one that DEFINES what counts as a write to gbrain. The other skills SERVE or DISTRIBUTE the rules — they should always read from here, never define their own version.

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
