---
name: ec2-remote-access
description: |
  Conecta una máquina nueva (Mac, Linux, Windows/WSL) a tu stack de Claude Code corriendo
  en un EC2 vía SSH + Tailscale + tmux persistente. Te guía paso a paso: detecta tu OS,
  instala Tailscale, configura SSH keys, crea aliases, verifica la conexión. Una vez
  configurado, el comando "ec2" desde cualquier terminal te conecta a Claude Code remoto
  exactamente igual que si estuviera local. Funciona incluso si tu Mac se cae o cambias
  de WiFi (tmux mantiene la sesión viva en EC2).
triggers:
  - "/ec2-remote-access"
  - "/ec2-setup"
  - "conectar a mi EC2"
  - "configurar máquina nueva para EC2"
  - "remote claude code"
  - "tailscale ssh setup"
  - "abrir claude en otra compu"
tools:
  - exec
  - read
  - write
distribute-to: [claude]
---

# /ec2-remote-access — guía interactiva (modo CLIENTE)

Tu trabajo cuando se invoca este skill: **acompañar al usuario paso a paso** desde una máquina nueva hasta poder abrir Claude Code corriendo en su EC2 con un solo comando (`ec2-tmux`).

## SCOPE de este skill — IMPORTANTE

- ✅ Cubre el **lado CLIENTE** (Mac/Linux/Windows que se conecta vía SSH a un EC2)
- ❌ NO cubre el lado SERVIDOR (el EC2 mismo) — para eso existe `bootstrap.sh` en el mismo repo
- 🔧 Para auto-diagnóstico/healing post-instalación: `verify.sh --fix` en el EC2

**Antes de empezar, pregunta al usuario:**
> "¿Ya tienes el EC2 servidor configurado con Claude Code? Si NO → debes correr primero `bootstrap.sh` EN el EC2 (no este skill). Si SÍ, o si solo quieres SSH directo además del Pinned en Desktop, sigamos."

Si el usuario solo quiere la sesión `<NAME>-Permanent` pinned en Claude Code Desktop (sin SSH manual), **no necesita este skill** — solo necesita `bootstrap.sh` ejecutado en el EC2. Aclara esto si parece confundido.

**No leas todos los pasos y los ejecutes en bloque.** Ve **paso por paso**, verificando que cada uno funcionó antes de pasar al siguiente. Si algo falla, ve directo a la sección de troubleshooting.

---

## Concepto que debes explicarle al usuario primero

Antes de empezar pasos, dile (1-2 frases):

> "Claude Code NO se va a instalar aquí. Va a correr en tu EC2. Esta máquina solo será un control remoto vía SSH a través de Tailscale. Al final, tecleando `ec2` desde cualquier terminal de aquí, te conectas a Claude Code remoto con todo tu stack (GBrain, OpenClaw, Hermes) intacto."

Si confirma que entendió, procede al Paso 0.

---

## Paso 0 — Recolectar info crítica (antes de tocar nada)

Pregúntale al usuario las **4 cosas siguientes** ANTES de ejecutar cualquier comando. Sin estos datos no podemos seguir.

```
1. ¿Qué OS está corriendo esta máquina? (Mac / Linux / Windows-WSL)
2. ¿Cuál es el hostname Tailscale de tu EC2? (ej: jarvis-v3, mi-servidor, prod-1)
3. ¿Cuál es el usuario SSH del EC2? (default: ec2-user — confirma)
4. ¿Cuál es el directorio inicial donde quieres que arranque Claude Code? (default: /home/ec2-user)
```

Guarda estos valores en variables internas (`OS`, `EC2_HOST`, `EC2_USER`, `EC2_HOME`). Vas a usarlos en todos los pasos siguientes y al final en `~/.config/ec2-remote-access/config.env`.

Si el usuario no sabe el hostname Tailscale, dile que entre a https://login.tailscale.com/admin/machines desde el navegador y copie el "Machine name" del EC2.

---

## Paso 1 — Instalar Tailscale

Adapta el comando según `OS`:

**Mac:**
```bash
which tailscale >/dev/null 2>&1 && echo "✅ Tailscale ya instalado" || \
  (echo "Instalando..." && brew install --cask tailscale && open -a Tailscale)
```

