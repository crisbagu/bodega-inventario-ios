#!/bin/bash
# Doble clic en este archivo: descarga la app compilada y te la deja lista para instalar.
# No necesitas Xcode. La firma la hace tu cuenta de Apple gratuita (dura 7 días).

set -u
URL_IPA="{{URL_IPA}}"
DESTINO="$HOME/Descargas"
NOMBRE="Bodega-unsigned.ipa"

echo ""
echo "  🍷  Bodega · instalador"
echo "  ────────────────────────────────"
echo ""

if [ ! -f "$URL_IPA" ]; then
  echo "  ✖️  El enlace de descarga aún no está configurado."
  echo "      Se rellenará en cuanto el proyecto esté publicado en GitHub."
  echo ""
  read -r -p "  Pulsa Intro para cerrar." _
  exit 1
fi

mkdir -p "$DESTINO"
echo "  ⬇️  Descargando la app…"
if ! curl -fL --progress-bar -o "$DESTINO/$NOMBRE" "$URL_IPA"; then
  echo "  ✖️  No se pudo descargar. Revisa tu conexión."
  read -r -p "  Pulsa Intro para cerrar." _
  exit 1
fi

echo "  ✅  Descargada en: $DESTINO/$NOMBRE"
echo ""

if [ -d "/Applications/Sideloadly.app" ]; then
  echo "  🚀  Abriendo Sideloadly con la app…"
  open -a Sideloadly "$DESTINO/$NOMBRE"
  echo "      En Sideloadly: escribe tu Apple ID → Start."
elif [ -d "/Applications/AltStore.app" ]; then
  echo "  🚀  Abriendo AltStore con la app…"
  open -a AltStore "$DESTINO/$NOMBRE"
  echo "      En AltStore: ⋮ → Install → escribe tu Apple ID → Install."
else
  echo "  📦  No encontré Sideloadly ni AltStore."
  echo "      1. Instala AltStore en el iPhone (App Store) o Sideloadly en la Mac."
  echo "      2. Abre la app descargada con AltStore o arrástrala a Sideloadly."
fi

echo ""
echo "  💡  En el iPhone, la primera vez, activa el Modo desarrollador:"
echo "      Ajustes → Privacidad y seguridad → Modo desarrollador."
echo ""
read -r -p "  Pulsa Intro para cerrar." _
