#!/usr/bin/env bash
# =========================================================
# Éprouve le script de ménage du stockage.
#
# Ce script-là EFFACE DES FICHIERS, et une suppression ne se
# rattrape pas. Il mérite donc mieux qu'une relecture : on lui
# donne un faux Supabase, on regarde ce qu'il lui envoie
# vraiment, et on vérifie qu'il ne touche que ce qu'il doit.
#
# Un défaut trouvé ainsi : le script supprimait tout dans le
# seau « produits », alors que la liste des orphelins couvre
# TOUS les seaux. Un orphelin du seau « slider » aurait fait
# effacer, dans « produits », un fichier de même chemin — bien
# vivant, lui.
#
# Usage :  tools/eprouver-menage.sh
# Sortie 0 : le ménage ne déborde pas. Sortie 1 : le message
# dit ce qui a débordé.
# =========================================================
set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOCLE="${TMPDIR:-/tmp}/bizzoo-menage-$$"
PORT="${PORT_ESSAI_MENAGE:-5199}"

rouge() { printf '\033[31m%s\033[0m\n' "$*"; }
vert()  { printf '\033[32m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }

command -v pwsh   >/dev/null 2>&1 || { gris "PowerShell absent : étape sautée."; exit 0; }
command -v python3 >/dev/null 2>&1 || { gris "Python absent : étape sautée."; exit 0; }

nettoyer() { touch "$SOCLE/stop" 2>/dev/null || true; sleep 0.5; rm -rf "$SOCLE"; }
trap nettoyer EXIT

mkdir -p "$SOCLE/tools" "$SOCLE/client"
cp "$RACINE/tools/menage-stockage.ps1" "$SOCLE/tools/"

# ---------- Le faux Supabase ----------
# Il note ce qu'on lui envoie, et refuse « enseigne/ » comme le font les
# vraies règles pour un compte qui n'est pas superadministrateur.
cat > "$SOCLE/serveur.py" <<'PY'
import json, os, sys, time, threading, http.server
SOCLE, PORT = sys.argv[1], int(sys.argv[2])
recu = []
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _lire(self):
        return self.rfile.read(int(self.headers.get('Content-Length') or 0)).decode()
    def _rep(self, code, corps):
        b = json.dumps(corps).encode()
        self.send_response(code); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        self._lire()
        if '/auth/v1/token' in self.path: self._rep(200, {"access_token": "jeton-essai"})
        else: self._rep(404, {})
    def do_DELETE(self):
        corps = self._lire()
        chemins = json.loads(corps)['prefixes']
        recu.append({"seau": self.path.rsplit('/', 1)[-1], "chemins": chemins, "brut": corps})
        self._rep(200, [{"name": c} for c in chemins if not c.startswith('enseigne/')])
srv = http.server.HTTPServer(('127.0.0.1', PORT), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
while not os.path.exists(os.path.join(SOCLE, 'stop')): time.sleep(0.2)
json.dump(recu, open(os.path.join(SOCLE, 'recu.json'), 'w'))
PY

cat > "$SOCLE/client/config.js" <<EOF
const CONFIG = {
  SUPABASE_URL: "http://127.0.0.1:$PORT",
  SUPABASE_ANON_KEY: "cle-anon-essai",
};
EOF

# ---------- La liste, avec ses pièges ----------
cat > "$SOCLE/liste.csv" <<'EOF'
section,quoi,détail 1,détail 2,détail 3
TOTAL,tout le stockage,530 fichier(s),297 MB,sur 1 Go (offre gratuite) : 29.0 %
PLUS GROS,produits/bou_impact/photo-en-ligne.jpg,image/jpeg,3 MB,2026-03-01
ORPHELINS,produits/bou_impact/photo-ancienne.jpg,1224 kB,2026-03-04,plus référencé
ORPHELINS,produits/bou_impact/vieille-video.mp4,12 MB,2026-02-11,plus référencé
ORPHELINS,slider/accueil/banniere-2025.png,340 kB,2026-01-20,plus référencé
ORPHELINS,produits/enseigne/logo-retire.png,88 kB,2026-01-02,plus référencé
ORPHELINS,chemin-sans-seau.jpg,10 kB,2026-01-02,plus référencé
ORPHELINS,"produits/bou_impact/vil""ain.jpg",10 kB,2026-01-02,plus référencé
EOF

# ---------- La doublure de Read-Host ----------
# Le script n'est pas modifié d'une ligne : c'est la question qu'on
# double, pas la réponse qu'on contourne.
cat > "$SOCLE/avec-reponses.ps1" <<'PS'
function Read-Host {
  param([string]$Prompt, [switch]$AsSecureString)
  $script:rang++
  $r = @('SUPPRIMER', 'patron@bizzoo.bj', 'motdepasse')[$script:rang - 1]
  if ($AsSecureString) { return (ConvertTo-SecureString $r -AsPlainText -Force) }
  return $r
}
$script:rang = 0
& $args[0] -Csv $args[1]
exit $LASTEXITCODE
PS

ECHECS=0
constat() {
  if [ "$1" = "oui" ]; then echo "  ok    $2"
  else printf '\033[31m  ÉCHEC %s\033[0m\n' "$2"; ECHECS=$((ECHECS + 1)); fi
}
dedans() { grep -qF "$2" "$1" && echo oui || echo non; }

gris "Ménage du stockage — Supabase est une doublure, rien ne sort d'ici."

# ---------- 1. La simulation ne touche à rien ----------
echo
echo "== La simulation montre, et ne touche à rien"
rm -f "$SOCLE/stop" "$SOCLE/recu.json"
python3 "$SOCLE/serveur.py" "$SOCLE" "$PORT" & SERVEUR=$!
sleep 1
pwsh -NoProfile -File "$SOCLE/tools/menage-stockage.ps1" \
  -Csv "$SOCLE/liste.csv" -Simulation > "$SOCLE/sim.txt" 2>&1 || true

constat "$(dedans "$SOCLE/sim.txt" 'seau « produits » - 3 fichier(s)')" \
  "les orphelins sont groupés par seau"
constat "$(dedans "$SOCLE/sim.txt" 'seau « slider » - 1 fichier(s)')" \
  "y compris un seau qui n'a qu'un fichier"
constat "$(dedans "$SOCLE/sim.txt" 'chemin-sans-seau.jpg')" \
  "une ligne sans seau est écartée, pas devinée"
constat "$(dedans "$SOCLE/sim.txt" 'vil"ain.jpg')" \
  "un chemin au format inattendu est écarté plutôt qu'échappé"
constat "$([ "$(grep -c 'photo-en-ligne' "$SOCLE/sim.txt" || true)" = 0 ] && echo oui || echo non)" \
  "les lignes qui ne sont pas des orphelins sont ignorées"
constat "$(dedans "$SOCLE/sim.txt" "rien n'a ete supprime")" "et rien n'est supprimé"

# ---------- 2. Une liste périmée ne sert pas de liste de suppression ----------
echo
echo "== Une liste périmée ne sert pas de liste de suppression"
touch -d "3 days ago" "$SOCLE/liste.csv" 2>/dev/null || touch -t "$(date -v-3d +%Y%m%d%H%M 2>/dev/null || echo 202601010000)" "$SOCLE/liste.csv"
set +e
pwsh -NoProfile -File "$SOCLE/tools/menage-stockage.ps1" -Csv "$SOCLE/liste.csv" > "$SOCLE/vieux.txt" 2>&1
SORTIE=$?
set -e
constat "$([ "$SORTIE" = 2 ] && echo oui || echo non)" \
  "un CSV de trois jours est refusé (sortie $SORTIE)"
constat "$(dedans "$SOCLE/vieux.txt" "peut etre affiche dans la boutique aujourd'hui")" \
  "et le refus dit pourquoi : un orphelin d'hier peut être en ligne"
touch "$SOCLE/liste.csv"

# ---------- 3. La suppression, seau par seau ----------
echo
echo "== La suppression va dans le bon seau"
pwsh -NoProfile -File "$SOCLE/avec-reponses.ps1" \
  "$SOCLE/tools/menage-stockage.ps1" "$SOCLE/liste.csv" > "$SOCLE/vrai.txt" 2>&1 || true
touch "$SOCLE/stop"; wait "$SERVEUR" 2>/dev/null || true

RECU="$SOCLE/recu.json"
lire() { python3 -c "import json,sys; print(json.dumps($1))" 2>/dev/null || echo '"illisible"'; }
APPELS="$(python3 - "$RECU" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
print(json.dumps({a["seau"]: a["chemins"] for a in r}, sort_keys=True))
PY
)"
constat "$([ "$APPELS" = '{"produits": ["bou_impact/photo-ancienne.jpg", "bou_impact/vieille-video.mp4", "enseigne/logo-retire.png"], "slider": ["accueil/banniere-2025.png"]}' ] && echo oui || echo non)" \
  "chaque chemin part dans SON seau, et pas ailleurs"

BRUT="$(python3 -c "import json,sys; print([a['brut'] for a in json.load(open('$RECU')) if a['seau']=='slider'][0])")"
constat "$([ "$BRUT" = '{"prefixes":["accueil/banniere-2025.png"]}' ] && echo oui || echo non)" \
  "un seul fichier part quand même dans une LISTE, pas une chaîne"

constat "$(dedans "$SOCLE/vrai.txt" '3 fichier(s) supprime(s)')" \
  "trois partent, et le quatrième est refusé par les règles"
constat "$(dedans "$SOCLE/vrai.txt" 'produits/enseigne/logo-retire.png')" \
  "le refus nomme le fichier AVEC son seau"

echo
if [ "$ECHECS" -gt 0 ]; then
  rouge "$ECHECS constat(s) en échec : le ménage déborde."
  exit 1
fi
vert "Le ménage ne touche que ce qu'on lui a désigné, dans le bon seau ✔"
