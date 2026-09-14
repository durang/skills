#!/usr/bin/env bash
# Instala/actualiza el hook signal-detector en ESTA máquina.
#
# POR QUÉ EXISTE: el hook NO lo instala el install.sh del monorepo (ese sólo
# copia skills según `distribute-to:`). Se copiaba a mano, así que la Mac se
# quedó con una versión anterior a `ALLOWED_NAMESPACES` (fix de 2026-07-25) y
# siguió escribiendo slugs SIN namespace. gbrain usa el slug entero como
# page type ⇒ 163 tipos basura y el doctor en 0/100 (limpiado 2026-09-14).
#
# Idempotente: si ya está la versión correcta, no toca nada.
set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook/signal-detector.py"
DEST="$HOME/.gbrain/hooks/signal-detector.py"
SETTINGS="$HOME/.claude/settings.json"

[ -f "$SRC" ] || { echo "✗ no encuentro el hook en $SRC"; exit 1; }

# El fix imprescindible: sin esta constante el hook escribe slugs sin namespace.
if ! grep -q "ALLOWED_NAMESPACES" "$SRC"; then
    echo "✗ el hook de origen NO tiene ALLOWED_NAMESPACES — repo desactualizado, haz git pull"
    exit 1
fi

mkdir -p "$(dirname "$DEST")"
if [ -f "$DEST" ] && cmp -s "$SRC" "$DEST"; then
    echo "✓ hook ya al día ($(wc -c < "$DEST") bytes)"
else
    [ -f "$DEST" ] && cp "$DEST" "$DEST.bak-$(date +%Y%m%d%H%M%S)"
    cp "$SRC" "$DEST"; chmod 700 "$DEST"
    echo "✓ hook actualizado -> $DEST"
fi

# Registro en el Stop hook de Claude Code (si no está, avisar — no editar a ciegas)
if [ -f "$SETTINGS" ] && grep -q "signal-detector" "$SETTINGS"; then
    echo "✓ registrado como Stop hook en $SETTINGS"
else
    echo "⚠️  falta registrarlo en $SETTINGS (hooks.Stop):"
    echo '    {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"python3 '"$DEST"'"}]}]}}'
fi

echo
echo "Verificación: tras una sesión, revisa ~/.gbrain/hooks/signal-detector.log"
echo "Los slugs escritos DEBEN llevar namespace (decisions/..., concepts/...)."
