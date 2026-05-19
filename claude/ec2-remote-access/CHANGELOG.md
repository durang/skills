# Changelog

Cada versión captura bugs encontrados en implementaciones reales + sus fixes. El skill se auto-mejora con cada uso.

## [1.0.0] — 2026-05-19

**Versión inicial canónica con 8 pasos completos** + self-healing via `verify.sh`.

### Added
- **`bootstrap.sh` step [7/8]**: instala `~/.config/systemd/user/claude-remote.service` que arranca Claude Code con `--remote-control <NAME>`. Hace que aparezca `<NAME>-Permanent` pinned en Claude Code Desktop.
- **`bootstrap.sh` step [8/8]**: pre-trustea `$HOME` en `~/.claude.json` para evitar que el prompt "Do you trust this folder?" bloquee el service en restarts.
- **`verify.sh`**: diagnóstico de los 8 pasos con auto-fix opcional (`--fix`). Idempotente. One-liner:
  ```
  curl -fsSL .../verify.sh | bash -s -- --fix
  ```
- **`TROUBLESHOOTING.md`**: documentación de los 8 bugs encontrados en implementaciones reales + sus fixes (`curl-minimal` conflict, trust prompt, dnf upgrade conflicts, single-binary layout, etc.).
- **VERSION constant** en `bootstrap.sh` para tracking.

### Fixed
- **Bug #1: `curl-minimal` vs `curl` conflict on Amazon Linux 2023** — eliminé `curl` de la lista de paquetes a instalar en step [2/8]. AL2023 trae `curl-minimal` que conflictúa, y curl siempre está presente (es lo que descargó el bootstrap).
- **Bug #2: full `dnf upgrade -y` aborta con conflictos** — cambiado a `dnf upgrade --security -y || true` (security only, tolera fallas). El `dnf-automatic` del step [3/8] maneja parches ongoing.
- **Bug #3: Single-binary Claude Code layout no detectado** — step [7/8] ahora prueba 4 paths en orden: `~/.local/bin/claude` (nuevo), node-resolved `claude.exe` (viejo), filesystem `find`, y `command -v claude` fallback.
- **Bug #4: trust dialog bloquea service en restarts** — step [8/8] pre-trustea `$HOME` en `~/.claude.json`.

### Documentación
- README reestructurado: **Modo SERVIDOR** ahora primario (era CLIENTE).
- Diagrama mental aclara: skill cubre AMBOS lados (servidor con bootstrap, cliente opcional con install.sh + skill SSH).

---

## Filosofía de versionado

- **Cada bug encontrado en mundo real → documentado en TROUBLESHOOTING.md + fixed en bootstrap.sh + entry en CHANGELOG.md**
- **El skill se auto-mejora con cada iteración**: el próximo usuario que instala recibe los fixes acumulados de todos los anteriores
- **Idempotente siempre**: re-correr bootstrap.sh nunca rompe nada, solo añade lo que falte
- **`verify.sh --fix` como red de seguridad**: detecta drift y lo arregla solo

---

## Cómo contribuir

Si encuentras un bug que no está aquí:

1. Captura output del bootstrap/verify donde falló
2. Abre issue en https://github.com/durang/ec2-remote-access/issues
3. Si tienes el fix, manda PR — incluye:
   - Cambio en `bootstrap.sh` (idempotente)
   - Cambio en `verify.sh` para detectarlo
   - Entry en `TROUBLESHOOTING.md` con síntoma + fix
   - Entry en `CHANGELOG.md` bajo nueva versión

Esto mantiene el skill como una memoria viva del estado-del-arte de "implementar Claude Code permanente en AWS EC2".
