#!/usr/bin/env bash
# =========================================================
# Un fichier collé dans l'éditeur SQL doit se suffire.
#
# Le gérant n'installe pas la base : il l'a déjà, et il ne
# rejoue pas schema.sql. Il colle les petits fichiers qu'on
# lui envoie, un par un, dans l'ordre où on les lui envoie.
#
# Or PostgreSQL ne relit le corps d'une fonction qu'au moment
# de l'EXÉCUTER. Un fichier peut donc poser une règle
# d'écriture qui remplit une colonne absente : il passe sans
# broncher, et la base s'arrête à la première commande, sur
# « record "new" has no field … ». C'est arrivé pour de vrai :
# marge-bizzoo.sql posait la règle qui fige le code du produit
# vendu, sans poser la colonne qui le reçoit.
#
# Ce contrôle relit chaque fichier et exige la règle suivante :
#
#   un fichier qui (re)pose une fonction de déclencheur pose
#   AUSSI toutes les colonnes tardives que cette fonction lit
#   ou écrit — même celles qu'un autre fichier a inventées.
#
# « Tardive » veut dire : ajoutée par un « alter table … add
# column if not exists » dans schema.sql. Ce sont exactement
# celles qui peuvent manquer à une base déjà en service ; les
# autres sont dans le corps du « create table », donc là
# depuis toujours.
#
# Usage :  tools/fichiers-autonomes.sh
# Sortie 0 : chaque fichier se suffit. Sortie 1 : le message
# dit quel fichier, quelle fonction, et quelle ligne ajouter.
# =========================================================
set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="$RACINE/supabase/schema.sql"

