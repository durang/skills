---
name: whatsapp
description: "WhatsApp monitor dashboard for OpenClaw. Shows connection status, monitored groups with last message, config per group (read/write/mute), DM policies, GBrain storage status, and detected-but-unconfigured groups. Subcommands: /whatsapp (status dashboard), /whatsapp add <group>, /whatsapp remove <group>, /whatsapp groups, /whatsapp guide. Triggers: /whatsapp, whatsapp status, que grupos tengo, agrega grupo whatsapp, revisa whatsapp."
allowed-tools: Bash Read Write Agent
user-invocable: true
distribute-to: [claude, openclaw]
---

# /whatsapp — WhatsApp Monitor Dashboard

You are managing the WhatsApp channel on OpenClaw running on Jarvis (EC2).

## IMPORTANT: Always verify against live state

Never trust cached info. Every invocation MUST run the verification commands below and show REAL state.

## OUTPUT FORMAT — Two parts, always both

### Part 1: Text response (directly to user)
A quick functional summary in conversational text. Example:

```
WhatsApp esta conectado y healthy. Tu numero +526624707325 vinculado.

Tienes 1 grupo monitoreado:
  - JPC — read-only, sin visto, guardando todo en GBrain. Ultimo mensaje hace 7 min: "thanks jonathan..."

3 grupos detectados disponibles para agregar:
  - 120363427149546617@g.us (ultimo: "MACBOOK: https://...")
  - 120363418735974556@g.us (ultimo: "Viral Videos")  
  - 5216623573702-1575495688@g.us (ultimo: "Quien renta asador?")

DMs: deshabilitados. Nadie puede escribirte por WhatsApp al bot.
GBrain: guia guardada, datos de JPC pendientes (esperando mensajes).
Sistema: 9h uptime, 5.5GB RAM, load 0.11.

Reporte completo: ~/whatsapp-status.md
```

Key rules for text response:
- Hablar claro, directo, en espanol
- Listar cada grupo con su estado real (read-only, puede responder, visto on/off, GBrain activo/no)
- Decir cuantos grupos detectados hay disponibles
- Mencionar alertas si algo esta mal
- Dar el path al .md al final

### Part 2: Detailed .md report (saved to file)
Write a complete report to `~/whatsapp-status.md` with ALL details:

