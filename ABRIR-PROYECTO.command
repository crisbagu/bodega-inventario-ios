#!/bin/bash
# Doble clic en este archivo: copia el proyecto a ~/Proyectos/Bodega y lo abre en Xcode.
cd "$(dirname "$0")" || exit 1
DEST="$HOME/Proyectos/Bodega"
mkdir -p "$DEST"
rsync -a --exclude 'Verificacion/Sources' --exclude '.DS_Store' ./ "$DEST"/ 2>/dev/null
echo "Proyecto copiado a: $DEST"
if [ -d "/Applications/Xcode.app" ]; then
  open -a Xcode "$DEST/Bodega.xcodeproj"
  echo "Abriendo Xcode..."
else
  echo ""
  echo "Xcode NO está instalado en este equipo."
  echo "Descárgalo gratis desde la Mac App Store (Xcode 16 o superior) y vuelve a hacer doble clic en este archivo."
  open "https://apps.apple.com/app/xcode/id497799835"
fi