rouge() { printf '\033[31m%s\033[0m\n' "$*"; }
vert()  { printf '\033[32m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }

[ -f "$SCHEMA" ] || { rouge "supabase/schema.sql introuvable."; exit 2; }

REPERES="$(mktemp)"
trap 'rm -f "$REPERES"' EXIT

# ---------- Ce que schema.sql nous apprend ----------
# TARDIVE table.colonne  — une colonne qui peut manquer ailleurs.
# PORTE   fonction table — quelle fonction s'exécute sur quelle table.
awk '
  # « alter table public.X » ouvre une cible, le « ; » la referme.
  /^[[:space:]]*alter table (only )?public\.[a-z_]+/ {
    match($0, /public\.[a-z_]+/); cible = substr($0, RSTART + 7, RLENGTH - 7);
  }
  /add column if not exists [a-z_]+/ {
    if (cible != "") {
      match($0, /add column if not exists [a-z_]+/);
      colonne = substr($0, RSTART + 25, RLENGTH - 25);
      print "TARDIVE " cible "." colonne;
    }
  }
  /;/ { if (!dans_trigger) cible = "" }

  # « create trigger … on public.T … execute function public.F() »
  /^[[:space:]]*create trigger/ { dans_trigger = 1; table = ""; fonction = "" }
  dans_trigger && / on public\.[a-z_]+/ {
    match($0, / on public\.[a-z_]+/); table = substr($0, RSTART + 11, RLENGTH - 11);
  }
  dans_trigger && /execute function public\.[a-z_]+/ {
    match($0, /execute function public\.[a-z_]+/);
    fonction = substr($0, RSTART + 24, RLENGTH - 24);
    if (table != "") print "PORTE " fonction " " table;
    dans_trigger = 0; cible = "";
  }
' "$SCHEMA" | sort -u > "$REPERES"

TARDIVES="$(grep -c '^TARDIVE ' "$REPERES" || true)"
PORTES="$(grep -c '^PORTE ' "$REPERES" || true)"
gris "schema.sql : $TARDIVES colonnes tardives, $PORTES déclencheurs."
if [ "$TARDIVES" = "0" ] || [ "$PORTES" = "0" ]; then
  rouge "Rien n'a été reconnu dans schema.sql : ce contrôle ne contrôle plus rien."
  exit 2
fi

# ---------- Chaque fichier, relu seul ----------
MANQUES=0
for fichier in "$RACINE"/supabase/*.sql; do
  [ "$(basename "$fichier")" = "schema.sql" ] && continue
  SORTIE="$(awk -v reperes="$REPERES" -v nom="$(basename "$fichier")" '
    BEGIN {
      while ((getline ligne < reperes) > 0) {
        split(ligne, m, " ");
        if (m[1] == "TARDIVE") tardive[m[2]] = 1;
        else if (m[1] == "PORTE") porte[m[2]] = m[3];
      }
    }
    # Ce que CE fichier pose lui-même.
    /^[[:space:]]*alter table (only )?public\.[a-z_]+/ {
      match($0, /public\.[a-z_]+/); cible = substr($0, RSTART + 7, RLENGTH - 7);
    }
    /add column if not exists [a-z_]+/ {
      if (cible != "") {
        match($0, /add column if not exists [a-z_]+/);
        pose[cible "." substr($0, RSTART + 25, RLENGTH - 25)] = 1;
      }
    }
    /;/ { if (!fonction) cible = "" }

    # Ce que ses fonctions touchent.
    /^create or replace function public\.[a-z_]+/ {
      match($0, /public\.[a-z_]+/);
      fonction = substr($0, RSTART + 7, RLENGTH - 7);
      depart = FNR; cible = ""; next;
    }
    fonction && /^end \$\$;/ { fonction = ""; next }
    fonction {
      reste = $0;
      while (match(reste, /(new|old)\.[a-z_]+/)) {
        bout = substr(reste, RSTART, RLENGTH);
        sub(/^(new|old)\./, "", bout);
        touche[fonction " " bout] = depart;
        reste = substr(reste, RSTART + RLENGTH);
      }
    }
    END {
      for (cle in touche) {
        split(cle, m, " ");
        table = porte[m[1]];
        if (table == "") continue;                 # pas une fonction de déclencheur
        if (!tardive[table "." m[2]]) continue;    # colonne de toujours
        if (pose[table "." m[2]]) continue;        # le fichier la pose
        printf "%s|%s|%s|%s|%d\n", nom, m[1], table, m[2], touche[cle];
      }
    }
  ' "$fichier" | sort -t'|' -k3,3 -k4,4)"

  [ -z "$SORTIE" ] && continue
  echo
  rouge "$(basename "$fichier") ne se suffit pas :"
  while IFS='|' read -r f fonc table colonne ligne; do
    [ -z "$f" ] && continue
    echo "  public.$fonc() (ligne $ligne) écrit ou lit $table.$colonne,"
    echo "  que ce fichier ne pose pas. Ajoutez-y :"
    echo "      alter table public.$table add column if not exists $colonne …;"
    MANQUES=$((MANQUES + 1))
  done <<< "$SORTIE"
done

echo
if [ "$MANQUES" -gt 0 ]; then
  rouge "$MANQUES colonne(s) manquante(s) : sur une base déjà en service, ces"
  rouge "fichiers passeraient sans erreur et casseraient tout à l'usage."
  exit 1
fi
vert "Chaque fichier pose les colonnes que ses fonctions remplissent ✔"

# =========================================================
# Deuxième règle : une fonction appelée est une fonction posée
#
# Le même piège, un cran plus loin. Une fonction n'appelle pas
# que des colonnes : elle appelle d'autres fonctions. Et une
# fonction née APRÈS la base du gérant manque chez lui, alors
# qu'elle est là chez nous.
#
# C'est exactement ce qui s'est passé quand « creer_commande »
# s'est mise à demander « compte_exige() » : trois fichiers
# portaient l'appelante, aucun ne portait l'appelée. Collé seul
# sur une base d'avant, chacun d'eux passait sans broncher —
# pour refuser toute commande à la première vente.
#
# La règle : si un fichier NOMME « public.f( » et que « f » est
# née dans un fichier de migration (donc plus tard que le socle),
# ce fichier doit la poser lui-même. Les fonctions qui ne vivent
# que dans schema.sql sont le socle : elles sont là depuis
# toujours, chez tout le monde.
# =========================================================
echo
NEES="$(for f in "$RACINE"/supabase/*.sql; do
  [ "$(basename "$f")" = "schema.sql" ] && continue
  grep -o 'create or replace function public\.[a-z_]*' "$f" || true
done | sed 's/.*public\.//' | sort -u)"

NB_NEES="$(printf '%s\n' "$NEES" | grep -c . || true)"
gris "migrations : $NB_NEES fonction(s) nées après le socle."
if [ "$NB_NEES" = "0" ]; then
  rouge "Aucune fonction reconnue dans les migrations : ce contrôle ne contrôle plus rien."
  exit 2
fi

EMPRUNTS=0
for fichier in "$RACINE"/supabase/*.sql; do
  nom="$(basename "$fichier")"
  [ "$nom" = "schema.sql" ] && continue
  # « || true » : un fichier sans aucune fonction n'est pas une erreur,
  # et « grep » qui ne trouve rien sort en 1 — que « pipefail » propage.
  posees="$( { grep -o 'create or replace function public\.[a-z_]*' "$fichier" || true; } \
             | sed 's/.*public\.//' | sort -u)"
  appels="$( { grep -o 'public\.[a-z_]*(' "$fichier" || true; } \
             | sed 's/public\.//; s/(//' | sort -u)"
  for appelee in $appels; do
    # Née dans le socle : elle est là chez tout le monde depuis toujours.
    if ! printf '%s\n' "$NEES" | grep -qx "$appelee"; then continue; fi
    # Le fichier la pose lui-même : il se suffit.
    if printf '%s\n' "$posees" | grep -qx "$appelee"; then continue; fi
    if [ "$EMPRUNTS" = "0" ]; then echo; fi
    rouge "$nom emprunte public.$appelee() sans la poser."
    echo "  Sur une base d'avant, ce fichier passerait sans erreur et"
    echo "  s'arrêterait à l'usage. Recopiez-y la fonction telle quelle :"
    echo "      create or replace function public.$appelee(…) …"
    EMPRUNTS=$((EMPRUNTS + 1))
  done
done

echo
if [ "$EMPRUNTS" -gt 0 ]; then
  rouge "$EMPRUNTS emprunt(s) non posé(s)."
  exit 1
fi
vert "Chaque fichier pose les fonctions qu'il appelle ✔"
