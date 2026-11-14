#!/usr/bin/env bash
# =========================================================
# Allège les images produites par les outils (4.3.1) : les icônes des
# applications (client, admin, personnel), leurs icônes Android et les
# pictogrammes des catégories.
#
# Le logo B de la 4.3.0 est une image riche (dégradés, reflets) : écrite
# telle quelle, chaque icône 512 pesait 345 Ko, et les APK comme le site
# avaient pris 1,3 Mo et 5,7 Mo. pngquant les réduit à une palette de
# 256 couleurs, transparence comprise : quatre fois plus légères, et la
# différence ne se voit pas. « --quality=80-95 » : si cette qualité ne
# peut être tenue, l'image est laissée telle quelle ; « --skip-if-larger »
# ne remplace jamais une image par une plus lourde.
#
# Lancé à la fin de tools/make-icons.js et de tools/recolorer-pictos.mjs.
# Sans pngquant, rien n'est perdu : les images restent justes, seulement
# plus lourdes (le script le dit).
#
#   bash tools/alleger-images.sh
# =========================================================
set -uo pipefail
cd "$(dirname "$0")/.."

if ! command -v pngquant >/dev/null 2>&1; then
  echo "pngquant est absent : images NON allégées (sudo apt-get install pngquant)." >&2
  exit 0
fi

avant=0; apres=0; n=0
while IFS= read -r -d '' f; do
  t0=$(stat -c%s "$f")
  pngquant --quality=80-95 --speed 1 --strip --skip-if-larger --force --output "$f" -- "$f" 2>/dev/null
  t1=$(stat -c%s "$f")
  avant=$((avant + t0)); apres=$((apres + t1)); n=$((n + 1))
done < <(find client/icons admin/icons personnel/icons client/img/pictos admin/img/pictos \
           android/app/src/client/res android/app/src/admin/res \
           -name '*.png' -print0 2>/dev/null)

echo "$n images allégées : $((avant / 1024)) Ko -> $((apres / 1024)) Ko."
