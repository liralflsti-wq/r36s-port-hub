#!/bin/sh
# Gera r36sporthub/game.love e o pacote final para copiar em /roms/ports
# Uso: tools/build.sh [--dev]   (--dev inclui o roteiro de testes automaticos)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build"
rm -rf "$OUT"
mkdir -p "$OUT/ports"
cp -a "$ROOT/port/." "$OUT/ports/"
cd "$ROOT/src"
if [ "$1" = "--dev" ]; then EXCL=""; else EXCL="dev/*"; fi
rm -f "$OUT/ports/r36sporthub/game.love"
zip -q -9 -n .ogg -r "$OUT/ports/r36sporthub/game.love" . -x "$EXCL"
chmod +x "$OUT/ports/R36S PORT HUB.sh" "$OUT/ports/r36sporthub/bin/fetch.sh" "$OUT/ports/r36sporthub/bin/es_theme_apply.sh" "$OUT/ports/r36sporthub/tools/R36S_Analog_Tester.sh"
# manifesto (versao + SHA-256 de cada arquivo): o pacote completo tambem pode
# ser instalado pela Atualizacao local do proprio hub
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/tools/make_update.py" full "$OUT/ports" >/dev/null
fi
cd "$OUT/ports"
rm -f "$OUT/R36S-PORT-HUB-BETA.zip"
zip -q -9 -r "$OUT/R36S-PORT-HUB-BETA.zip" "R36S PORT HUB.sh" r36sporthub $( [ -f update_manifest.json ] && echo update_manifest.json )
echo "Pacote: $OUT/R36S-PORT-HUB-BETA.zip"
