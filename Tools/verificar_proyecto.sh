#!/bin/bash
# Verificación completa del proyecto (no necesita Xcode):
#  1. sintaxis de cada archivo Swift
#  2. genera el .xcodeproj y lo valida con plutil
#  3. compila y ejecuta las pruebas de la lógica en macOS
set -u
cd "$(dirname "$0")/.."
RAIZ=$(pwd)
FALLOS=0

echo "=== 1. Sintaxis Swift ==="
while IFS= read -r f; do
  if ! swiftc -parse "$f" 2>/tmp/err_parse.txt; then
    echo "FALLO DE SINTAXIS: $f"
    head -5 /tmp/err_parse.txt
    FALLOS=$((FALLOS+1))
  fi
done < <(find Bodega BodegaTests -name '*.swift' 2>/dev/null | sort)
TOTAL=$(find Bodega BodegaTests -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')
echo "Archivos analizados: $TOTAL | fallos: $FALLOS"

echo
echo "=== 2. Proyecto Xcode ==="
python3 Tools/generar_xcodeproj.py || FALLOS=$((FALLOS+1))
if plutil -lint Bodega.xcodeproj/project.pbxproj; then
  echo "pbxproj válido"
else
  echo "pbxproj INVÁLIDO"; FALLOS=$((FALLOS+1))
fi

echo
echo "=== 3. Pruebas de la lógica (macOS) ==="
set -o pipefail
bash Verificacion/sincronizar.sh 2>&1 | grep -E "PASS|FAIL|FALLOS|TODO|error:" || FALLOS=$((FALLOS+1))
RESULTADO_PRUEBAS=${PIPESTATUS[0]:-0}
if [ "$RESULTADO_PRUEBAS" != "0" ]; then FALLOS=$((FALLOS+1)); fi

echo
if [ "$FALLOS" -eq 0 ]; then
  echo "VERIFICACIÓN: todo correcto"
else
  echo "VERIFICACIÓN: $FALLOS problema(s)"
fi
exit $FALLOS