**Linux (Ubuntu/Debian/Amazon Linux):**
```bash
which tailscale >/dev/null 2>&1 && echo "✅ Tailscale ya instalado" || \
  (curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up)
```

**Windows/WSL:** Dile que descargue desde https://tailscale.com/download/windows (es GUI, no automatizable). Espera a que confirme antes de seguir.

Ejecuta el comando. Si el resultado es "ya instalado", pasa al Paso 2. Si lo acabas de instalar, dile que **haga login con la cuenta del usuario** (la misma cuenta de Tailscale que usa en su Mac/EC2 actual). Espera confirmación.

---

## Paso 2 — Verificar que Tailscale ve al EC2

```bash
tailscale status | grep -E "${EC2_HOST}|$(echo ${EC2_HOST} | tr '[:upper:]' '[:lower:]')" || \
  echo "❌ ${EC2_HOST} no aparece en tu tailnet"
```

**Si NO aparece:**
- La cuenta de Tailscale no es la correcta → `tailscale logout && tailscale up` y login con la cuenta correcta
- O el device nuevo no está aprobado → entrar a https://login.tailscale.com/admin/machines y aprobarlo

NO sigas hasta que el grep encuentre el EC2.

**Si SÍ aparece:** guarda el IP Tailscale del EC2 (`tailscale status | grep ${EC2_HOST} | awk '{print $1}'`). Lo vas a necesitar como fallback.

---

## Paso 3 — Generar / verificar SSH key

```bash
ls ~/.ssh/id_ed25519.pub 2>/dev/null && echo "✅ SSH key ya existe" || \
  (echo "Generando nueva SSH key..." && ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)-$(date +%Y%m%d)" -f ~/.ssh/id_ed25519 -N "")
```

**Importante:** `-N ""` crea la key SIN passphrase. Si el usuario prefiere passphrase (más seguro pero más fricción), pregúntale antes y ejecuta sin `-N ""`.

Después muestra la public key:
```bash
cat ~/.ssh/id_ed25519.pub
```

Dile al usuario: **"Copia esa línea entera. Ahora la vamos a autorizar en el EC2."**

---

## Paso 4 — Autorizar la SSH key en el EC2

El usuario tiene 2 opciones para hacer esto, dependiendo de si ya tiene otra máquina conectada al EC2.

### Opción A — Ya tiene otra máquina con acceso al EC2 (más fácil)

Dile que abra terminal en su Mac existente (o donde ya tenga acceso), conecte por SSH al EC2, y agregue la nueva key:

```bash
# En máquina YA conectada al EC2:
ssh ${EC2_USER}@${EC2_HOST}

# Una vez dentro del EC2:
echo 'ssh-ed25519 AAAA... TU_KEY_NUEVA_AQUI' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
```

Espera confirmación de que lo hizo.

### Opción B — Es su primera máquina conectada al EC2

Necesita autorizar la key vía AWS Console. Dile:

1. AWS Console → EC2 → Instances → seleccionar el EC2 → "Connect" → "EC2 Instance Connect"
2. Una vez en la terminal web del EC2:
   ```bash
   echo 'ssh-ed25519 AAAA... TU_KEY_NUEVA_AQUI' >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```
3. Cerrar la terminal web

Espera confirmación.

---

## Paso 5 — Configurar SSH config local

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
```

Verifica si ya hay entry para el EC2:
```bash
grep -q "Host ${EC2_HOST}" ~/.ssh/config 2>/dev/null && echo "Entry existe, lo actualizo" || echo "Creando nueva entry"
```

Agrega (o reemplaza) la entry. Usa Edit/Write para añadir a `~/.ssh/config`:

```
Host ec2 ${EC2_HOST}
    HostName ${EC2_HOST}
    User ${EC2_USER}
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 60
    ServerAliveCountMax 3
    # Fallback si MagicDNS de Tailscale falla:
    #   HostName <IP_TAILSCALE_DEL_PASO_2>
