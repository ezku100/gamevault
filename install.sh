#!/usr/bin/env bash
# Instalador 1-clic para Game Vault (Plasma 6)
set -e
cd "$(dirname "$0")"

pkg="com.ezku.gamevault"
if kpackagetool6 -t Plasma/Applet -u "$pkg"; then
  echo "↻ $pkg actualizado."
else
  echo "＋ Instalando $pkg..."
  kpackagetool6 -t Plasma/Applet -i "$pkg"
fi

echo ""
echo "Listo. Ahora clic derecho en panel/escritorio → Añadir widgets → busca 'Game Vault'."
echo "Atajo sugerido: Meta+Ctrl+G (clic derecho al widget → Configurar → Atajos)."
echo "Si no aparece, reinicia: nohup plasmashell --replace >/tmp/plasmashell.log 2>&1 &"
