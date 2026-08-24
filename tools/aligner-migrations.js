/* =========================================================
   Aligne les fichiers de migration sur schema.sql.

   Les fichiers qu'on envoie au gérant redéfinissent parfois
   les mêmes fonctions que schema.sql — « creer_commande »,
   par exemple, apparaît dans trois d'entre eux. Le jour où
   l'un garde une version périmée, l'exécuter APRÈS un autre
   défait ce que celui-ci venait de poser. En silence : le
   fichier passe, la base répond, et une fonctionnalité a
   disparu.

   C'est arrivé : « commandes-paiement.sql » gardait une
   « creer_commande » d'avant le code produit ; le rejouer
   retirait le code du récapitulatif envoyé au client.

   Ce script recopie dans chaque migration le corps que
   schema.sql donne à la fonction. schema.sql reste la seule
   source de vérité ; les migrations n'en sont que des
   extraits.

   Usage :  node tools/aligner-migrations.js
   ========================================================= */
const fs = require("fs");
const path = require("path");

const RACINE = path.join(__dirname, "..");
const SUPABASE = path.join(RACINE, "supabase");

/**
 * Le texte d'une fonction, depuis son en-tête jusqu'à sa fin.
 * Les fonctions du projet se terminent toutes par « end $$; »
 * (plpgsql) ou « $$; » (sql).
 */
function corpsDeLaFonction(source, nom) {
  const entete = "create or replace function public." + nom + "(";
  const debut = source.indexOf(entete);
  if (debut < 0) return null;
  const finPlpgsql = source.indexOf("\nend $$;", debut);
  const finSql = source.indexOf("\n$$;", debut);
  const candidats = [
    finPlpgsql >= 0 ? finPlpgsql + "\nend $$;".length : Infinity,
    finSql >= 0 ? finSql + "\n$$;".length : Infinity,
  ].filter((n) => n !== Infinity);
  if (!candidats.length) return null;
  return source.slice(debut, Math.min(...candidats));
}

const schema = fs.readFileSync(path.join(SUPABASE, "schema.sql"), "utf8");

let alignees = 0;
let intactes = 0;
const manquantes = [];

for (const fichier of fs.readdirSync(SUPABASE).filter((f) => f.endsWith(".sql"))) {
  if (fichier === "schema.sql") continue;
  const chemin = path.join(SUPABASE, fichier);
  let texte = fs.readFileSync(chemin, "utf8");
  const noms = [...texte.matchAll(/create or replace function public\.([a-z_]+)\(/g)]
    .map((m) => m[1]);

  for (const nom of [...new Set(noms)]) {
    const voulu = corpsDeLaFonction(schema, nom);
    if (!voulu) { manquantes.push(fichier + " : " + nom); continue; }
    const actuel = corpsDeLaFonction(texte, nom);
    if (actuel === null) continue;
    if (actuel === voulu) { intactes++; continue; }
    // Le corps est plein de « $$ » — les délimiteurs de PostgreSQL. Passé
    // tel quel à « replace », chaque « $$ » deviendrait un simple « $ » :
    // c'est ainsi que JavaScript écrit un dollar dans un remplacement. La
    // fonction rend le texte intact.
    texte = texte.replace(actuel, () => voulu);
    console.log("  aligné  " + fichier + " → " + nom + "()");
    alignees++;
  }
  // Un délimiteur perdu et le fichier ne veut plus rien dire — sans que
  // rien ne le signale avant l'éditeur SQL du gérant. On compte.
  const ouvrants = (texte.match(/\$\$/g) || []).length;
  const solitaires = (texte.match(/(^|[^$])\$([^$]|$)/g) || []).length;
  if (ouvrants % 2 !== 0 || solitaires > 0) {
    console.error("  DÉLIMITEURS ABÎMÉS dans " + fichier + " : rien n'est écrit.");
    process.exit(1);
  }
  fs.writeFileSync(chemin, texte);
}

for (const m of manquantes) console.log("  ABSENTE de schema.sql : " + m);
console.log(alignees + " fonction(s) réalignée(s), " + intactes + " déjà à jour.");
if (manquantes.length) process.exit(1);