```

El alias `Host ec2` permite que el usuario teclee `ssh ec2` sin escribir el hostname completo. `Host ${EC2_HOST}` es el alias largo.

---

## Paso 6 — Test de conexión

Ahora prueba SSH crudo (sin claude):
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 ec2 'echo "✅ SSH funciona desde $(hostname) → $(uname -n)"' 2>&1
```

**Si funciona:** sigue al Paso 7.

**Si falla con `Permission denied`:** la SSH key no quedó autorizada. Vuelve al Paso 4 y verifica.

**Si falla con `Could not resolve hostname`:** Tailscale MagicDNS no está activo. Edita `~/.ssh/config` y reemplaza `HostName ${EC2_HOST}` por `HostName <IP_TAILSCALE>` (que guardaste en Paso 2).

**Si falla con `Connection refused`:** el sshd del EC2 no escucha en el IP Tailscale. Verifica que el security group de AWS permita Tailscale (usualmente no requiere abrir nada porque Tailscale es WireGuard interno).

---

## Paso 7 — Configurar aliases en shell del usuario

Detecta shell del usuario:
```bash
SHELL_RC="$HOME/.zshrc"
[ -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.bashrc"
echo "Editando: $SHELL_RC"
```

Agrega los siguientes aliases (usa Edit con append) si no existen ya:

```bash
# ─── Claude Code remoto en ${EC2_HOST} ───
# Sesión nueva (no persistente, se pierde si cierras laptop)
alias ec2='ssh -t ec2 "cd ${EC2_HOME} && claude"'

# Sesión persistente vía tmux (RECOMENDADA — sobrevive WiFi/laptop closes)
alias ec2-tmux='ssh -t ec2 "tmux new-session -A -s claude \"cd ${EC2_HOME} && claude\""'

# Reanudar última sesión (continúa donde quedaste)
alias ec2-continue='ssh -t ec2 "cd ${EC2_HOME} && claude --continue"'

# Menú de todas las sesiones previas
alias ec2-resume='ssh -t ec2 "cd ${EC2_HOME} && claude --resume"'

# Solo terminal del EC2 (sin claude — para correr comandos shell)
alias ec2-shell='ssh ec2'

# Sesiones tmux paralelas (independientes)
alias ec2-tmux-2='ssh -t ec2 "tmux new-session -A -s claude-2 \"cd ${EC2_HOME} && claude\""'
alias ec2-tmux-3='ssh -t ec2 "tmux new-session -A -s claude-3 \"cd ${EC2_HOME} && claude\""'
```

Guarda y recarga:
```bash
source $SHELL_RC
```

---

## Paso 8 — Persistir la configuración del skill

Guarda los valores que recolectaste para que futuras invocaciones del skill no pregunten de nuevo:

```bash
mkdir -p ~/.config/ec2-remote-access
cat > ~/.config/ec2-remote-access/config.env <<EOF
EC2_HOST=${EC2_HOST}
EC2_USER=${EC2_USER}
EC2_HOME=${EC2_HOME}
OS=${OS}
CONFIGURED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
chmod 600 ~/.config/ec2-remote-access/config.env
echo "✅ Config guardada en ~/.config/ec2-remote-access/config.env"
```

---

## Paso 9 — Smoke test final

Pide al usuario que abra una **nueva terminal** (para que cargue el `.zshrc`/`.bashrc` actualizado) y teclee:

```bash
ec2-tmux
```

Si todo está bien, ve el prompt de Claude Code en EC2. Le confirma:

> "Listo. Para usarlo en cualquier momento: abre cualquier terminal, teclea `ec2-tmux`, y estás dentro de Claude Code en tu EC2. Si se cae el WiFi o cierras la laptop, vuelve a teclear `ec2-tmux` y retomas exactamente donde quedaste."

Comandos cheat-sheet (muéstrale la tabla):

| Comando         | Qué hace                                                    |
|-----------------|-------------------------------------------------------------|
| `ec2`           | Sesión Claude nueva (no persistente)                        |
| `ec2-tmux`      | Sesión Claude persistente vía tmux (recomendada)            |
| `ec2-continue`  | Reanuda la sesión más reciente                              |
| `ec2-resume`    | Menú con todas las sesiones previas                         |
| `ec2-shell`     | Solo terminal en EC2, sin Claude                            |
| `ec2-tmux-2/3`  | Sesiones tmux paralelas independientes                      |

