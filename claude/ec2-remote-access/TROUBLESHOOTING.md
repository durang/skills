# Troubleshooting — bugs encontrados y resueltos

Este documento captura **todos los errores reales** que surgieron durante implementaciones live de `/ec2-remote-access`, y cómo el bootstrap los soluciona automáticamente.

> **Cada bug descrito aquí ya está fixed en `bootstrap.sh`.** Si te aparece alguno de estos, corre `verify.sh --fix`.

---

## Tabla de bugs solucionados

| # | Síntoma | Causa raíz | Solucionado en |
|---|---------|------------|----------------|
| 1 | Pared de errores `curl-minimal vs curl conflict` durante install | AL2023 trae `curl-minimal` preinstalado, no convive con `curl` full | bootstrap.sh paso [2/8] |
| 2 | `dnf upgrade -y` falla en EC2 fresca con conflictos transitivos | Full upgrade arrastra paquetes que conflictúan | bootstrap.sh paso [1/8] |
| 3 | Paso [5/8] o [7/8] dice "Couldn't locate claude.exe" | Instalaciones nuevas usan `~/.local/bin/claude` (single ELF), no `claude.exe` | bootstrap.sh paso [7/8] |
| 4 | El service Remote Control se queda bloqueado en cada restart | "Trust this folder?" prompt sin nadie que presione Enter | bootstrap.sh paso [8/8] |
| 5 | "Stdin is not a TTY (running via curl\|bash). Exiting safely" | Bootstrap detecta correctamente que está como ssm-user efímero | Diseñado así (safe-exit) |
| 6 | `tmux new -s claude` → `duplicate session: claude` | Ya hay sesión tmux activa (el bootstrap ya la creó vía systemd) | Usa `tmux attach -t claude-remote` |
| 7 | `[ec2-user@...]$ tmux attach` → `no current client` o cuelga | Te conectas desde shell crudo y tmux requiere TTY | Es OK — accede vía Claude Code Desktop pinned |
| 8 | Session "EC2-Permanent" no aparece en Claude Code Desktop | Service no está activo, o cuentas distintas (cliente vs servidor) | `verify.sh --fix` + verificar cuenta Anthropic |

---

## Bug 1 — curl-minimal vs curl conflict

### Síntoma
Al correr `bootstrap.sh`, durante el paso [2/8] aparece:
```
package curl-minimal-X.Y.Z.amzn2023... conflicts with curl provided by curl-X.Y.Z
...
[40+ líneas de conflictos similares]
```

### Causa
Amazon Linux 2023 viene con `curl-minimal` (versión reducida) instalado por default. Si intentas instalar `curl` (full), dnf detecta el conflicto y aborta.

### Fix (ya aplicado)
- Step [1/8] usa `dnf upgrade --security -y || true` (security only, tolera fallas)
- Step [2/8] **eliminado `curl` de la lista** — siempre está presente vía `curl-minimal` (es lo que descargó este script)

### Comando manual si necesitas el fix retroactivamente
```bash
# Tu sistema ya tiene curl funcional. Solo continúa con el bootstrap.
curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/bootstrap.sh | bash
```

---

## Bug 2 — `dnf upgrade -y` falla en EC2 fresca

### Síntoma
Step [1/8] aborta con conflictos de dependencias transitivas, especialmente en EC2s recién lanzadas con repos cacheados.

### Causa
`dnf upgrade -y` intenta llevar TODOS los paquetes a la última versión disponible, arrastrando conflictos como el de curl-minimal.

### Fix (ya aplicado)
- Cambiado a `dnf upgrade --security -y || true` — solo parches de seguridad, tolera fallas
- El daemon `dnf-automatic` instalado en step [3/8] se encarga de mantener el sistema parchado posteriormente

---

## Bug 3 — "Couldn't locate claude.exe" en step [7/8]

### Síntoma
```
▶ [7/8] Installing Claude Code Remote Control systemd service
  ⚠️  Couldn't locate claude.exe — skipping Remote Control service
```

### Causa
Claude Code tiene **dos layouts de instalación**:
- **Layout viejo (node wrapper):** `~/.../node_modules/@anthropic-ai/claude-code/bin/claude.exe`
- **Layout nuevo (single binary):** `~/.local/bin/claude` (symlink a ELF en `~/.local/share/claude/versions/X.Y.Z`)

El bootstrap inicial solo buscaba `claude.exe`. Las instalaciones nuevas (2.1.145+) usan el layout nuevo → no encontraba binario → step 7 saltaba el service install.

### Fix (ya aplicado)
Bootstrap ahora prueba 4 paths en orden:
1. `~/.local/bin/claude` (stable symlink — preferido, sobrevive auto-updates)
2. `node -e "require.resolve('@anthropic-ai/claude-code')..."` (node-resolved)
3. `find ... -name claude.exe` (filesystem fallback)
4. `command -v claude` (PATH lookup)

---

## Bug 4 — Trust dialog bloquea service en cada restart

### Síntoma
Después de step [7/8], el systemd service arranca pero Claude Code se queda colgado en:
```
Do you trust the files in /home/ec2-user?
[Yes] / No
```

Sin nadie que presione Enter, el service queda bloqueado. En el siguiente reboot, mismo problema → `Restart=always` se vuelve inútil.

