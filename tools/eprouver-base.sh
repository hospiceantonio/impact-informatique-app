#!/usr/bin/env bash
# =========================================================
# Éprouve supabase/schema.sql sur un VRAI PostgreSQL.
#
# Les tests des applications simulent la base : ils valident
# l'écran, jamais les déclencheurs — ceux-ci ne s'exécutent
# que pour de vrai. Ce banc d'essai monte un PostgreSQL
# jetable, y pose le décor de Supabase (rôles, auth, storage),
# charge schema.sql tel quel, puis essaie de forcer chaque
# porte.
#
# Usage :  tools/eprouver-base.sh
#
# Sortie 0 : tout tient. Sortie 1 : une porte a cédé, et le
# message dit laquelle.
# =========================================================
set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PGPORT_ESSAI:-5433}"
SOCLE="${TMPDIR:-/tmp}/bizzoo-essai-$$"
export PGHOST="$SOCLE/socket"

rouge() { printf '\033[31m%s\033[0m\n' "$*"; }
vert()  { printf '\033[32m%s\033[0m\n' "$*"; }
gris()  { printf '\033[90m%s\033[0m\n' "$*"; }

# ---------- Chaque fichier se suffit-il ? ----------
# Avant même de monter un PostgreSQL : un fichier qui pose une règle
# d'écriture doit poser les colonnes qu'elle remplit. Sur une base neuve
# elles sont toujours là, donc rien ici ne le verrait ; chez le gérant,
# non — et le fichier passe quand même, pour casser à la première
# commande. Ce contrôle-là se fait à la lecture, pas à l'exécution.
bash "$RACINE/tools/fichiers-autonomes.sh"
echo

# ---------- Trouver PostgreSQL ----------
if command -v initdb >/dev/null 2>&1; then
  BIN=""
else
  BIN="$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1 || true)"
  if [ -z "$BIN" ] || [ ! -x "$BIN/initdb" ]; then
    rouge "PostgreSQL introuvable."
    echo "  Debian/Ubuntu : sudo apt-get install -y postgresql"
    echo "  macOS         : brew install postgresql@16"
    exit 2
  fi
  export PATH="$BIN:$PATH"
fi
gris "PostgreSQL : $(postgres --version)"

# ---------- Un serveur jetable, rien qu'à nous ----------
# Il vit dans un dossier temporaire et disparaît à la sortie,
# quelle qu'en soit la raison.
DONNEES="$SOCLE/donnees"
mkdir -p "$DONNEES" "$PGHOST"
chmod 700 "$DONNEES"

nettoyer() {
  pg_ctl -D "$DONNEES" -m immediate stop >/dev/null 2>&1 || true
  rm -rf "$SOCLE"
}
trap nettoyer EXIT

# Sous root (conteneurs d'intégration continue), PostgreSQL refuse de
# démarrer : on repasse par un compte ordinaire.
COMME=""
if [ "$(id -u)" = "0" ]; then
  if id postgres >/dev/null 2>&1; then
    chown -R postgres "$SOCLE"
    COMME="postgres"
  else
    rouge "Ne pas lancer ce script en root sans compte « postgres »."
    exit 2
  fi
fi

lancer() {
  if [ -n "$COMME" ]; then
    su "$COMME" -c "PATH='$PATH' $*"
  else
    eval "$@"
  fi
}

gris "Création du serveur d'essai…"
lancer "initdb -D '$DONNEES' -A trust -E UTF8 --locale=C" >/dev/null
# Aucune écoute réseau : on passe par une prise Unix, dans un dossier
# qui n'appartient qu'à cette exécution. Deux essais lancés coup sur coup
# ne peuvent donc pas se disputer un port.
lancer "pg_ctl -D '$DONNEES' -o \"-k $PGHOST -p $PORT -c listen_addresses='' -c fsync=off -c full_page_writes=off\" -w start" >/dev/null

PSQL="psql -h '$PGHOST' -p $PORT -d postgres -v ON_ERROR_STOP=1 --no-psqlrc"
# Les « existe déjà, ignoré » d'un second passage n'apprennent rien :
# on ne veut voir que ce que les essais racontent.
PSQL_MUET="$PSQL -c 'set client_min_messages = warning' -q"

charger() {
  gris "  → $(basename "$1")"
  lancer "$PSQL_MUET -f '$1'" >/dev/null 2>&1
}

echo
gris "Le décor de Supabase, puis le schéma tel qu'il part chez le client :"
charger "$RACINE/supabase/tests/00-plateforme.sql"