```markdown
# WhatsApp Monitor — Reporte Completo
> Generado: YYYY-MM-DD HH:MM UTC
> Skill version: 1.1

---

## Estado de Conexion

| Campo | Estado | Detalle |
|---|---|---|
| Canal | connected/disconnected | Verificado via openclaw channels status |
| Numero | +526624707325 | Personal, Hermosillo |
| Health | healthy/degraded/offline | Ultimo check |
| Ultimo mensaje recibido | Xm ago | Timestamp |
| Sesion | linked/unlinked | Baileys WhatsApp Web |
| Gateway | active/inactive | systemd service |

## Configuracion Global

| Setting | Valor | Que significa | Se puede cambiar |
|---|---|---|---|
| enabled | true | Canal activo | /whatsapp disable |
| dmPolicy | disabled | No recibe DMs | /whatsapp dm add <numero> |
| groupPolicy | allowlist | Solo grupos listados | Agregar con /whatsapp add |
| sendReadReceipts | false | Sin visto azul, invisible | Config en openclaw.json |
| reactionLevel | off | No pone emojis | Config en openclaw.json |
| selfChatMode | false | Escucha grupos | Config en openclaw.json |
| pluginHooks.messageReceived | true/false | GBrain capture | Config en openclaw.json |
| allowFrom | [+526624707325] | Tu numero | Config en openclaw.json |

## Grupos Monitoreados (detalle)

### Grupo: JPC
| Campo | Valor |
|---|---|
| ID | 120363425126131671@g.us |
| Modo | read-only (observador silencioso) |
| Responde en grupo | NO (systemPrompt lo prohibe) |
| Visto azul | NO (sendReadReceipts: false) |
| Reacciones | NO (reactionLevel: off) |
| requireMention | false (lee todo) |
| GBrain slug | whatsapp/jpc/YYYY-MM-DD |
| Que guarda | TODO + resumen importante |
| Ultimo mensaje | "texto..." |
| SystemPrompt completo | (pegar el prompt entero) |

(repetir para cada grupo monitoreado)

## Grupos Detectados (no monitoreados)

| # | ID | Ultimo mensaje | Cuando | Como agregar |
|---|---|---|---|---|
| 1 | 120363...@g.us | "texto..." | hace X | /whatsapp add |
| 2 | ... | ... | ... | /whatsapp add |

## DMs Monitoreados

| Numero | Estado | Desde cuando |
|---|---|---|
| (ninguno si dmPolicy=disabled) | | |

## GBrain Storage

| Slug | Tipo | Ultima actualizacion | Tamano |
|---|---|---|---|
| guias/whatsapp-openclaw-setup | Guia | fecha | X chunks |
| guias/whatsapp-history/YYYY-MM-DD | Historial | fecha | X chunks |
| whatsapp/jpc/YYYY-MM-DD | Datos grupo | fecha o "sin datos" | X chunks |

## Templates de SystemPrompt disponibles

### 1. Guardar todo + resumen (DEFAULT)
Guarda cada mensaje + resumen diario de lo importante.

### 2. Solo lo importante
Solo decisiones, tareas, fechas, acuerdos.

### 3. Enfocado en personas
Guarda todo de personas especificas, solo importante de los demas.

## Comandos disponibles

| Comando | Que hace |
|---|---|
| /whatsapp | Este dashboard completo |
| /whatsapp add | Agregar grupo al monitoreo |
| /whatsapp remove | Quitar grupo del monitoreo |
| /whatsapp groups | Solo tabla de grupos |
| /whatsapp guide | Mostrar guia de GBrain |
| /whatsapp dm add <num> | Monitorear DMs de un numero |
| /whatsapp dm remove <num> | Dejar de monitorear DMs |

## Como crear/configurar un agente para un grupo nuevo

1. Obtener ID: mandar mensaje en el grupo o esperar que alguien mande
2. Verificar ID: grep "@g.us" /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log | sort -u
3. Decidir reglas: guardar todo, solo importante, o enfocado en personas
4. Agregar a config: editar openclaw.json o pedir /whatsapp add
5. Reiniciar: systemctl --user restart openclaw-gateway
6. Verificar: openclaw channels status --channel whatsapp
7. Actualizar guia en GBrain

## Troubleshooting

| Problema | Solucion |
|---|---|
| WhatsApp desconectado | openclaw channels login --channel whatsapp (re-escanear QR) |
| No llegan mensajes | Verificar groupPolicy y que ID este en groups |
| pluginHooks null | Agregar pluginHooks.messageReceived: true en config |
| Gateway caido | systemctl --user restart openclaw-gateway |
| Quiero ver logs | journalctl --user -u openclaw-gateway -f \| grep whatsapp |

## Archivos clave

| Archivo | Que es |
|---|---|
| ~/.openclaw/openclaw.json | Config principal |
| ~/.openclaw/credentials/whatsapp/ | Credenciales sesion |
| /tmp/openclaw/openclaw-YYYY-MM-DD.log | Logs del dia |
| ~/whatsapp-status.md | Este reporte |
| gbrain: guias/whatsapp-openclaw-setup | Guia viva |
| gbrain: guias/whatsapp-history/ | Historial de cambios |
```

Write this to `~/whatsapp-status.md` on jarvis via SSH, then tell the user the path.

## Data collection commands

Run ALL of these on jarvis via SSH to get real data:

