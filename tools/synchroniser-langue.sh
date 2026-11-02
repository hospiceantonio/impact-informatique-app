#!/usr/bin/env bash
# Recopie client/js/langue.js (l'original) dans les autres applications et
# dans la vitrine, à l'identique. Les bancs vérifient que les copies sont
# identiques : modifier l'original, puis lancer ce script.
set -euo pipefail
cd "$(dirname "$0")/.."
for cible in admin/js/langue.js personnel/js/langue.js vitrine/langue.js; do
  cp client/js/langue.js "$cible"
done
echo "langue.js recopié dans admin, personnel et vitrine."
