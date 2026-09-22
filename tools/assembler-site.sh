#!/usr/bin/env bash
# =========================================================
#  Assembler le site public — ce qui part en ligne, et RIEN d'autre
# =========================================================
#  UNE LISTE BLANCHE, PAS UNE LISTE NOIRE. L'assemblage d'avant copiait
#  tout le dépôt sauf quelques dossiers : le README (l'architecture, la
#  place de chaque secret), le dossier skills/ (le code d'intégration du
#  paiement) et le lanceur Windows partaient en ligne avec le reste. Et
#  un fichier ajouté demain au dépôt serait parti de même, sans que
#  personne ne l'ait décidé. Ici, n'est publié que ce qui est nommé.
#
#  Deux usages :
#
#    bash tools/assembler-site.sh [dossier]
#        le site de GitHub Pages (par défaut dans _site/) ;
#
#    bash tools/assembler-site.sh --hebergement [fichier.zip]
#        le même site, plus le .htaccess d'un hébergement Apache ou
#        LiteSpeed, rangé dans un zip à téléverser tel quel dans
#        public_html (par défaut bizzoo-site.zip).
#
#  Le script refuse de finir si le site contient un fichier qui n'a rien
#  à y faire, ou quelque chose qui ressemble à une clé secrète.
# =========================================================
set -euo pipefail
cd "$(dirname "$0")/.."

HEBERGEMENT=0
if [ "${1:-}" = "--hebergement" ]; then HEBERGEMENT=1; shift; fi

# Ce qui part en ligne. Rien d'autre.
FICHIERS=(index.html 404.html robots.txt sitemap.xml)
DOSSIERS=(vitrine client admin apk)

if [ "$HEBERGEMENT" = 1 ]; then
  ZIP="${1:-bizzoo-site.zip}"
  case "$ZIP" in /*) ;; *) ZIP="$PWD/$ZIP" ;; esac
  SORTIE="$(mktemp -d)/site"
else
  SORTIE="${1:-_site}"
fi

rm -rf "$SORTIE"
mkdir -p "$SORTIE"
for f in "${FICHIERS[@]}"; do cp "$f" "$SORTIE/"; done
for d in "${DOSSIERS[@]}"; do cp -R "$d" "$SORTIE/"; done

# Le .htaccess ne sert qu'à un hébergement Apache ou LiteSpeed. GitHub
# Pages l'ignorerait — et le publierait comme un fichier ordinaire.
if [ "$HEBERGEMENT" = 1 ]; then cp hebergement/htaccess "$SORTIE/.htaccess"; fi

# ---- Ce qui ne doit JAMAIS être en ligne ----
interdits=$(cd "$SORTIE" && find . \( -name '*.md' -o -name '*.bat' -o -name '*.ps1' \
  -o -name '*.sh' -o -name '*.sql' -o -name '*.ts' -o -name '*.skill' -o -name '.git*' \
  -o -name '.DS_Store' \) -print)
if [ -n "$interdits" ]; then
  echo "REFUS : ces fichiers n'ont rien à faire en ligne :" >&2
  echo "$interdits" >&2
  exit 1
fi

# ---- Rien qui ressemble à une clé secrète ----
# La clé PUBLIABLE de Supabase (sb_publishable_…) est faite pour être
# lue par tout le monde. Ce qui suit ne l'est jamais : la clé secrète
# (sb_secret_…), un jeton FeexPay (fp_…), une clé privée.
if grep -rIlE 'sb_secret_[A-Za-z0-9]|(^|[^A-Za-z0-9_])fp_[A-Za-z0-9]{16,}|BEGIN [A-Z ]*PRIVATE KEY' \
     --exclude='*.apk' "$SORTIE" >/dev/null 2>&1; then
  echo "REFUS : le site contient quelque chose qui ressemble à une clé secrète :" >&2
  grep -rIlE 'sb_secret_[A-Za-z0-9]|(^|[^A-Za-z0-9_])fp_[A-Za-z0-9]{16,}|BEGIN [A-Z ]*PRIVATE KEY' \
    --exclude='*.apk' "$SORTIE" >&2
  exit 1
fi

# L'ancienne clé « service_role » est un jeton JWT : illisible à l'œil,
# elle ne se trahit qu'une fois décodée. Chaque jeton trouvé est ouvert,
# et un seul qui porte ce rôle suffit à tout arrêter.
python3 - "$SORTIE" <<'PY'
import base64, json, os, re, sys
racine = sys.argv[1]
motif = re.compile(rb"eyJ[A-Za-z0-9_-]{10,}\.(eyJ[A-Za-z0-9_-]{10,})\.[A-Za-z0-9_-]{10,}")
fautifs = []
for dossier, _, fichiers in os.walk(racine):
    for nom in fichiers:
        if nom.endswith(".apk"):
            continue
        chemin = os.path.join(dossier, nom)
        with open(chemin, "rb") as f:
            contenu = f.read()
        for m in motif.finditer(contenu):
            corps = m.group(1) + b"=" * (-len(m.group(1)) % 4)
            try:
                role = json.loads(base64.urlsafe_b64decode(corps)).get("role")
            except Exception:
                continue
            if role == "service_role":
                fautifs.append(chemin)
if fautifs:
    sys.stderr.write("REFUS : une clé service_role est dans le site :\n" + "\n".join(fautifs) + "\n")
    sys.exit(1)
PY

if [ "$HEBERGEMENT" = 1 ]; then
  rm -f "$ZIP"
  (cd "$SORTIE" && zip -qr -X "$ZIP" .)
  rm -rf "$(dirname "$SORTIE")"
  echo "Site prêt à téléverser : $ZIP ($(du -h "$ZIP" | cut -f1))"
else
  echo "Site assemblé dans $SORTIE ($(du -sh "$SORTIE" | cut -f1))"
fi
