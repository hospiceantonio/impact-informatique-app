#!/usr/bin/env bash
# =========================================================
# Éprouve le transport SMS, SANS CREATISINTER.
#
# Deux portes vivent ici, et aucune des deux ne se voit à la
# relecture.
#
# LA PREMIÈRE EST UN MENSONGE POLI : la passerelle répond
# « HTTP 200 » en portant l'échec dans le corps. Un envoi
# manqué ressemble alors trait pour trait à un envoi réussi.
#
# LA SECONDE EST UNE PORTE OUVERTE : le hook de Supabase Auth
# se déploie sans vérification de jeton, et sa signature est
# le seul contrôle. Sans elle, n'importe qui fait envoyer des
# SMS aux frais de l'enseigne jusqu'à épuisement du crédit.
#
# Ici, CREATISINTER est une DOUBLURE : elle répond ce qu'on lui
# dit de répondre et note ce qu'on lui a envoyé. Aucun appel ne
# sort, et aucun SMS n'est facturé.
#
# Deno n'étant pas installable partout, les fonctions sont
# chargées par Node avec une doublure de « Deno » — même code,
# sans une ligne modifiée pour l'essai.
#
# Usage :  tools/eprouver-sms.sh
# Sortie 0 : les portes tiennent. Sortie 1 : le message dit
# laquelle a cédé.
# =========================================================
set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BANC="$RACINE/supabase/functions/tests/sms.mjs"

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
