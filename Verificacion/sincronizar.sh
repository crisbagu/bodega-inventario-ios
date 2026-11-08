#!/bin/bash
# Copia las fuentes de dominio (Core + Vision) al arnés macOS y ejecuta las pruebas.
# Excluye Modelos.swift y DatosSemilla.swift: usan las macros @Model de SwiftData,
# cuyo plugin de compilación solo existe dentro de Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."
DEST="Verificacion/Sources/Verificacion"
rm -rf "$DEST"
mkdir -p "$DEST"
for f in Bodega/Core/*.swift; do
  case "$f" in
    *Modelos.swift|*DatosSemilla.swift) continue ;;
  esac
  cp "$f" "$DEST"/
done
cp Bodega/Vision/*.swift "$DEST"/ 2>/dev/null || true
cp Verificacion/Verificacion.swift "$DEST"/main.swift
echo "Sincronizadas $(ls -1 "$DEST" | wc -l | tr -d ' ') fuentes a $DEST"
cd Verificacion
swift run Verificacion