```bash
# 1. Channel status
ssh jarvis 'openclaw channels status --channel whatsapp 2>&1 | grep -i whatsapp'

# 2. Current config
ssh jarvis 'python3 -c "
import json
with open(\"/home/ec2-user/.openclaw/openclaw.json\") as f:
    cfg = json.load(f)
wa = cfg.get(\"channels\", {}).get(\"whatsapp\", {})
groups = wa.get(\"groups\", {})
print(\"ENABLED:\", wa.get(\"enabled\"))
print(\"DM_POLICY:\", wa.get(\"dmPolicy\"))
print(\"GROUP_POLICY:\", wa.get(\"groupPolicy\"))
print(\"READ_RECEIPTS:\", wa.get(\"sendReadReceipts\"))
print(\"REACTION:\", wa.get(\"reactionLevel\"))
print(\"SELF_CHAT:\", wa.get(\"selfChatMode\"))
print(\"HOOKS:\", wa.get(\"pluginHooks\"))
print(\"ALLOW_FROM:\", wa.get(\"allowFrom\"))
print(\"GROUP_COUNT:\", len(groups))
for gid, gcfg in groups.items():
    mention = gcfg.get(\"requireMention\", True)
    prompt = gcfg.get(\"systemPrompt\", \"\")
    print(f\"GROUP:{gid}|mention={mention}|prompt_len={len(prompt)}\")
    print(f\"PROMPT_FULL:{prompt}\")
"'

# 3. Groups seen today in logs
ssh jarvis 'grep "@g.us" /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log 2>/dev/null | python3 -c "
import sys, json
groups = {}
for line in sys.stdin:
    try:
        d = json.loads(line)
        info = d.get(\"1\", {})
        frm = info.get(\"from\", \"\")
        body = info.get(\"body\", \"\")
        ts = info.get(\"timestamp\", 0)
        if \"@g.us\" in frm and body:
            groups[frm] = {\"body\": body[:80], \"ts\": ts}
    except:
        pass
for gid, data in sorted(groups.items(), key=lambda x: x[1][\"ts\"], reverse=True):
    print(gid + \"  |  \" + data[\"body\"])
" 2>/dev/null'

# 4. GBrain stored data
ssh jarvis 'gbrain list 2>/dev/null | grep -i whatsapp'

# 5. Gateway health
ssh jarvis 'uptime; free -h | grep Mem'
```

## Subcommands

### `/whatsapp add`
User says "agrega grupo X" or "/whatsapp add":
1. List detected groups not yet in config
2. Ask which one to add and what name to give it
3. Ask what rules (save everything, only important, custom prompt)
4. Edit openclaw.json to add the group
5. Restart gateway
6. Verify with channels status
7. Update gbrain guide: `gbrain put guias/whatsapp-openclaw-setup`
8. Save version snapshot: `gbrain put guias/whatsapp-history/YYYY-MM-DD`

### `/whatsapp remove`
1. Show current monitored groups
2. Confirm which to remove
3. Edit openclaw.json
4. Restart gateway
5. Update gbrain guide

### `/whatsapp groups`
Just show the groups table (monitored + detected), no full dashboard.

### `/whatsapp guide`
Pull and display the guide from gbrain:
```bash
ssh jarvis 'gbrain get guias/whatsapp-openclaw-setup'
```

### `/whatsapp dm add <number>`
1. Change dmPolicy from disabled to allowlist (if not already)
2. Add number to allowFrom
3. Restart gateway
4. Update guide

### `/whatsapp dm remove <number>`
Reverse of add.

## Rules for systemPrompt per group

Each group gets its own systemPrompt in the config. Current templates:

### Template: Save everything + summary (DEFAULT)
```
Eres un observador silencioso del grupo NOMBRE. REGLAS:
1. NUNCA respondas en el grupo.
2. GUARDA TODO en gbrain con slug whatsapp/SLUG/YYYY-MM-DD.
3. Formato: [HH:MM] Nombre: mensaje
4. Multimedia: [HH:MM] Nombre: [tipo recibido]
5. Al final: seccion "Resumen del dia" con decisiones, tareas, fechas, acuerdos.
```

### Template: Only important
```
Eres un observador silencioso del grupo NOMBRE. REGLAS:
1. NUNCA respondas en el grupo.
2. Solo guarda en gbrain lo importante: decisiones, tareas, fechas, acuerdos, problemas.
3. Ignora saludos, emojis, conversacion casual.
4. Slug: whatsapp/SLUG/YYYY-MM-DD
```

### Template: Focused on specific people
```
Eres un observador silencioso del grupo NOMBRE. REGLAS:
1. NUNCA respondas en el grupo.
2. Guarda TODO lo que digan: PERSONA1 (+52...), PERSONA2 (+52...).
3. De los demas, solo guarda decisiones y tareas.
4. Slug: whatsapp/SLUG/YYYY-MM-DD
```

## After ANY change

Always:
1. Restart: `systemctl --user restart openclaw-gateway`
2. Verify: `openclaw channels status --channel whatsapp`
3. Update guide in gbrain
4. Save history snapshot

## Trigger phrases

- /whatsapp
- whatsapp status
- que grupos tengo
- como esta whatsapp
- agrega grupo whatsapp
- quita grupo whatsapp
- revisa whatsapp
- monitorea este grupo
- agrega a este numero
