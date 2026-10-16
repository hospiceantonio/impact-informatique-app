#!/usr/bin/env bash
# =========================================================
# Éprouve l'annonce d'un live TikTok, SANS Google ni Firebase.
#
# Google, Firebase et la base sont des DOUBLURES : aucun appel ne
# sort, aucune notification n'arrive sur un téléphone.
#
# Deno n'étant pas installable partout, les fonctions sont
# chargées par Node avec une doublure de « Deno » — même code,
# sans une ligne modifiée pour l'essai.
#
# Usage :  tools/eprouver-live.sh
# Sortie 0 : les portes tiennent. Sortie 1 : le message dit
# laquelle a cédé.
# =========================================================
set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BANC="$RACINE/supabase/functions/tests/live.mjs"

rouge() { printf '\033[31m%s\033[0m\n' "$*"; }

command -v node >/dev/null 2>&1 || { rouge "Node.js introuvable."; exit 2; }

# Le typage s'efface à la lecture : il faut Node 22.6 ou plus récent.
MAJEUR="$(node -p 'process.versions.node.split(".")[0]')"
MINEUR="$(node -p 'process.versions.node.split(".")[1]')"
if [ "$MAJEUR" -lt 22 ] || { [ "$MAJEUR" -eq 22 ] && [ "$MINEUR" -lt 6 ]; }; then
  rouge "Node $(node -v) : il faut 22.6 ou plus récent pour lire le TypeScript."
  exit 2
fi

cd "$(dirname "$BANC")"
exec node --experimental-strip-types --no-warnings "$(basename "$BANC")"