---

## Troubleshooting

### "Permission denied (publickey)"
- La SSH key no quedó autorizada en `~/.ssh/authorized_keys` del EC2. Vuelve al Paso 4.
- O el archivo tiene permisos incorrectos: `chmod 600 ~/.ssh/authorized_keys` en EC2.

### "Could not resolve hostname"
- Tailscale MagicDNS no está activo. Soluciones:
  - Activarlo: https://login.tailscale.com/admin/dns → toggle "MagicDNS"
  - O usar IP directo: edita `~/.ssh/config` y reemplaza `HostName <hostname>` por `HostName <IP_Tailscale>`

### "claude: command not found" tras hacer SSH
- Claude Code no está en el PATH cuando SSH ejecuta comandos no-interactivos.
- Fix rápido: edita el alias para incluir el path completo:
  ```bash
  alias ec2='ssh -t ec2 "/home/ec2-user/.local/share/fnm/node-versions/v24.14.0/installation/bin/claude"'
  ```
- Fix permanente (mejor): en el EC2, asegúrate que `~/.bashrc` exporta el PATH correcto y que `~/.bash_profile` carga `~/.bashrc`.

### Sesión tmux muere o no se re-adjunta
- Verifica que tmux esté instalado en EC2: `ssh ec2 'which tmux'`
- Si no: `ssh ec2 'sudo dnf install -y tmux'` (Amazon Linux) o `sudo apt install -y tmux` (Ubuntu)

### "Connection refused"
- El sshd del EC2 no acepta conexiones desde la IP de Tailscale.
- Verifica que sshd esté corriendo: `sudo systemctl status sshd` (desde otra forma de acceso al EC2)
- AWS Security Group no necesita cambios si usas Tailscale (es WireGuard, no SSH normal).

### "claude --continue" da "session locked"
- Otra terminal ya tiene esa sesión abierta. Cierra la otra o usa `claude --resume` para elegir una diferente.

---

## Notas de mantenimiento

- Si el hostname Tailscale del EC2 cambia (ej: renombras a `prod-2`): edita 3 lugares en orden:
  1. `~/.config/ec2-remote-access/config.env` → `EC2_HOST=nuevo-nombre`
  2. `~/.ssh/config` → `Host ec2 nuevo-nombre` + `HostName nuevo-nombre`
  3. Los aliases en `~/.zshrc` siguen funcionando automáticamente porque referencian `ssh ec2` (el alias corto)

- Para añadir OTRO EC2 al mismo setup (multi-instancia): copia el bloque de aliases con prefijo distinto: `ec2-staging`, `ec2-prod`, etc.

- Para revocar acceso desde una máquina antigua: borra la línea correspondiente de `~/.ssh/authorized_keys` en el EC2.

---

## Para Claude que ejecuta este skill

**Reglas operativas críticas:**

1. **Verifica antes de avanzar.** Cada paso tiene un check (grep, ls, ssh -o BatchMode). Si el check falla, NO avances — diagnostica.
2. **Nunca asumas valores.** Si el usuario no respondió a una pregunta del Paso 0, pregúntala antes de seguir.
3. **No bloques si la máquina ya está configurada.** Si `~/.config/ec2-remote-access/config.env` ya existe, ofrece "ya está configurado, ¿re-verificar o re-configurar?" en vez de re-correr todo.
4. **Sé conversacional, no recitar.** Después de cada paso, dile 1 frase corta sobre qué hiciste y qué viene. No leas el SKILL.md textual al usuario.
5. **Si el usuario está en Windows nativo (no WSL):** explícale que Claude Code se recomienda corra en WSL. Si insiste en PowerShell crudo, el flujo es similar pero los paths cambian (`%USERPROFILE%\.ssh\config`).
6. **NUNCA modifiques `~/.ssh/authorized_keys` del EC2 desde la máquina nueva.** El Paso 4 se hace desde una máquina YA autorizada o desde AWS Console — nunca desde la máquina nueva (porque por definición todavía no tiene acceso).
