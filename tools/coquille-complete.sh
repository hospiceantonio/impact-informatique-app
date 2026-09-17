#!/usr/bin/env bash
# =========================================================
# Le service worker connaît-il TOUS les fichiers de l'application ?
#
# Les deux applications s'ouvrent hors connexion : leur
# « coquille » — HTML, CSS, scripts — est mise en cache par le
# service worker, qui en tient la liste À LA MAIN.
#
# Une liste tenue à la main finit par mentir. C'est arrivé :
# « compte.js » et « vues/compte.js » ont vécu deux étapes hors
# de la liste. En ligne, rien ne se voyait — le navigateur les
# chargeait par le réseau. Hors connexion, « Compte » n'était pas
# défini et l'application s'ouvrait cassée, sur le seul écran où
# l'on ne peut rien réparer.
#
# Ce contrôle compare les balises « script » de index.html à la
# liste du service worker, dans les deux sens : un script absent
# de la liste NE SERA PAS mis en cache ; un fichier listé qui
# n'existe plus fait échouer « cache.addAll » ENTIÈREMENT — et
# donc le cache tout entier, en silence.
#
# Usage :  tools/coquille-complete.sh
# Sortie 0 : les deux listes coïncident. Sortie 1 : le message
# dit quel fichier manque, et où.
# =========================================================
set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rouge() { printf '\033[31m%s\033[0m\n' "$*"; }
vert()  { printf '\033[32m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }

ECHECS=0

verifier() {
  local app="$1"
  local html="$RACINE/$app/index.html"
  local sw="$RACINE/$app/sw.js"
  [ -f "$html" ] && [ -f "$sw" ] || { gris "$app : pas de service worker, ignoré."; return 0; }

  # Les scripts que la page charge vraiment, chemins relatifs seulement.
  local scripts liste
  scripts="$(grep -o 'src="[^"]*\.js"' "$html" | sed 's/src="//; s/"//' \
             | grep -v '^https\?://' | sort -u)"
  # Ce que le service worker promet de garder.
  liste="$(sed -n '/^const FICHIERS = \[/,/^\];/p' "$sw" \
           | grep -o '"\./[^"]*"' | sed 's/"\.\///; s/"//' | sort -u)"

  local manquants=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    grep -qxF "$f" <<<"$liste" || manquants+="  $f"$'\n'
  done <<<"$scripts"

  # Et l'inverse : un fichier listé qui n'existe plus fait échouer
  # « cache.addAll » en entier, donc le cache complet.
  local fantomes=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in "") continue;; esac
    [ -e "$RACINE/$app/$f" ] || fantomes+="  $f"$'\n'
  done <<<"$liste"

  if [ -n "$manquants" ] || [ -n "$fantomes" ]; then
    rouge "$app/sw.js ne décrit pas l'application :"
    [ -n "$manquants" ] && {
      echo "  Chargés par index.html mais ABSENTS de la liste —"
      echo "  ils ne seront pas mis en cache, et manqueront hors connexion :"
      printf '%s' "$manquants"
    }
    [ -n "$fantomes" ] && {
      echo "  Listés mais INTROUVABLES sur le disque —"
      echo "  « cache.addAll » échouera en entier, et rien ne sera gardé :"
      printf '%s' "$fantomes"
    }
    ECHECS=$((ECHECS + 1))
  else
    gris "$app : $(wc -l <<<"$scripts") script(s), tous dans la coquille."
  fi
}

verifier client
verifier admin

echo
if [ "$ECHECS" -gt 0 ]; then
  rouge "La coquille hors connexion est incomplète."
  exit 1
fi
vert "Les deux applications s'ouvriront hors connexion au complet ✔"
