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

## 📦 Dos modos — usa el que necesites

| Modo | Cuándo usarlo | Qué hace | Dónde lo corres |
|---|---|---|---|
| 🖥️ **SERVIDOR** — [`bootstrap.sh`](#-modo-servidor-bootstrap-de-un-ec2-nuevo) | Tienes un **EC2 NUEVO** (recién lanzado) que vas a usar como host de Claude Code | Hardening + Claude Code + auto-patches OS + tmux + history audit + IMDSv2 verify | **EN el EC2** (vía SSM Session Manager o SSH) |
| 💻 **CLIENTE** — [`/ec2-remote-access`](#-modo-cliente-conectar-tu-compu-al-ec2-los-5-pasos) | Tienes una **compu nueva** (Mac/Linux/iPad) que quieres usar como ventana al EC2 | Instala Tailscale + SSH key + aliases `ec2-tmux` | **EN tu compu cliente** |

> Si vas a montar UN nuevo EC2 desde cero: corre Modo SERVIDOR primero (en el EC2), luego Modo CLIENTE (en tu Mac). Es la combinación canonical.

---

## 🖥️ Modo SERVIDOR: bootstrap de un EC2 nuevo

**Cuándo:** acabas de lanzar un EC2 (Amazon Linux 2023, Ubuntu, Debian, RHEL) y quieres dejarlo robusto + listo para Claude Code en una sola corrida.

**Cómo:** conecta a tu EC2 vía SSM Session Manager (lo más seguro — no necesita SSH abierto) o SSH. Una vez dentro, corre:

```bash
# Recomendado: switch a ec2-user primero (no ssm-user)
sudo su - ec2-user

# Bootstrap
curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/bootstrap.sh | bash
```

**Lo que hace en 6 pasos idempotentes:**

| #  | Paso                                              | Detalle                                                     |
|----|----|-|
| 1  | Updates system packages                           | `dnf upgrade` / `apt upgrade` — baseline limpio              |
| 2  | Instala utilidades base                           | `tmux`, `git`, `jq`, `curl`, `dnf-automatic`/`unattended-upgrades` |
| 3  | **Auto-security-patches**                         | Activa el timer/service para que parches críticos se instalen solos en background |
| 4  | Configura shell                                   | PATH persistente (`~/.local/bin`) + history audit (`HISTTIMEFORMAT`, `HISTSIZE`, append) |
| 5  | Instala Claude Code                               | Con su propio auto-updater incluido                          |
| 6  | Verifica IMDSv2                                   | Confirma que el endpoint v2 responde y v1 se rechaza         |

**Después del bootstrap:**

```bash
# 1. Autenticate Claude (URL en browser → paste code back)
claude

# 2. Persistencia diaria con tmux
tmux new -s claude
claude
# Ctrl+B luego D para detach (Claude sigue corriendo)
# tmux attach -t claude para volver
```

> **Soporta:** Amazon Linux 2023, RHEL/CentOS/Fedora/Rocky/Alma, Ubuntu/Debian.
> **Idempotente:** safe re-correr; nunca borra config, solo añade.

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

## 📦 Estructura del repo

```
ec2-remote-access/
├── SKILL.md      ← El skill (lo lee Claude Code y guía al usuario)
├── README.md     ← Este archivo
├── install.sh    ← Instalador 1-línea (curl | bash)
└── LICENSE       ← MIT
```

Solo 3 archivos. Sin dependencias. Sin contaminar otros skills.

---

## 🔗 Relacionado

Este skill es parte de mi stack canonical, vivido en el monorepo público [`durang/skills`](https://github.com/durang/skills) — pero también vive aquí como standalone para que puedas instalarlo SOLO si es lo único que necesitas.

Si te interesa el resto del stack (orquestador GBrain, dashboard WhatsApp dual-agent, security hardening de OpenClaw, etc.), el monorepo está abierto en MIT.

---

<div align="center">

**Construido por [@durang](https://github.com/durang).** MIT licensed.

_Si tu cerebro vive en la nube, tu acceso debería ser ubicuo._ 🛰️

</div>
