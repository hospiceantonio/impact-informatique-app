#!/usr/bin/env bash
# =========================================================
# Ouvre les deux applications BIZZOO sur cet ordinateur.
#
#   bash tools/servir.sh          (port 5180)
#   bash tools/servir.sh 8000     (un autre port)
#
# Un simple serveur de fichiers : rien n'est compilé, rien
# n'est installé. Les deux applications sont du HTML, du CSS
# et du JavaScript — le navigateur les lit telles quelles,
# exactement comme le fera le serveur une fois en ligne.
#
# La base reste celle de Supabase, en ligne : ce qu'on
# enregistre ici est enregistré pour de bon.
#
# Ctrl+C pour arrêter.
# =========================================================
set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${1:-5180}"

bleu()  { printf '\033[36m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }
rouge() { printf '\033[31m%s\033[0m\n' "$*"; }

if ! command -v python3 >/dev/null 2>&1; then
  rouge "Python 3 est nécessaire pour ce petit serveur."
  echo "  Ubuntu/Debian : sudo apt-get install -y python3"
  echo "  macOS         : brew install python"
  echo "  Windows       : utilisez plutôt  .\\serve.ps1"
  exit 2
fi

# Un port déjà pris donne un message clair plutôt qu'une trace Python.
if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -q ":$PORT "; then
  rouge "Le port $PORT est déjà utilisé."
  echo "  Fermez l'autre fenêtre, ou choisissez un autre port :"
  echo "    bash tools/servir.sh 5181"
  exit 2
fi

echo
bleu "BIZZOO tourne sur cet ordinateur :"
echo
echo "   Accueil          http://localhost:$PORT/"
echo "   La boutique      http://localhost:$PORT/client/"
echo "   Espace admin     http://localhost:$PORT/admin/"
echo
gris "Astuce : réduisez la fenêtre du navigateur sous 1024 px de large"
gris "         pour voir exactement ce que voit un téléphone."
gris "Ctrl+C pour arrêter."
echo

cd "$RACINE"
# Écoute uniquement sur cette machine : rien n'est exposé au réseau.
exec python3 -m http.server "$PORT" --bind 127.0.0.1
