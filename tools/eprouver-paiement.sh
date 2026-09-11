#!/usr/bin/env bash
# =========================================================
# Éprouve les deux fonctions de paiement, SANS FeexPay.
#
# Le banc de la base (tools/eprouver-base.sh) monte un vrai
# PostgreSQL et force les portes de la base. Il ne voit rien
# des fonctions Edge : celles-ci tournent chez Supabase, en
# Deno, et parlent à FeexPay. C'est pourtant là qu'ont vécu
# les deux défauts de la première mise en service.
#
# Ici, FeexPay est une DOUBLURE : elle répond ce qu'on lui dit
# de répondre et note ce qu'on lui a envoyé. Aucun appel ne
# sort. Un banc qui dépendrait de leur API rougirait les jours
# de panne et ne prouverait rien les autres jours.
#
# Deno n'étant pas installable partout, les fonctions sont
# chargées par Node avec une doublure de « Deno » — même code,
# sans une ligne modifiée pour l'essai.
#
# Usage :  tools/eprouver-paiement.sh
# Sortie 0 : les portes tiennent. Sortie 1 : le message dit
# laquelle a cédé.
# =========================================================
set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BANC="$RACINE/supabase/functions/tests/feexpay.mjs"

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
