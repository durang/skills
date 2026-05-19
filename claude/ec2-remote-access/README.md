<div align="center">

# 🛰️ /ec2-remote-access

### **Convierte cualquier máquina en una ventana a tu Claude Code remoto en EC2.**

[![Skill](https://img.shields.io/badge/skill-claude_code-blue?style=flat-square)](#)
[![Transport](https://img.shields.io/badge/transport-SSH_+_Tailscale-success?style=flat-square)](#)
[![Persistence](https://img.shields.io/badge/persistence-tmux-orange?style=flat-square)](#)
[![Setup](https://img.shields.io/badge/setup-9_pasos-brightgreen?style=flat-square)](#)

**Una compu nueva. Tres minutos. Un comando para siempre: `ec2-tmux`.**

</div>

---

## ✨ Qué hace

Te abre Claude Code corriendo en tu EC2 — con todo tu stack (GBrain, OpenClaw, Hermes, MCPs, secrets) — desde **cualquier máquina nueva**, sin re-instalar nada del stack.

```bash
# En máquina nueva, después de configurar (1 sola vez):
$ ec2-tmux

# Te aparece esto, igual que si estuvieras enfrente del EC2:
Claude Code 2.1.144
🧠 GBrain conectado (4,000+ pages)
📡 OpenClaw + Hermes + MCPs ready
>
```

**Antes:** abrías terminal, recordabas `ssh ec2-user@100.117.155.74 -i ~/.ssh/blah.pem`, esperabas password, manualmente cargabas `claude`, y si se caía el WiFi perdías todo el contexto.

**Después:** tecleas `ec2-tmux` y estás dentro. Caes WiFi, regresas, mismo comando, mismo estado.

---

## 🤯 Por qué importa

Si tu cerebro vive en un EC2 (GBrain + agentes), tu acceso a él no puede depender de "qué máquina tengo enfrente". Necesitas que **cualquier teclado** sea una puerta a tu agente.

| Problema antes                                      | Después                            |
|------------------------------------------------------|------------------------------------|
| Compu nueva = 2-3 horas reconfigurando todo          | Compu nueva = 3 minutos            |
| SSH se cae, pierdes contexto del agente             | tmux preserva sesión indefinidamente |
| Recordar IPs, paths, flags                           | `ec2`, `ec2-tmux`, `ec2-resume`    |
| Subir SSH key manualmente                           | Skill guía y verifica cada paso    |
| Diferentes Macs, configs distintas                  | Mismo skill, mismo config en todas |

---

## 🚀 Uso

```bash
# 1) Clona tu monorepo de skills en la máquina nueva (1 sola vez por máquina):
git clone https://github.com/durang/skills ~/skills
cd ~/skills && ./install.sh

# 2) Abre Claude Code en la máquina nueva
claude

# 3) Tecleas:
/ec2-remote-access

# Y el skill te guía paso a paso. Al final tienes:
ec2-tmux   # ← un solo comando para abrir Claude remoto persistente
```

---

## 🎯 Lo que el skill hace por ti (9 pasos automatizados)

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

## 🛠️ Aliases que crea

| Comando         | Para qué                                                       |
|-----------------|----------------------------------------------------------------|
| `ec2`           | Sesión Claude Code remota nueva                                |
| `ec2-tmux` ⭐    | Sesión persistente — sobrevive cierres de laptop / WiFi caído  |
| `ec2-continue`  | Retomar la sesión más reciente                                 |
| `ec2-resume`    | Menú de todas las sesiones previas                             |
| `ec2-shell`     | Solo terminal del EC2 (sin Claude)                             |
| `ec2-tmux-2/3`  | Sesiones tmux paralelas independientes                         |

---

## 🧠 Diagrama mental

```
┌────────────────────────────┐         SSH         ┌──────────────────────────────────┐
│  CUALQUIER máquina nueva   │  ──(Tailscale)──▶  │  Tu EC2 (canonical home del stack)│
│  Mac · Linux · Windows/WSL │                     │                                  │
│                            │                     │  • Claude Code corre AQUÍ        │
│  Solo tiene:               │                     │  • GBrain database conectada     │
│  • Terminal                │                     │  • OpenClaw + Hermes activos     │
│  • Tailscale               │                     │  • Todos tus MCPs registrados    │
│  • SSH key autorizada      │                     │  • Tu memoria persistente        │
│  • 7 aliases               │                     │  • Tu compound engine             │
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

## 🔗 Skills relacionados

- 🧠 [/gbrain](../../shared/gbrain/) — orchestrator del stack completo (este skill se complementa con él)
- 🛡️ [/openclaw-security](../openclaw-security/) — hardening del EC2 (corre ANTES de exponer el SSH)

---

## 💡 Casos de uso reales

1. **Compré una MacBook nueva** → instalo Claude Code + clono skills + `/ec2-remote-access` → 3 min después estoy dentro de mi agente con todo el contexto
2. **iPad en una cafetería** → Termius + Tailscale + `ec2-tmux` → mismo Claude Code que en casa
3. **Mi mac actual se mojó con café** → cualquier máquina prestada me sirve mientras envío la mía a reparar
4. **Quiero 3 sesiones paralelas trabajando en cosas distintas** → `ec2-tmux`, `ec2-tmux-2`, `ec2-tmux-3` en 3 terminals
5. **Estoy programando con un colaborador remoto** → ambos `ec2-tmux` a la misma sesión = pair programming literal sobre el mismo Claude

---

<div align="center">

**Construido por [@durang](https://github.com/durang).** MIT licensed.

_Si tu cerebro vive en la nube, tu acceso debería ser ubiquo._ 🛰️

</div>
