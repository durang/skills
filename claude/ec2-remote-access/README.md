<div align="center">

# 🛰️ /ec2-remote-access

### **Convierte cualquier máquina en una ventana a tu Claude Code corriendo en EC2.**

[![Skill](https://img.shields.io/badge/skill-claude_code-blue?style=flat-square)](#)
[![Transport](https://img.shields.io/badge/transport-SSH_+_Tailscale-success?style=flat-square)](#)
[![Persistence](https://img.shields.io/badge/persistence-tmux-orange?style=flat-square)](#)
[![Setup](https://img.shields.io/badge/setup-3_minutos-brightgreen?style=flat-square)](#)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE)

**3 minutos. 5 comandos. Después: `ec2-tmux` desde cualquier terminal — Claude Code remoto persistente.**

</div>

---

## 📦 El skill tiene 2 modos + 1 herramienta de auto-sanación

| | Comando | Qué hace | Dónde |
|---|---|---|---|
| 🖥️ **SERVIDOR** ⭐ | `curl ... bootstrap.sh \| bash` | Hardening + Claude Code + **systemd Remote Control** (pinned en Desktop) | EN el EC2 |
| 💻 **CLIENTE** | `curl ... install.sh \| bash` → `/ec2-remote-access` | Tailscale + SSH key + aliases para acceso SSH adicional | EN la compu cliente |
| 🔧 **DOCTOR** | `curl ... verify.sh \| bash -s -- --fix` | Diagnóstico de los 8 pasos + **auto-fix de problemas** | EN el EC2 |

> **Flujo canónico:** SERVIDOR primero (EC2 queda con Claude pinned en Desktop). Luego CLIENTE opcional si quieres SSH directo. Y siempre que algo se vea raro: DOCTOR.

> **Self-healing:** cada bug encontrado en implementaciones reales se documenta en [TROUBLESHOOTING.md](TROUBLESHOOTING.md) y se fixea en `bootstrap.sh` + `verify.sh`. El próximo usuario recibe los fixes acumulados.

---

## 🖥️ Modo SERVIDOR — bootstrap de un EC2 nuevo (RECOMENDADO)

**Cuándo:** acabas de lanzar un EC2 (Amazon Linux 2023, Ubuntu, Debian, RHEL) y quieres tu Claude Code corriendo permanente + accesible desde Claude Code Desktop **con un solo comando**.

**Cómo:** conecta a tu EC2 (SSM Session Manager o SSH), `sudo su - ec2-user`, y:

```bash
# Default name será <hostname>-Permanent. Para personalizar (recomendado):
export REMOTE_CONTROL_NAME="JPC-Permanent"   # el nombre que verás en Claude Code Desktop

# Bootstrap (idempotente)
curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/bootstrap.sh | bash
```

**Lo que hace en 7 pasos idempotentes:**

| #  | Paso                                              | Detalle                                                     |
|----|----|-|
| 1  | Updates system (security)                         | `dnf upgrade --security -y` / `apt upgrade` — baseline limpio |
| 2  | Instala utilidades base                           | `tmux`, `git`, `jq`, `dnf-automatic`/`unattended-upgrades` |
| 3  | **Auto-security-patches**                         | Parches críticos se instalan solos en background           |
| 4  | Configura shell                                   | PATH persistente + history audit (`HISTTIMEFORMAT`, `HISTSIZE`) |
| 5  | Instala Claude Code                               | Con auto-updater incluido                                   |
| 6  | Verifica IMDSv2                                   | Confirma endpoint v2 responde y v1 se rechaza               |
| 7  | **🌟 Remote Control systemd service**             | **Crea `~/.config/systemd/user/claude-remote.service` que arranca Claude con `--remote-control "<NAME>"`. Sobrevive reboots/crashes. La sesión aparece PINNED en tu Claude Code Desktop.** |

### Después del bootstrap — tu sesión aparece pinned automáticamente 🎯

1. **Autentica Claude** (una sola vez, primera vez de la EC2):
   ```bash
   claude
   # URL en browser → login → paste code → Ctrl+C después de ver el prompt
   systemctl --user restart claude-remote.service
   ```

2. **Verifica el service:**
   ```bash
   systemctl --user status claude-remote.service
   # → active (running)
   ```

3. **Abre Claude Code Desktop** (o `claude.ai/code` en el browser) **logueado con la misma cuenta** que autenticaste en el EC2:
   - En el sidebar bajo **Pinned** aparece tu sesión con el nombre que configuraste
   - Click → entras directo, persistente, sobrevive todo

**Esa es la "permanencia" que querías.** El service:
- ✅ Restart automático si Claude crash (`Restart=always`)
- ✅ Sobrevive reboots del EC2 (`WantedBy=default.target` + linger habilitado)
- ✅ Sobrevive logout del usuario (linger)
- ✅ No requiere SSH desde el cliente — Claude Code Desktop habla con el EC2 vía Anthropic backend

> **Soporta:** Amazon Linux 2023, RHEL/CentOS/Fedora/Rocky/Alma, Ubuntu/Debian.
> **Idempotente:** safe re-correr; solo añade lo que falta, nunca borra config.

---

## 💻 Modo CLIENTE: conectar tu compu al EC2 (los 5 pasos)

**Cuándo:** ya tienes un EC2 funcionando (configurado por ti, por un compañero, o con el Modo SERVIDOR arriba) y quieres usarlo desde una **máquina nueva** (Mac/Linux/Windows-WSL).

### 1️⃣ Instalar Claude Code en esta máquina

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Verifica:

```bash
claude --version
# → 2.1.144 (Claude Code)  ← o versión similar
```

> Alternativa GUI: descarga la app .dmg desde **https://claude.ai/code**

---

### 2️⃣ Autenticar Claude Code

```bash
claude
```

Te abre el navegador → login con tu cuenta Anthropic → vuelves al terminal autenticado.
Sal con `Ctrl+D` (o `/exit`) y pasa al Paso 3.

---

### 3️⃣ Instalar el skill `/ec2-remote-access`

```bash
curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/install.sh | bash
```

Output esperado:

```
▶ Installing /ec2-remote-access skill
  Target: ~/.claude/skills/ec2-remote-access
  → SKILL.md
  → README.md

✅ Installed.
```

---

### 4️⃣ Abrir Claude Code

```bash
claude
```

---

### 5️⃣ Invocar el skill — dentro de Claude

```
/ec2-remote-access
```

El skill te pregunta 4 datos:

```
1. ¿OS de esta máquina?     (Mac / Linux / Windows-WSL)
2. ¿Hostname Tailscale del EC2?  (ej: jarvis-v3, mi-servidor)
3. ¿Usuario SSH del EC2?    (default: ec2-user)
4. ¿Home dir del EC2?       (default: /home/ec2-user)
```

Y te guía paso a paso (Tailscale, SSH key, aliases) verificando cada paso. Al terminar tienes 7 aliases listos:

```bash
ec2-tmux       # ⭐ sesión Claude Code remota PERSISTENTE (sobrevive cierres de laptop / WiFi)
ec2            # sesión nueva (no persistente)
ec2-continue   # retomar última sesión
ec2-resume     # menú de sesiones previas
ec2-shell      # solo terminal del EC2 (sin Claude)
ec2-tmux-2/3   # sesiones tmux paralelas
```

---

## ⚡ Los 5 comandos en orden (copy-paste ready)

```bash
curl -fsSL https://claude.ai/install.sh | bash                                                # 1. instalar Claude Code
claude                                                                                         # 2. authenticate (login browser) — sal con Ctrl+D
curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/install.sh | bash # 3. instalar skill
claude                                                                                         # 4. abrir Claude Code
# Dentro de Claude:                                                                            # 5. invocar skill
/ec2-remote-access
```

---

## ✨ Qué hace

Te abre Claude Code corriendo en tu EC2 — con todo tu stack (memoria, agentes, MCPs, secrets) — desde **cualquier máquina nueva**, sin re-instalar nada del stack.

```bash
# Después del setup, desde cualquier terminal:
$ ec2-tmux

# Te aparece esto, igual que si estuvieras enfrente del EC2:
Claude Code 2.1.144
🧠 Tu stack canonical conectado
📡 Tus MCPs ready
>
```

**Antes:** abrías terminal, recordabas IP, esperabas password, manualmente cargabas `claude`, y si se caía el WiFi perdías todo el contexto.

**Después:** tecleas `ec2-tmux` y estás dentro. Cierra laptop / cae WiFi → regresas, mismo comando, mismo estado exacto.

---

## 🤯 Por qué importa

Si tu cerebro vive en un EC2 (memoria + agentes + MCPs), tu acceso a él no puede depender de "qué máquina tengo enfrente". Necesitas que **cualquier teclado** sea una puerta a tu agente.

| Problema antes                                      | Después                            |
|------------------------------------------------------|------------------------------------|
| Compu nueva = 2-3 horas reconfigurando todo          | Compu nueva = 3 minutos            |
| SSH se cae, pierdes contexto del agente             | tmux preserva sesión indefinidamente |
| Recordar IPs, paths, flags                           | `ec2`, `ec2-tmux`, `ec2-resume`    |
| Subir SSH key manualmente                           | Skill guía y verifica cada paso    |
| Diferentes Macs, configs distintas                  | Mismo skill, mismo config en todas |

---

## 🎯 Lo que el skill hace por ti (9 pasos verificados)

| #  | Paso                                  | Lo hace por ti                                          |
|----|---------------------------------------|---------------------------------------------------------|
| 0  | Detecta tu OS + recolecta tu hostname | Te pregunta 4 cosas y guarda en `~/.config/`            |
| 1  | Instala Tailscale                     | `brew/apt/curl install` + verifica login                |
| 2  | Verifica conectividad al EC2          | `tailscale status \| grep` + alerta si no aparece       |
| 3  | Genera SSH key                        | `ssh-keygen -t ed25519` con identificación de máquina   |
| 4  | Autoriza la key en EC2                | Opción A (vía otra Mac) u Opción B (AWS Console)        |
| 5  | Configura `~/.ssh/config`             | Entry canónica con alias `Host ec2`                     |
| 6  | Test de conexión                      | `ssh -o BatchMode` + diagnóstico si falla               |
| 7  | Crea 7 aliases en tu shell            | `ec2`, `ec2-tmux`, `ec2-resume`, etc.                   |
| 8  | Persiste config del skill             | `~/.config/ec2-remote-access/config.env`                |
| 9  | Smoke test final                      | Te dice exactamente qué tecleas para entrar             |

---

## 🧠 Diagrama mental

```
┌────────────────────────────┐         SSH         ┌──────────────────────────────────┐
│  CUALQUIER máquina nueva   │  ──(Tailscale)──▶  │  Tu EC2 (canonical home del stack)│
│  Mac · Linux · Windows/WSL │                     │                                  │
│                            │                     │  • Claude Code corre AQUÍ        │
│  Solo tiene:               │                     │  • Tu memoria persistente        │
│  • Terminal                │                     │  • Tus agentes activos           │
│  • Tailscale               │                     │  • Todos tus MCPs registrados    │
│  • SSH key autorizada      │                     │  • Tus tools y secrets           │
│  • 7 aliases               │                     │  • Tus sesiones previas          │
└────────────────────────────┘                     └──────────────────────────────────┘
```

**Regla mental:** Claude Code vive en EC2. Las máquinas nuevas son ventanas a esa instancia, no instalaciones duplicadas.

---

## 🔒 Por qué Tailscale (y no SSH público + clave .pem)

| Vector                  | SSH público (.pem)             | Tailscale + SSH               |
|--------------------------|--------------------------------|-------------------------------|
| Brute force al puerto 22 | ❌ Cualquier bot puede intentar | ✅ Puerto 22 cerrado al mundo  |
| Tu .pem se filtra        | 💀 Game over                   | ✅ Sin .pem — usa tu Tailscale identity |
| Revocar acceso           | Manualmente edit authorized_keys | Click "Disconnect device" en admin panel |
| Multi-device             | Misma key en todas (riesgo)    | Cada device tiene su identidad |
| Auditoría                | Logs de sshd                   | Logs de Tailscale + sshd       |

El skill asume que ya tienes Tailscale en tu cuenta. Si no, te lo instala en el Paso 1.

---

## 🐛 Troubleshooting incluido

El skill tiene branching automático para los 6 errores más comunes:
- `Permission denied (publickey)` → vuelta al Paso 4
- `Could not resolve hostname` → fallback a IP Tailscale directa
- `claude: command not found` → fix de PATH o usar full path
- `tmux not installed` → comando de instalación según OS
- `Connection refused` → diagnóstico de sshd + Security Group
- `session locked` → guía para usar `--resume` en vez

---

## 💡 Casos de uso reales

1. **Compré una MacBook nueva** → instalo Claude Code + curl install → 3 min después estoy dentro de mi agente con todo el contexto
2. **iPad en una cafetería** → Termius + Tailscale + `ec2-tmux` → mismo Claude Code que en casa
3. **Mi mac actual se mojó con café** → cualquier máquina prestada me sirve mientras envío la mía a reparar
4. **Quiero 3 sesiones paralelas trabajando en cosas distintas** → `ec2-tmux`, `ec2-tmux-2`, `ec2-tmux-3` en 3 terminals
5. **Pair programming remoto** → ambos `ec2-tmux` a la misma sesión = literalmente sobre el mismo Claude

---

## 🗑️ Desinstalar

```bash
# Borrar el skill
rm -rf ~/.claude/skills/ec2-remote-access

# Opcional: limpiar config persistente
rm -rf ~/.config/ec2-remote-access

# Opcional: quitar los aliases (edita ~/.zshrc o ~/.bashrc y borra el bloque
# entre "─── Claude Code remoto en ..." y la última línea de ec2-tmux-3)
```

---

## 🔧 Auto-sanación con verify.sh

Si después de algún reboot o auto-update algo se ve raro, **un solo comando lo diagnostica y arregla**:

```bash
# Diagnóstico (read-only, lista qué está bien y qué falla):
curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/verify.sh | bash

# Diagnóstico + arreglo automático:
curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/verify.sh | bash -s -- --fix
```

Chequea los 8 mismos pasos del bootstrap. Si encuentra algo roto, lo arregla (con `--fix`) o te dice exactamente cómo arreglarlo (sin flag).

---

## 🐛 Self-improving: bugs solucionados se acumulan

Cada bug encontrado en implementaciones reales **se documenta + se fixea + el próximo usuario lo hereda gratis**. Ver:

- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — 8 bugs reales documentados con síntoma + causa raíz + fix
- **[CHANGELOG.md](CHANGELOG.md)** — versión + cada fix con contexto histórico

Bugs ya solucionados que **NO te van a pasar** porque `bootstrap.sh` los maneja:
1. `curl-minimal` vs `curl` conflict en Amazon Linux 2023
2. `dnf upgrade -y` aborta con conflictos transitivos
3. Single-binary Claude Code layout (`~/.local/bin/claude`) no detectado
4. Trust dialog bloquea systemd service en restarts
5. ssm-user efímero detectado y rechazado correctamente
6. tmux session duplicado por confusión de naming
7. SSM Session Manager TTY issues
8. Cuentas Anthropic distintas (cliente vs servidor)

---

## 📦 Estructura del repo

```
ec2-remote-access/
├── bootstrap.sh         ← SERVIDOR: hardening + Remote Control systemd (8 pasos)
├── install.sh           ← CLIENTE: instala el skill /ec2-remote-access en Claude Code
├── verify.sh            ← DOCTOR: self-diagnostic + auto-fix de los 8 pasos
├── SKILL.md             ← El skill conversacional (lo lee Claude Code para guiar al cliente)
├── README.md            ← Este archivo
├── TROUBLESHOOTING.md   ← Bugs reales encontrados + cómo se solucionaron
├── CHANGELOG.md         ← Versión + historial de cada mejora
└── LICENSE              ← MIT
```

Una sola URL. Tres comandos. Cobertura completa de servidor + cliente + diagnóstico.

---

## 🔗 Relacionado

Este skill es parte de mi stack canonical, vivido en el monorepo público [`durang/skills`](https://github.com/durang/skills) — pero también vive aquí como standalone para que puedas instalarlo SOLO si es lo único que necesitas.

Si te interesa el resto del stack (orquestador GBrain, dashboard WhatsApp dual-agent, security hardening de OpenClaw, etc.), el monorepo está abierto en MIT.

---

<div align="center">

**Construido por [@durang](https://github.com/durang).** MIT licensed.

_Si tu cerebro vive en la nube, tu acceso debería ser ubicuo._ 🛰️

</div>