# Dans l'ordre où cela se passe vraiment : le gérant crée d'abord son
# compte dans Supabase, PUIS exécute schema.sql — qui fait de lui le
# superadministrateur. L'inverse le laisserait dehors.
lancer "$PSQL_MUET -c \"insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'enseigne@bizzoo.bj')
  on conflict do nothing;\"" >/dev/null 2>&1

charger "$RACINE/supabase/schema.sql"

# Une base se relance : le fichier doit pouvoir repasser sans rien casser.
gris "  → schema.sql, une seconde fois (rejouabilité)"
lancer "$PSQL_MUET -f '$RACINE/supabase/schema.sql'" >/dev/null 2>&1

SORTIE="$SOCLE/sortie.txt"

# Les fichiers qu'on envoie au gérant se collent dans l'éditeur SQL de
# Supabase, qui exécute TOUT d'un bloc et annule TOUT à la première
# erreur. On les rejoue donc ici comme lui : en une seule transaction,
# et SANS COMPTE CONNECTÉ — c'est ainsi qu'une simple requête de
# vérification appelant une fonction réservée fait échouer le fichier
# entier, sans rien laisser derrière elle.
echo
gris "Les fichiers à coller dans l'éditeur SQL, rejoués comme lui :"
for migration in "$RACINE"/supabase/*.sql; do
  [ "$(basename "$migration")" = "schema.sql" ] && continue
  gris "  → $(basename "$migration")"
  if ! lancer "$PSQL_MUET --single-transaction -f '$migration'" >"$SORTIE" 2>&1; then
    echo
    rouge "$(basename "$migration") ne passe pas dans l'éditeur SQL de Supabase :"
    grep -E "ERROR|ERREUR" "$SORTIE" | head -3
    rouge "Tout le fichier serait annulé, et le gérant n'aurait rien."
    exit 1
  fi
done

# ---------- Une base DÉJÀ EN SERVICE ----------
# Le gérant n'installe pas la base : il l'a déjà. Chez lui, « create table
# if not exists » ne fait rien du tout — une colonne ajoutée depuis dans le
# corps d'un « create table » ne lui arrivera JAMAIS. C'est arrivé avec la
# marge : elle existait pour une base neuve, pas pour la sienne.
#
# On refait donc son chemin : l'ancien schema.sql, puis les fichiers qu'on
# lui envoie. Il doit arriver exactement où arrive une base neuve.
AVANT="$(git -C "$RACINE" log -2 --format=%H -- supabase/schema.sql 2>/dev/null | tail -1 || true)"
NEUVE="$SOCLE/neuve.txt"
SERVICE="$SOCLE/service.txt"
echo
if [ -z "$AVANT" ] || [ "$AVANT" = "$(git -C "$RACINE" log -1 --format=%H -- supabase/schema.sql 2>/dev/null)" ]; then
  gris "Base déjà en service : pas d'historique de schema.sql ici, étape sautée."
else
  gris "La base du gérant, qui existe DÉJÀ (schema.sql de ${AVANT:0:7}, puis les fichiers) :"
  git -C "$RACINE" show "$AVANT:supabase/schema.sql" > "$SOCLE/schema-avant.sql"
  lancer "createdb -h '$PGHOST' -p $PORT enservice" >/dev/null 2>&1 || true
  PSQL_SERVICE="psql -h '$PGHOST' -p $PORT -d enservice -v ON_ERROR_STOP=1 --no-psqlrc -c 'set client_min_messages = warning' -q"
  lancer "$PSQL_SERVICE -f '$RACINE/supabase/tests/00-plateforme.sql'" >/dev/null 2>&1
  lancer "$PSQL_SERVICE -c \"insert into auth.users (id, email) values
    ('11111111-1111-1111-1111-111111111111', 'enseigne@bizzoo.bj')
    on conflict do nothing;\"" >/dev/null 2>&1
  lancer "$PSQL_SERVICE -f '$SOCLE/schema-avant.sql'" >/dev/null 2>&1

  for migration in "$RACINE"/supabase/*.sql; do
    [ "$(basename "$migration")" = "schema.sql" ] && continue
    if ! lancer "$PSQL_SERVICE --single-transaction -f '$migration'" >"$SORTIE" 2>&1; then
      echo
      rouge "$(basename "$migration") échoue sur une base déjà en service :"
      grep -E "ERROR|ERREUR" "$SORTIE" | head -3
      rouge "Le gérant collerait ce fichier, et tout serait annulé."
      exit 1
    fi
  done

  INVENTAIRE="select table_name || '.' || column_name from information_schema.columns
              where table_schema = 'public' order by 1;"
  lancer "$PSQL -t -A -c \"$INVENTAIRE\"" > "$NEUVE" 2>/dev/null
  lancer "$PSQL_SERVICE -t -A -c \"$INVENTAIRE\"" > "$SERVICE" 2>/dev/null
  if ! diff -q "$NEUVE" "$SERVICE" >/dev/null; then
    echo
    rouge "La base du gérant n'arrive pas là où arrive une base neuve :"
    diff "$NEUVE" "$SERVICE" | sed -n 's/^< /  il lui MANQUE  /p;s/^> /  elle a EN TROP /p' | head -12
    rouge "Ajoutez « alter table … add column if not exists » : chez lui,"
    rouge "le corps d'un « create table if not exists » n'est jamais lu."
    exit 1
  fi
  vert "  la base du gérant arrive exactement où arrive une base neuve ✔"
fi

# Les comptes suivants naissent modérateurs et inactifs, comme ceux que
# l'on crée depuis l'application : c'est à l'enseigne de les élever.
lancer "$PSQL_MUET -c \"insert into auth.users (id, email) values
  ('22222222-2222-2222-2222-222222222222', 'chef-boutique@bizzoo.bj'),
  ('33333333-3333-3333-3333-333333333333', 'equipe@bizzoo.bj')
  on conflict do nothing;\"" >/dev/null 2>&1

# ---------- L'état des lieux dit-il la vérité ? ----------
# Ce fichier-là est le seul que le gérant lise vraiment : c'est lui qui
# lui annonce « en place » ou « MANQUANT ». Il s'exécute déjà plus haut,
# avec les autres — mais s'exécuter ne prouve rien : une requête de
# lecture réussit même quand elle répond faux. Or sur CETTE base, qui
# vient de recevoir schema.sql et tous les fichiers, la réponse est
# connue d'avance : tout doit être en place. Un « MANQUANT » ici, et
# c'est le contrôle qui se trompe, pas la base — le gérant chercherait
# à réparer ce qui va bien.
echo
gris "L'état des lieux, sur une base où tout est là :"
lancer "$PSQL -t -A -f '$RACINE/supabase/etat-des-lieux.sql'" > "$SORTIE" 2>&1
if grep -q 'MANQUANT' "$SORTIE"; then
  rouge "L'état des lieux annonce « MANQUANT » là où tout vient d'être posé :"
  grep 'MANQUANT' "$SORTIE" | head -8
  rouge "Ou bien le contrôle se trompe — et le gérant chercherait à réparer"
  rouge "ce qui va bien ; ou bien schema.sql ne pose pas ce qu'il annonce."
  exit 1
fi
CONTROLES="$(grep -c 'en place' "$SORTIE" || true)"
if [ "${CONTROLES:-0}" -lt 1 ]; then
  rouge "L'état des lieux n'a rien constaté du tout :"
  head -5 "$SORTIE"
  exit 1
fi
vert "  $CONTROLES contrôles, tous « en place » ✔"

echo
ECHECS=0
for fichier in "$RACINE"/supabase/tests/[1-9]*.sql; do
  [ -e "$fichier" ] || continue
  echo "── $(basename "$fichier")"
  if lancer "$PSQL -f '$fichier'" >"$SORTIE" 2>&1; then
    sed -n 's/^psql:.*: NOTICE:  //p' "$SORTIE"
    # Un fichier MUET passait pour vert. C'est arrivé : un
    # « set client_min_messages = warning » de trop, et les trente-huit
    # constats d'un fichier disparaissaient — le banc annonçait quand
    # même que tout tenait. Un essai qui ne constate rien ne prouve
    # rien : on le compte pour un échec.
    if ! grep -q '  ok    ' "$SORTIE"; then
      echo
      rouge "  Aucun constat dans ce fichier : il s'est exécuté sans rien éprouver."
      ECHECS=$((ECHECS + 1))
    fi
  else
    sed -n 's/^psql:.*: NOTICE:  //p' "$SORTIE"
    echo
    grep -E "ÉCHEC|ERROR|ERREUR" "$SORTIE" | head -8
    ECHECS=$((ECHECS + 1))
  fi
  echo
done

if [ "$ECHECS" -gt 0 ]; then
  rouge "La base a laissé passer quelque chose, ou un essai n'a pas pu aller au bout."
  exit 1
fi

vert "La base tient : schema.sql se rejoue, et chaque porte forcée a résisté ✔"