### Causa
Claude Code muestra un prompt de "trust this folder" la primera vez que abre un workspace. Si corre vía systemd (sin TTY interactivo), el prompt bloquea indefinidamente.

### Fix (ya aplicado)
Step [8/8] añadido: pre-trusta `$HOME` en `~/.claude.json`:
```python
projects[$HOME]["hasTrustDialogAccepted"] = True
projects[$HOME]["hasCompletedProjectOnboarding"] = True
```
Y restart automático del service para aplicar el trust.

### Comando manual si necesitas hacerlo retroactivamente
```bash
python3 -c "
import json
from pathlib import Path
path = Path.home() / '.claude.json'
d = json.loads(path.read_text())
home = str(Path.home())
d.setdefault('projects', {}).setdefault(home, {})['hasTrustDialogAccepted'] = True
d['projects'][home]['hasCompletedProjectOnboarding'] = True
path.write_text(json.dumps(d, indent=2))
"
systemctl --user restart claude-remote.service
```

O simplemente: `bash <(curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/verify.sh) --fix`

---

## Bug 5 — "Stdin is not a TTY (running via curl|bash)"

### Síntoma
```
⚠️  You're running as ssm-user (ephemeral, not ideal for workspace)
   Switch first with: sudo su - ec2-user
Stdin is not a TTY (running via curl|bash). Exiting safely.
```

### Causa
Esto es **diseño correcto**, no un bug. El bootstrap detecta que estás como `ssm-user` (usuario efímero de SSM Session Manager) y se sale de forma segura sin instalar workspace bajo ese usuario.

### Fix
Haz lo que dice el mensaje:
```bash
sudo su - ec2-user
curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/bootstrap.sh | bash
```

---

## Bug 6 — `tmux new -s claude` → "duplicate session: claude"

### Síntoma
Después de un bootstrap exitoso, intentas crear una sesión tmux para Claude y dice que ya existe.

### Causa
El service `claude-remote.service` YA creó una sesión tmux llamada `claude-remote` (o `claude` en versiones anteriores). La pelea por el mismo nombre.

### Fix
**No necesitas crear una sesión tmux manualmente.** El service ya hace todo:
```bash
tmux attach -t claude-remote   # ver lo que el service está corriendo
```

Pero el flujo canónico es: NO toques tmux directamente. Abre Claude Code Desktop → sidebar Pinned → `<NAME>-Permanent` → entras al Claude remoto.

---

## Bug 7 — `tmux attach` en SSH se ve raro

### Síntoma
Te conectas vía SSM Session Manager (como ssm-user), haces `sudo su - ec2-user` y luego `tmux attach -t claude-remote`. Ves la sesión pero no responde bien a inputs.

### Causa
Múltiples clientes attached a la misma sesión tmux. O TTY incompatibilities.

### Fix
**No uses tmux attach desde SSM.** El acceso correcto es vía **Claude Code Desktop** (sidebar Pinned). El service maneja el tmux internamente.

Si necesitas debuggear desde SSM:
```bash
journalctl --user -u claude-remote.service -f   # ver logs del service
systemctl --user status claude-remote.service   # estado del service
```

---

## Bug 8 — Session no aparece en Claude Code Desktop

### Síntoma
El service está activo (`systemctl status` ok), pero en Claude Code Desktop / claude.ai/code no aparece `<NAME>-Permanent` en el sidebar Pinned.

### Causas posibles

#### A) Cuentas Anthropic distintas
El service en el EC2 está autenticado con CuentaA, pero estás abriendo Desktop con CuentaB. Las Remote Control sessions están atadas a la cuenta logueada.

**Verifica:**
```bash
# En el EC2
cat ~/.claude/.credentials.json | python3 -c "import sys,json; print(json.load(sys.stdin).get('account',{}).get('email','?'))"

# En tu Desktop / Web
# Settings → Account → ver email logueado
```

Deben ser **la misma cuenta**.

#### B) Service no está realmente activo
```bash
systemctl --user status claude-remote.service   # debe decir "active (running)"
journalctl --user -u claude-remote.service -n 30   # últimos logs
```

#### C) Claude Code en el EC2 no terminó de autenticar
Si nunca completaste el `claude` interactive login en el EC2, el service se queda esperando credentials.

**Fix:**
```bash
# En el EC2 (como ec2-user)
claude
# Sigue el flujo de OAuth (URL → browser → paste code)
# Ctrl+C después de ver el prompt
systemctl --user restart claude-remote.service
```

---

## Comando de oro — "arregla todo automáticamente"

Si tienes CUALQUIER duda sobre el estado del setup:

```bash
curl -fsSL https://raw.githubusercontent.com/durang/ec2-remote-access/master/verify.sh | bash -s -- --fix
```

Eso corre los 8 chequeos, te dice cuáles fallan, y arregla automáticamente todo lo que sea automatizable. Idempotente, seguro.

---

## Reportar nuevos bugs

Si encuentras un bug nuevo que no está aquí:

1. Captura el output completo del bootstrap o verify
2. Abre issue en https://github.com/durang/ec2-remote-access/issues
3. Idealmente con steps to reproduce

Cada bug encontrado en el mundo real se documenta aquí + se fixea en el bootstrap → la siguiente persona que instale ya no lo sufre.
