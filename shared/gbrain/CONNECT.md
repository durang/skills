# Connecting Multiple Clients to One GBrain

Practical reference for sharing one brain across multiple AI clients (Claude Code, Cursor, Windsurf, Claude Desktop, claude.ai web, mobile). Verified against `gbrain` v0.50.5.0 with Supabase Postgres engine (last live check 2026-09-28: 8 clients, 30,562 pages).

## TL;DR

- **Local stdio clients** (Claude Code, Cursor, Windsurf, anything that supports MCP stdio): all share the same brain automatically by pointing each install of `gbrain` at the same Supabase `database_url`. ✅ Works today.
- **Remote HTTP clients** (Claude Desktop, claude.ai web Cowork, mobile, Perplexity): require an HTTP wrapper around `gbrain serve`. ❌ Not in the binary today — `gbrain serve --http` is documented as *"planned but not yet implemented"* in [docs/mcp/DEPLOY.md](https://github.com/garrytan/gbrain/blob/main/docs/mcp/DEPLOY.md).

## Compatibility matrix

| Client | Runs on | Transport | Estado | Cómo |
|---|---|---|---|---|
| Claude Code (CLI) | máquina local | stdio | ✅ en producción | `claude mcp add gbrain -- gbrain serve` |
| Cursor | Mac/PC | **HTTP + Bearer** | ✅ en producción | `~/.cursor/mcp.json` con `url` + header `Authorization: Bearer <token>` |
| Cursor (alternativa) | máquina local | stdio | ✅ | entrada MCP apuntando a `gbrain serve` |
| Claude.ai web / app | servidores Anthropic | HTTP + OAuth 2.1 | ✅ en producción | wrapper + DCR (registro dinámico) |
| ChatGPT app | servidores OpenAI | HTTP + OAuth 2.1 | ✅ en producción | wrapper + OAuth |
| Codex CLI | local + Mac | HTTP + Bearer | ✅ en producción | token estático |
| **Grok** (grok.com) | servidores xAI | **HTTP + OAuth 2.1** | ✅ en producción | grok.com/connectors → Custom. **Ver la trampa de redirect_uri abajo** |
| OpenClaw / Telegram | EC2 | stdio | ✅ en producción | MCP registrado + SOUL.md |
| Hermes | EC2 | stdio | ✅ en producción | `hermes claw migrate` importa el skill |

## How shared brain works (architecture)

```
                    ┌──────────────────────┐
                    │   Supabase Postgres  │  ◄── the brain (single source of truth)
                    │   (or PGLite file)   │
                    └──────────┬───────────┘
                               │ same database_url
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
   gbrain serve            gbrain serve           gbrain serve
   (on Mac)                (on EC2)               (on laptop)
        │                      │                      │
        ▼                      ▼                      ▼
   Claude Code             Claude Code            Cursor / etc.
```

Each client runs its own local `gbrain serve` (stdio). They all read/write the same Postgres backend — so a page written from EC2 is immediately visible from Mac and vice versa.

## Connect a new local stdio client (canonical 4-step recipe)

This is the official path documented in [docs/mcp/CLAUDE_CODE.md](https://github.com/garrytan/gbrain/blob/main/docs/mcp/CLAUDE_CODE.md) Option 1, applied to multi-machine setups.

### 1. Install GBrain on the new machine

```bash
# requires Bun
curl -fsSL https://bun.sh/install | bash
bun install -g gbrain
gbrain --version  # should print 0.21.0+
```

### 2. Point it at the same Postgres as your other machines

If your "primary" machine has `~/.gbrain/config.json` with `engine: postgres` and a `database_url` to Supabase, copy the same `database_url` into the new machine's `~/.gbrain/config.json`:

```json
{
  "engine": "postgres",
  "database_url": "postgresql://...your-pooler-url..."
}
```

Permissions: `chmod 600 ~/.gbrain/config.json` (the URL contains the DB password).

### 3. Verify the connection

```bash
gbrain doctor --fast    # should show pgvector OK + same schema_version
gbrain list -n 3        # should show pages already created from your other machine
```

If `doctor` and `list` work and show the same data as the primary machine → the cerebro is shared.

### 4. Wire the MCP client

```bash
# Claude Code:
claude mcp add gbrain -- gbrain serve
claude mcp list   # confirms gbrain is registered + connected
```

For other stdio clients (Cursor, Windsurf), add this entry in their MCP config:

```json
{
  "mcpServers": {
    "gbrain": {
      "command": "gbrain",
      "args": ["serve"]
    }
  }
}
```

## Clientes HTTP — el wrapper ya está en producción

`gbrain-http-wrapper` (Bun + Hono, puerto 8787) es un front-end HTTP sobre el `gbrain serve`
de stdio. Publicado con Tailscale Funnel. Soporta **dos rutas de auth sobre la misma tabla
`access_tokens`**:

### Ruta 1 — Bearer estático (Cursor, Codex, scripts)

```bash
gbrain auth create "cursor"     # imprime gbrain_<64-hex> UNA sola vez
gbrain auth revoke "cursor"     # revocar
```

Cursor — `~/.cursor/mcp.json`:

```json
{ "mcpServers": { "gbrain": {
    "url": "https://<tu-host>.ts.net/mcp",
    "headers": { "Authorization": "Bearer gbrain_..." } } } }
```

### Ruta 2 — OAuth 2.1 + PKCE (claude.ai, ChatGPT, Grok)

Estos clientes no aceptan pegar un token; exigen el baile OAuth completo. El wrapper expone
`/.well-known/oauth-authorization-server`, `/oauth/authorize`, `/oauth/token` y
`/oauth/register` (DCR).

**⚠️ TRAMPA DE GROK — redirect_uri (costó un ciclo completo el 2026-09-28).**
Grok **no muestra su callback** en el formulario, y si registras el cliente con la URL
equivocada la autorización muere en `{"error":"invalid_redirect_uri"}` **antes** de la
pantalla de login. Grok usa DOS callbacks y hay que registrar ambos:

```
https://grok.com/connectors/oauth/callback
https://grok.com/connectors-oauth-exchange-code/
```

Registro del cliente:

```bash
curl -X POST https://<tu-host>.ts.net/mcp/oauth/register \
  -H "Content-Type: application/json" \
  -d '{"client_name":"grok",
       "redirect_uris":["https://grok.com/connectors/oauth/callback",
                        "https://grok.com/connectors-oauth-exchange-code/"],
       "grant_types":["authorization_code","refresh_token"],
       "response_types":["code"],
       "token_endpoint_auth_method":"none"}'
```

Lo que devuelve `client_id` va en grok.com/connectors → Custom, junto con los endpoints de
authorize/token, ámbito `mcp`, y método de auth **"ninguno (solo PKCE)"**. El secreto de
cliente se deja vacío: es un cliente público.

**Grok exige URL alcanzable desde internet.** Si el Funnel se cae, Grok pierde el brain
aunque Cursor siga funcionando por tailnet — por eso el Layer 18 del dashboard los lista
en filas separadas.

### Verificar que un cliente quedó conectado de verdad

No basta con que la UI diga "conectado". Mira el tráfico real:

```bash
journalctl --user -u gbrain-http-wrapper --since "30 min ago" | grep -oE 'ua="[^"]+"' | sort | uniq -c
```

Un `POST /oauth/token 200` sólo prueba que se autenticó. Hasta que no veas un `tools/list`
o un `tools/call` de ese user-agent, el cliente no ha ejercitado el brain.

## Verifying "shared brain" claims

Before trusting that two machines hit the same brain, write a unique test page from one and read it from the other:

```bash
# on machine A:
echo "ping from A at $(date -u +%FT%TZ)" | gbrain put test/multi-client-check

# on machine B:
gbrain get test/multi-client-check
# should print the same string
```

If machine B prints what A wrote → confirmed shared. If not, the `database_url` differs or there's a network/firewall issue between B and Supabase.

## Common pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| `claude mcp list` shows `✗ Failed` | `gbrain` binary not in `PATH` for the shell that launched Claude Code | Use absolute path: `claude mcp add gbrain -- /full/path/to/gbrain serve` |
| `gbrain doctor` says `pgvector NOT FOUND` on machine B but works on A | Different `database_url` | Diff `~/.gbrain/config.json` across machines |
| Claude Desktop "added" the server but tools never appear | Tried `claude_desktop_config.json` for a remote URL | Desktop only takes remote MCP via Settings > Integrations GUI; JSON config is stdio-only |
| Tailscale URL works on tailnet but not from claude.ai web | claude.ai web runs on Anthropic's servers — not in your tailnet | Use Tailscale **Funnel** (public) or ngrok, not Tailscale **Serve** (tailnet-only) |

## References

- Upstream docs: [github.com/garrytan/gbrain/tree/main/docs/mcp](https://github.com/garrytan/gbrain/tree/main/docs/mcp)
  - [CLAUDE_CODE.md](https://github.com/garrytan/gbrain/blob/main/docs/mcp/CLAUDE_CODE.md) — local stdio (canonical)
  - [CLAUDE_DESKTOP.md](https://github.com/garrytan/gbrain/blob/main/docs/mcp/CLAUDE_DESKTOP.md) — remote HTTP (requires wrapper)
  - [CLAUDE_COWORK.md](https://github.com/garrytan/gbrain/blob/main/docs/mcp/CLAUDE_COWORK.md) — remote HTTP (requires wrapper)
  - [PERPLEXITY.md](https://github.com/garrytan/gbrain/blob/main/docs/mcp/PERPLEXITY.md) — remote HTTP (requires wrapper)
  - [DEPLOY.md](https://github.com/garrytan/gbrain/blob/main/docs/mcp/DEPLOY.md) — tunneling + auth tokens
  - [ALTERNATIVES.md](https://github.com/garrytan/gbrain/blob/main/docs/mcp/ALTERNATIVES.md) — ngrok vs Tailscale Funnel vs Fly.io
- This skill (health dashboard): [SKILL.md](SKILL.md)
- Author: Sergio Durán ([@durang](https://github.com/durang))
