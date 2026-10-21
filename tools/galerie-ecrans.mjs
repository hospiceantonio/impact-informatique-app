/* =========================================================
   La galerie des écrans — et ce qu'une capture ne dit pas
   =========================================================
   CE QU'ELLE FAIT. Elle ouvre les deux applications sur une
   base doublée (rien ne sort de la machine), passe sur chaque
   écran, et en garde une capture dans un dossier. C'est ce
   qu'on envoie au propriétaire pour montrer « avant » et
   « après », et ce qu'on regarde soi-même avant de livrer.

   CE QU'ELLE MESURE, en plus. Sur chaque écran :
     — la page déborde-t-elle en largeur, et à cause de quoi ;
     — quels boutons ont leur texte sur deux lignes ;
     — quels titres d'en-tête sont coupés par « … » ;
     — quels textes à une ligne sont coupés.
   Le rapport sort en JSON et en résumé dans la console.

   LE ZOOM DU TÉLÉPHONE. Le propriétaire a réglé son téléphone
   sur de grands caractères : Android multiplie alors TOUTES
   les tailles de police de l'application (le « textZoom » du
   WebView suit le réglage du système), sans toucher aux
   largeurs ni aux marges. C'est là que les boutons passent sur
   deux lignes et que les tuiles débordent. ZOOM=1.3 rejoue ce
   réglage : chaque élément reçoit sa taille calculée × 1,3,
   une fois, juste avant la capture.

     GALERIE=<dossier> ZOOM=1.3 LARGEUR=360 \
     PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/galerie-ecrans.mjs

   SEUL=<motif> ne capture que les écrans dont le nom contient
   le motif (« admin-commandes », « client- »).
   ========================================================= */
import fs from "node:fs";
import path from "node:path";

let chromium;
try {
  chromium = (await import(process.env.PLAYWRIGHT || "playwright-core/index.js"))
    .default.chromium;
} catch (_) {
  console.error("Playwright est introuvable.\n" +
    "  PLAYWRIGHT=<chemin>/playwright-core/index.js node tools/galerie-ecrans.mjs");
  process.exit(2);
}
const EXE = process.env.CHROMIUM || undefined;
const BASE = process.env.BANC_URL || "http://localhost:5180";
const DOSSIER = process.env.GALERIE || "galerie";
const ZOOM = Number(process.env.ZOOM || "1");
const LARGEUR = Number(process.env.LARGEUR || "360");
const SEUL = process.env.SEUL || "";
fs.mkdirSync(DOSSIER, { recursive: true });

const nav = await chromium.launch(EXE ? { executablePath: EXE } : {});

/* ------------------------------------------------------------------
   La base doublée : des noms longs, exprès. C'est avec « IMPACT
   INFORMATIQUE », « Imprimante multifonction Canon PIXMA G3411 à
   réservoirs rechargeables Wi-Fi » et une adresse de Cotonou qu'un
   écran casse — pas avec « Alpha » et « Souris ».
   ------------------------------------------------------------------ */
const MOI = "22222222-2222-2222-2222-222222222222";
const il = (min) => new Date(Date.now() - min * 60000).toISOString();
const PHOTO = (n) => "galerie/photo-" + n + ".svg";

const CATS = [
  ["cat_mode", "Mode & Vêtements", "mode"], ["cat_hightech", "Informatique & Électronique", "informatique"],
  ["cat_maison", "Maison & Déco", "maison"], ["cat_beaute", "Beauté & Santé", "sante"],
  ["cat_resto", "Restauration", "restauration"], ["cat_elec", "Électroménager", "electromenager"],
  ["cat_jouets", "Bébé & Enfants", "bebe"], ["cat_brico", "Bricolage & Matériaux", "bricolage"],
].map(([id, nom, icone], i) => ({ id, nom, icone, couleur: "#0047D9", en_avant: true, ordre: i + 1,
  boutique_id: null, sous_categories: [
    { id: "sc_" + id + "_1", nom: "Smartphones", ordre: 1 }, { id: "sc_" + id + "_2", nom: "Ordinateurs portables", ordre: 2 },
    { id: "sc_" + id + "_3", nom: "Accessoires", ordre: 3 }, { id: "sc_" + id + "_4", nom: "Tablettes", ordre: 4 }] }));

const BOUT = [
  { id: "bou_a", nom: "IMPACT INFORMATIQUE", secteur: "Informatique", categorie_id: "cat_hightech",
    note_moyenne: 4.2, nb_avis: 12, ordre: 1, logo: PHOTO("logo-a"), slogan: "Achat et vente de matériels informatiques et électroniques. En gros et en détail, livraison partout à Cotonou." },
  { id: "bou_b", nom: "JouJoutheque", secteur: "Jouets", categorie_id: "cat_jouets", note_moyenne: null, nb_avis: 0, ordre: 2, logo: PHOTO("logo-b") },
  { id: "bou_c", nom: "Matériel net", secteur: "Électroménager", categorie_id: "cat_elec", note_moyenne: 4.9, nb_avis: 40, ordre: 3 },
  { id: "bou_d", nom: "CREATIS INTER", secteur: "Services", categorie_id: "cat_hightech", note_moyenne: 4.5, nb_avis: 3, ordre: 4 },
  { id: "bou_e", nom: "restaurant bizzoo", secteur: "Restauration", categorie_id: "cat_resto", note_moyenne: 3.8, nb_avis: 7, ordre: 5 },
  { id: "bou_f", nom: "BENIN BÂTI PRO", secteur: "Bricolage", categorie_id: "cat_brico", note_moyenne: null, nb_avis: 0, ordre: 6 },
].map((b) => ({ icone: "magasin", couleur: "#0047D9", devise: "FCFA", indicatif: "229", actif: true,
  photos: [], whatsapp: "0197121596", tel: "0159045604", adresse: "Sainte Rita, Cotonou",
  site_web: "www.bizzoomarket.com", horaires: "Lundi - Samedi, 8h - 20h",
  description: "Achat et vente de matériels informatiques et électroniques.\nEn gros et en détail.",
  frais_livraison: 1000, ...b }));

const P = (id, bou, nom, prix, o = {}) => ({ id, boutique_id: bou, nom, code: "10" + String(id).padStart(4, "0"),
  reference: "IMP-0" + id, description: "Processeur : Intel Core i5\nRAM : 8 Go\nStockage : 512 Go SSD\nUn bel appareil, garanti six mois.",
  prix, ancien_prix: null, categorie_id: "cat_hightech", sous_categorie_id: "sc_cat_hightech_3",
  stock: 5, sur_commande: false, disponible: true, en_avant: false, ordre_avant: 0,
  images: [PHOTO("p" + id)], video: "", cree_le: il(60 * 24 * 3), modifie_le: il(60), note_moyenne: 4.5, nb_avis: 2, ...o });
const PROD = [
  P(1, "bou_a", "Ordinateur portable HP 15.6 pouces Intel Core i5 8 Go RAM 512 Go SSD Windows 11", 299000, { ancien_prix: 350000, en_avant: true, ordre_avant: 1 }),
  P(2, "bou_a", "iAir Pro 2", 6600),
  P(3, "bou_a", "OALE iAir Pro 3 TWS", 6600, { stock: 0, sur_commande: true }),
  P(4, "bou_a", "Cartouche d'encre HP 650 couleur d'origine", 7150, { video: PHOTO("v") }),
  P(5, "bou_a", "Pocket wifi universel T-ELEK 4G LTE", 7150, { stock: 0 }),
  P(6, "bou_b", "Ludo jouet en bois pour enfants de 3 à 8 ans", 110, { categorie_id: "cat_jouets", sous_categorie_id: "sc_cat_jouets_1" }),
  P(7, "bou_e", "CHAWARMA", 105, { categorie_id: "cat_resto", sous_categorie_id: "sc_cat_resto_1", images: [] }),
  P(8, "bou_c", "Imprimante multifonction Canon PIXMA G3411 à réservoirs rechargeables Wi-Fi", 142000, { ancien_prix: 160000, categorie_id: "cat_elec", sous_categorie_id: "sc_cat_elec_1", stock: 2 }),
];
const SLIDES = [{ id: 1, type: "image", image: PHOTO("slide"), titre: "Rentrée scolaire", sous_titre: "Jusqu'à -30 % sur les ordinateurs", lien: "#/produits", ordre: 1, actif: true, boutique_id: null }];

const L = (id, cmd, pid, nom, code, prix, q, etat, bou = "bou_a", conf) => ({ id, commande_id: cmd, boutique_id: bou,
  produit_id: pid, nom, code, reference: "IMP-0" + code.slice(-3), prix, prix_bizzoo: Math.round(prix * 0.9), quantite: q, etat,
  cree_le: il(30), confirme_le: conf || null, livreur_id: null });
const C = (o) => ({ note: "", devise: "FCFA", transaction_id: "tx", fournisseur_ref: "FXP-9001", confirme_par: "",
  remarque: "", transaction_annoncee: "", revendeur: false, client_indicatif: "229", frais_livraison: 1000, ...o });
const CMD = [
  C({ id: "c21", numero: "BZ-000062", client_nom: "Marina Agossou-Hounkpatin", client_tel: "0147174951",
    client_adresse: "Cotonou, Fidjrossè, derrière la pharmacie Sainte Rita, maison à étage bleue", note: "Merci d'appeler avant de passer, je suis au bureau jusqu'à 18 h.",
    total: 319500, etat: "payee", paye_le: il(6), cree_le: il(7), commande_lignes: [
      L("l1", "c21", "1", PROD[0].nom, "100061", 299000, 1, "nouvelle"),
      L("l2", "c21", "2", "iAir Pro 2", "100062", 6600, 2, "vue"),
      L("l3", "c21", "7", "CHAWARMA", "100407", 105, 1, "nouvelle", "bou_e"),
    ] }),
  C({ id: "c20", numero: "BZ-000058", client_nom: "Axel", client_tel: "0157959726", client_adresse: "Fidjrossè von morija",
    note: "O", revendeur: true, total: 142000, etat: "payee", paye_le: il(21), cree_le: il(23), commande_lignes: [
      L("l4", "c20", "8", PROD[7].nom, "100070", 142000, 1, "preparee", "bou_c"),
    ] }),
  C({ id: "c18", numero: "BZ-000057", client_nom: "Awa Soglo", client_tel: "0191223344", client_adresse: "Porto-Novo, Ouando",
    total: 64000, etat: "payee", paye_le: il(3 * 60), cree_le: il(3 * 60 + 2), commande_lignes: [
      L("l5", "c18", "5", "Pocket wifi universel T-ELEK 4G LTE", "100081", 29000, 1, "en_livraison"),
    ] }),
  C({ id: "c17", numero: "BZ-000033", confirme_par: "chef@bizzoo.bj", client_nom: "Sandrine", client_tel: "0192884611",
    client_adresse: "Tankpè", note: "DVD bleu, ludo jaune, repas chaud", total: 1315, etat: "payee",
    paye_le: il(24 * 60), cree_le: il(24 * 60 + 3), commande_lignes: [
      L("l6", "c17", "7", "CHAWARMA", "100407", 105, 1, "remise", "bou_e", il(23 * 60)),
      L("l7", "c17", "4", "Disque DVD+R vierge", "100155", 1100, 1, "remise", "bou_a", il(23 * 60)),
      L("l8", "c17", "6", "Ludo jouet", "100410", 110, 1, "remise", "bou_b", il(23 * 60)),
    ] }),
];
const CMD_CLIENT = CMD.map((c) => ({ id: c.id, numero: c.numero, total: c.total, devise: "FCFA", etat: c.etat,
  cree_le: c.cree_le, paye_le: c.paye_le, frais_livraison: 1000,
  client: { nom: c.client_nom, tel: c.client_tel, indicatif: "229", adresse: c.client_adresse },
  boutiques: [{ id: "bou_a", nom: "IMPACT INFORMATIQUE", montant: c.total,
    lignes: c.commande_lignes.map((l) => ({ nom: l.nom, prix: l.prix, quantite: l.quantite, etat: l.etat, code: l.code })) }] }));

const NOTIFS = [
  { id: 1, type: "commande_payee", titre: "Commande BZ-000062 payée", corps: "Marina Agossou-Hounkpatin a réglé 319 500 FCFA par FeexPay. Préparez les articles.", lien: "#/commandes/c21", commande_id: "c21", boutique_id: "bou_a", sonne: true, lue_le: null, cree_le: il(6) },
  { id: 2, type: "course_proposee", titre: "Course à prendre", corps: "Commande BZ-000058 — Fidjrossè von morija, 1 article à récupérer chez Matériel net.", lien: "#/livraisons", commande_id: "c20", boutique_id: "bou_c", sonne: true, lue_le: null, cree_le: il(20) },
  { id: 3, type: "reversement_demande", titre: "Demande de reversement", corps: "IMPACT INFORMATIQUE demande 150 000 FCFA sur le 01 97 12 15 96 (MTN).", lien: "#/reversements", commande_id: null, boutique_id: "bou_a", sonne: false, lue_le: il(60), cree_le: il(90) },
  { id: 4, type: "commande_remise", titre: "Votre colis est livré", corps: "Confirmez la réception de la commande BZ-000033.", lien: "#/commande/c17", commande_id: "c17", boutique_id: null, sonne: true, lue_le: null, cree_le: il(40) },
];
const PROFILS = [
  { id: MOI, email: "chef@impact.bj", role: "superadministrateur", actif: true, nom: "Hospice Soetonve", tel: "0196202098", boutique_id: null, peut_modifier_produits: true, peut_commandes: true, peut_boutiques: true, peut_finances: true, cree_par: null, cree_le: il(100000) },
  { id: "33333333-3333-3333-3333-333333333333", email: "boutique@impact.bj", role: "administrateur", actif: true, nom: "Rodrigue Agbo Houngbédji", tel: "0197000001", boutique_id: "bou_a", cree_par: MOI, cree_le: il(50000) },
  { id: "44444444-4444-4444-4444-444444444444", email: "", role: "livreur", actif: true, nom: "Rohim", tel: "0166554433", boutique_id: null, cree_par: MOI, cree_le: il(20000) },
  { id: "55555555-5555-5555-5555-555555555555", email: "modo@impact.bj", role: "moderateur", actif: false, nom: "", tel: "", boutique_id: "bou_a", cree_par: MOI, cree_le: il(10000) },
];

/* Les fonctions de la base, par leur nom : ce qu'elles rendent ici est
   ce qu'il faut pour que l'écran se dessine, pas plus. */
const RPC = {
  produits_populaires: PROD.slice(0, 4).map((p) => ({ produit_id: p.id, ventes: 3 })),
  lives_en_cours: [],
  mes_livraisons: [{ commande_id: "c20", numero: "BZ-000058", client_nom: "Axel", client_tel: "0157959726",
    client_adresse: "Fidjrossè von morija", note: "O", montant: 142000, devise: "FCFA", reste: 12000, acompte: 130000, frais: 1000,
    etat: "preparee", boutique_nom: "Matériel net", boutique_adresse: "Carrefour Agla, Cotonou",
    lignes: [{ nom: PROD[7].nom, quantite: 1, prix: 142000 }], prise_le: il(10), remise_le: null, encaisse: null, momopay: { code: "123456", nom: "BIZZOO MARKET" } }],
  courses_proposees: [],
  ma_caisse: { total: 0, lignes: [] },
  caisse_livreurs: [],
  solde_boutique: { gagne: 420000, a_venir: 142000, deja_encaisse: 0, reverse: 150000, en_attente: 0, disponible: 270000, devise: "FCFA", reception: { tel: "0197121596", reseau: "MTN", titulaire: "SOETONVE Hospice" } },
  reversements_liste: [{ id: 1, boutique_id: "bou_a", boutique_nom: "IMPACT INFORMATIQUE", montant: 150000, tel: "0197121596", reseau: "MTN", titulaire: "SOETONVE Hospice", etat: "en_attente", demande_le: il(120), decide_le: null, reference: "", motif: "" },
    { id: 2, boutique_id: "bou_c", boutique_nom: "Matériel net", montant: 80000, tel: "0166554433", reseau: "MOOV", titulaire: "", etat: "valide", demande_le: il(3000), decide_le: il(2000), reference: "MP240921.1234", motif: "" }],
  clients_liste: [{ id: "cl1", nom: "Marina Agossou-Hounkpatin", tel: "0147174951", indicatif: "229", email: "marina@exemple.bj", verifie: true, revendeur: false, nb_commandes: 4, total: 540000, devise: "FCFA", derniere_le: il(6) },
    { id: "cl2", nom: "Axel", tel: "0157959726", indicatif: "229", email: "", verifie: false, revendeur: true, nb_commandes: 1, total: 142000, devise: "FCFA", derniere_le: il(21) }],
  client_commandes: [],
  versements_liste: [{ id: 1, commande_id: "c21", numero: "BZ-000062", montant: 319500, attendu: 319500, devise: "FCFA", canal: "MTN Mobile Money", reference: "FXP-9001", etat: "recu", quand: il(6), client_nom: "Marina Agossou-Hounkpatin" },
    { id: 2, commande_id: "c18", numero: "BZ-000057", montant: 12000, attendu: 64000, devise: "FCFA", canal: "Moov Money", reference: "FXP-8812", etat: "incomplet", quand: il(180), client_nom: "Awa Soglo" }],
  versements_resume: [{ canal: "MTN Mobile Money", total: 319500, nombre: 1 }, { canal: "Moov Money", total: 12000, nombre: 1 }],
  codes_promo_liste: [{ id: 1, code: "RENTREE10", remise: 10, type: "pourcentage", actif: true, utilisations: 12, cout: 45000, devise: "FCFA", fin_le: null, cree_le: il(5000) },
    { id: 2, code: "BIENVENUE", remise: 2000, type: "montant", actif: false, utilisations: 3, cout: 6000, devise: "FCFA", fin_le: il(-1000), cree_le: il(9000) }],
  parrains_liste: [], retraits_a_traiter: [],
  revendeurs: [{ id: "rv1", nom: "Meaulnes Aurel", tel: "0166778899", indicatif: "229", email: "", etat: "en_attente", commerce: "Boutique de téléphones au marché Dantokpa, hangar 12", adresse: "Dantokpa, Cotonou", latitude: 6.37, longitude: 2.43, demande_le: il(300), cree_par: null }],
  statistiques_ventes: { total: 1230000, benefice: 123000, commandes: 14, articles: 22, devise: "FCFA", lignes: [{ produit: PROD[0].nom, boutique: "IMPACT INFORMATIQUE", quantite: 3, prix_bizzoo: 269100, marge: 29900, prix: 299000, benefice: 89700 }], boutiques: [{ nom: "IMPACT INFORMATIQUE", benefice: 89700, total: 897000 }] },
  statistiques_boutique: { total: 897000, articles: 3, commandes: 3, devise: "FCFA", lignes: [] },
  livreurs_boutique: [PROFILS[2]], livraison_des_commandes: [], produits_classes: [], remises_periode: [],
  etat_connexion: { sms_exige: false, numero: "0196202098", confirme: false, comptes: 20, avec_numero: 19, confirmes: 2 },
  mes_appareils_confiance: [], mon_solde_parrain: null, livreurs_de_ma_commande: [], a_achete: true, recours_possible: false,
};

/* Une photo de démonstration : un SVG coloré que le navigateur affiche
   comme une image. Rien n'est téléchargé. */
function photo(nom) {
  const teinte = (nom.split("").reduce((a, c) => a + c.charCodeAt(0), 0) * 37) % 360;
  return "<svg xmlns='http://www.w3.org/2000/svg' width='600' height='600'>" +
    "<rect width='600' height='600' fill='hsl(" + teinte + ",55%,85%)'/>" +
    "<circle cx='300' cy='260' r='120' fill='hsl(" + teinte + ",55%,65%)'/>" +
    "<rect x='150' y='400' width='300' height='90' rx='20' fill='hsl(" + teinte + ",45%,55%)'/></svg>";
}

async function ouvrir(app, { hash = "", role = "superadministrateur", connecte = true, panier = null, commandes = null, enBoutique = null } = {}) {
  const ctx = await nav.newContext({ viewport: { width: LARGEUR, height: 800 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  const erreurs = [];
  page.on("pageerror", (e) => erreurs.push(e.message));
  await page.addInitScript((a) => {
    localStorage.setItem("impact-config", JSON.stringify({ url: "https://base-absente.invalid", cle: "cle-de-galerie" }));
    localStorage.removeItem("impact-boutique");
    const b64 = (o) => btoa(unescape(encodeURIComponent(JSON.stringify(o)))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
    const session = { access_token: b64({ alg: "HS256" }) + "." + b64({ sub: a.moi }) + ".s", refresh_token: "r", expire_a: Date.now() + 3600000, email: "chef@impact.bj" };
    if (a.app === "admin") {
      if (a.connecte) localStorage.setItem("impact-session", JSON.stringify(session)); else localStorage.removeItem("impact-session");
    } else {
      if (a.connecte) localStorage.setItem("bizzoo-session", JSON.stringify(session)); else localStorage.removeItem("bizzoo-session");
      if (a.panier) localStorage.setItem("bizzoo-panier", JSON.stringify(a.panier));
      if (a.commandes) localStorage.setItem("bizzoo-commandes", JSON.stringify(a.commandes));
      localStorage.setItem("bizzoo-coordonnees", JSON.stringify({ nom: "Koffi Ahouansou", tel: "0197000000", indicatif: "229", adresse: "Cotonou, Fidjrossè" }));
      if (a.enBoutique) localStorage.setItem("impact-boutique", a.enBoutique);
    }
  }, { app, moi: MOI, connecte, panier, commandes, enBoutique });

  await page.route("**/storage/v1/object/public/**", (route) => route.fulfill({ status: 200, contentType: "image/svg+xml", body: photo(route.request().url()) }));
  await page.route("**/auth/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ id: MOI, email: "chef@impact.bj", phone: "22996202098", user_metadata: { nom: "Hospice Soetonve" } }) }));
  await page.route("**/functions/v1/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "{}" }));
  await page.route("**/rest/v1/**", (route) => {
    const req = route.request();
    const u = new URL(req.url());
    const c = u.pathname.replace(/^.*\/rest\/v1\//, "");
    const d = (x, status = 200) => route.fulfill({ status, contentType: "application/json", body: JSON.stringify(x) });
    if (req.method() !== "GET" && !c.startsWith("rpc/")) return route.fulfill({ status: 204, body: "" });
    if (c.startsWith("rpc/")) {
      const nom = c.slice(4);
      return d(nom in RPC ? RPC[nom] : null);
    }
    if (c.startsWith("profils")) {
      const m = /id=eq\.([^&]+)/.exec(u.search);
      const moi = { ...PROFILS[0], role, boutique_id: role === "superadministrateur" || role === "livreur" ? null : "bou_a" };
      if (m && decodeURIComponent(m[1]) === MOI) return d([moi]);
      return d([moi, ...PROFILS.slice(1)]);
    }
    if (c.startsWith("categories")) return d(CATS);
    if (c.startsWith("sous_categories")) return d(CATS.flatMap((k) => k.sous_categories.map((s) => ({ ...s, categorie_id: k.id }))));
    if (c.startsWith("boutiques")) return d(BOUT);
    if (c.startsWith("boutique")) return d([{ id: 1, nom: "BIZZOO", devise: "FCFA", indicatif: "229", whatsapp: "0142323238", tel: "0159045604",
      slogan: "Toutes vos boutiques, une seule application", adresse: "https://maps.app.goo.gl/J5fmn3mDZzuXg_st=aw", horaires: "Lundi - dimanche 24h sur 24h et 7j sur 7j",
      site_web: "www.bizzoomarket.com", facebook: "bizzoo", instagram: "bizzoo", tiktok: "bizzoo", direction_tel: "0195943189", momopay_code: "123456", momopay_nom: "BIZZOO MARKET", taux_acompte: 10 }]);
    if (c.startsWith("produits_prive")) return d(PROD.map((p) => ({ produit_id: p.id, prix_grossiste: Math.round(p.prix * 0.8) })));
    if (c.startsWith("produits")) return d(/produits_prive/.test(u.search) ? PROD.map((p) => ({ ...p, produits_prive: [{ prix_grossiste: Math.round(p.prix * 0.8) }] })) : PROD);
    if (c.startsWith("slides")) return d(SLIDES);
    if (c.startsWith("paiement")) return d([{ id: 1, actif: true, fournisseur: "feexpay", cle_publique: "", bac_a_sable: false, momopay_code: "123456", momopay_nom: "BIZZOO MARKET", taux_acompte: 10 }]);
    if (c.startsWith("reglages")) return d([{ id: 1, compte_obligatoire: false, sms_equipe: false }]);
    if (c.startsWith("commandes")) return d(app === "admin" ? CMD : CMD_CLIENT);
    if (c.startsWith("notifications")) return d(NOTIFS);
    if (c.startsWith("avis")) return d([{ id: 1, produit_id: "1", boutique_id: "bou_a", note: 4, texte: "Très bon ordinateur, livré en deux jours. Le livreur était ponctuel et poli.", auteur: "Marina A.", client_id: "cl1", cree_le: il(2000), reponse: "", masque: false }]);
    if (c.startsWith("reclamations")) return d([{ id: 1, commande_id: "c17", numero: "BZ-000033", boutique_id: "bou_a", etat: "a_repondre", objet: "Article abîmé à la livraison", client_nom: "Sandrine", cree_le: il(500), messages: [{ qui: "client", texte: "Le ludo est arrivé avec la boîte écrasée.", quand: il(500) }] }]);
    if (c.startsWith("historique")) return d([{ id: 1, quand: il(10), qui: "chef@impact.bj", action: "produit_modifie", libelle: "Prix de « " + PROD[0].nom + " » : 320 000 → 299 000 FCFA", details: "", annulee: false }]);
    if (c.startsWith("demandes")) return d([]);
    if (c.startsWith("adresses")) return d([{ id: 1, client_id: MOI, nom: "Maison", adresse: "Fidjrossè, derrière la pharmacie Sainte Rita, maison bleue", tel: "0197000000", defaut: true }]);
    if (c.startsWith("favoris")) return d([{ produit_id: "1" }, { produit_id: "8" }]);
    if (c.startsWith("clients")) return d([{ id: MOI, nom: "Koffi Ahouansou", tel: "0197000000", indicatif: "229", email: "soetonvehospice@gmail.com", revendeur: false, verifie: true, commerce: "", adresse: "Agla" }]);
    if (c.startsWith("encaissements")) return d([]);
    return d([]);
  });
  const url = BASE + "/" + app + "/index.html" + (hash ? hash : "");
  await page.goto(url, { waitUntil: "domcontentloaded" });
  await page.waitForTimeout(1800);
  if (hash) {
    /* Une seconde fois : l'application a pu rediriger (connexion, boutique). */
    await page.evaluate((h) => { if (location.hash !== h) location.hash = h; }, hash);
    await page.waitForTimeout(1400);
  }
  return { page, ctx, erreurs };
}

/* LE ZOOM DU TÉLÉPHONE, rejoué : chaque élément reçoit sa taille
   calculée × ZOOM, une seule fois, puis on laisse le navigateur
   remettre la page en page. */
async function zoomer(page) {
  if (ZOOM === 1) return;
  await page.evaluate((z) => {
    const els = [...document.querySelectorAll("body *")].filter((el) => !(el instanceof SVGElement));
    const tailles = els.map((el) => parseFloat(getComputedStyle(el).fontSize));
    els.forEach((el, i) => { el.style.fontSize = (tailles[i] * z).toFixed(2) + "px"; });
  }, ZOOM);
  await page.waitForTimeout(350);
}

/* Ce qu'une capture ne dit pas : mesuré sur l'écran lui-même. */
async function mesurer(page) {
  return page.evaluate(() => {
    const vp = window.innerWidth;
    const visible = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
    const nomme = (el) => el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") + (el.className && typeof el.className === "string" ? "." + el.className.trim().split(/\s+/).slice(0, 2).join(".") : "");
    /* Une rangée qui défile de côté (produits, puces) déborde exprès :
       ce qu'elle contient ne compte pas. */
    const dansUnDefilement = (el) => {
      for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
        const o = getComputedStyle(p).overflowX;
        if (o === "auto" || o === "scroll") return true;
      }
      return false;
    };
    const deborde = [...document.querySelectorAll("body *")].filter((el) => !(el instanceof SVGElement) && visible(el) && !dansUnDefilement(el))
      .map((el) => ({ el, r: el.getBoundingClientRect() })).filter((x) => x.r.right > vp + 1 || x.r.left < -1)
      .sort((a, b) => (b.r.right - vp) - (a.r.right - vp)).slice(0, 6)
      .map((x) => nomme(x.el) + " (" + Math.round(x.r.right - vp) + " px au-delà, « " + (x.el.textContent || "").trim().slice(0, 30) + " »)");
    const lignesTexte = (el) => {
      let n = 0;
      const marche = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
      const hauts = new Set();
      while (marche.nextNode()) {
        const t = marche.currentNode;
        if (!t.textContent.trim()) continue;
        const r = document.createRange(); r.selectNodeContents(t);
        for (const q of r.getClientRects()) if (q.height) hauts.add(Math.round(q.top / 4));
      }
      n = hauts.size;
      return n;
    };
    const boutons = [...document.querySelectorAll(".btn, .btn-mini, .puce")]
      .filter(visible).filter((b) => lignesTexte(b) > 1).map((b) => nomme(b) + " « " + (b.textContent || "").trim().replace(/\s+/g, " ").slice(0, 40) + " »");
    /* Un bouton qui porte autre chose qu'une icône et des mots (un bloc
       de deux lignes, un champ) se dessine en flex, pas en ligne : on
       les nomme pour vérifier chacun à l'œil. Et une icône APRÈS le
       texte doit porter « ic-apres » pour que l'écart soit du bon côté. */
    const composes = [...document.querySelectorAll(".btn")].filter(visible)
      .filter((b) => [...b.children].some((c) => !(c instanceof SVGElement) && c.tagName !== "INPUT"))
      .map((b) => nomme(b));
    const iconesApres = [...document.querySelectorAll(".btn > svg")].filter((s) => visible(s.parentElement))
      .filter((s) => { let t = s.previousSibling; while (t && t.nodeType === 3 && !t.textContent.trim()) t = t.previousSibling; return t && t.nodeType === 3; })
      .filter((s) => !s.classList.contains("ic-apres")).map((s) => nomme(s.parentElement));
    const titres = [...document.querySelectorAll(".topbar h1")].filter(visible).filter((h) => h.scrollWidth > h.clientWidth + 1)
      .map((h) => "« " + h.textContent.trim() + " »");
    const coupes = [...document.querySelectorAll("body *")].filter((el) => !(el instanceof SVGElement) && visible(el))
      .filter((el) => { const s = getComputedStyle(el); return s.textOverflow === "ellipsis" && s.whiteSpace === "nowrap" && el.scrollWidth > el.clientWidth + 1 && !el.closest(".topbar"); })
      .slice(0, 8).map((el) => nomme(el) + " « " + el.textContent.trim().slice(0, 30) + " »");
    const fixes = [...document.querySelectorAll(".tabbar, .barre-action, .topbar")].filter(visible)
      .filter((el) => el.getBoundingClientRect().width > vp + 1).map(nomme);
    return { largeurPage: document.documentElement.scrollWidth, viewport: vp, deborde, boutons, titres, coupes, fixes,
      composes, iconesApres, hauteur: document.documentElement.scrollHeight };
  });
}

const ECRANS = [
  /* ---------- L'application des clients ---------- */
  ["client-accueil", "client", { hash: "#/" }],
  ["client-accueil-deconnecte", "client", { hash: "#/", connecte: false }],
  ["client-boutiques", "client", { hash: "#/boutiques" }],
  ["client-boutique", "client", { hash: "#/boutique/bou_a" }],
  ["client-boutique-produits", "client", { hash: "#/boutique/bou_a/produits", enBoutique: "bou_a" }],
  ["client-categories", "client", { hash: "#/categories" }],
  ["client-rayon", "client", { hash: "#/categorie/cat_hightech" }],
  ["client-produits", "client", { hash: "#/produits" }],
  ["client-produit", "client", { hash: "#/produit/1" }],
  ["client-produit-commande", "client", { hash: "#/produit/3" }],
  ["client-recherche", "client", { hash: "#/recherche" }],
  ["client-favoris", "client", { hash: "#/favoris" }],
  ["client-panier", "client", { hash: "#/panier", panier: [{ produitId: "1", quantite: 1 }, { produitId: "8", quantite: 2 }, { produitId: "7", quantite: 3 }] }],
  ["client-paiement", "client", { hash: "#/commande", panier: [{ produitId: "1", quantite: 1 }, { produitId: "7", quantite: 1 }] }],
  ["client-recu", "client", { hash: "#/commande/c17", commandes: CMD_CLIENT }],
  ["client-mes-commandes", "client", { hash: "#/mes-commandes", commandes: CMD_CLIENT }],
  ["client-compte", "client", { hash: "#/compte" }],
  ["client-connexion", "client", { hash: "#/connexion", connecte: false }],
  ["client-connexion-tel", "client", { hash: "#/connexion-tel", connecte: false }],
  ["client-inscription", "client", { hash: "#/inscription", connecte: false }],
  ["client-notifications", "client", { hash: "#/notifications" }],
  ["client-adresses", "client", { hash: "#/adresses" }],
  ["client-infos", "client", { hash: "#/infos" }],
  ["client-reclamations", "client", { hash: "#/reclamations" }],
  ["client-promos", "client", { hash: "#/promos" }],
  /* ---------- L'application de l'équipe ---------- */
  ["admin-connexion", "admin", { hash: "#/", connecte: false }],
  ["admin-accueil", "admin", { hash: "#/" }],
  ["admin-accueil-boutique", "admin", { hash: "#/", role: "administrateur" }],
  ["admin-produits", "admin", { hash: "#/produits" }],
  ["admin-stock", "admin", { hash: "#/stock" }],
  ["admin-produit", "admin", { hash: "#/produit/1" }],
  ["admin-produit-nouveau", "admin", { hash: "#/produit/nouveau" }],
  ["admin-produit-modifier", "admin", { hash: "#/produit/1/modifier" }],
  ["admin-categories", "admin", { hash: "#/categories" }],
  ["admin-commandes", "admin", { hash: "#/commandes" }],
  ["admin-commandes-boutique", "admin", { hash: "#/commandes", role: "administrateur" }],
  ["admin-notifications", "admin", { hash: "#/notifications" }],
  ["admin-boutiques", "admin", { hash: "#/boutiques" }],
  ["admin-slider", "admin", { hash: "#/slider" }],
  ["admin-validations", "admin", { hash: "#/validations" }],
  ["admin-revendeurs", "admin", { hash: "#/revendeurs" }],
  ["admin-clients", "admin", { hash: "#/clients" }],
  ["admin-versements", "admin", { hash: "#/versements" }],
  ["admin-caisse", "admin", { hash: "#/caisse" }],
  ["admin-solde", "admin", { hash: "#/solde", role: "administrateur" }],
  ["admin-reversements", "admin", { hash: "#/reversements" }],
  ["admin-codes", "admin", { hash: "#/codes" }],
  ["admin-livraisons", "admin", { hash: "#/livraisons", role: "livreur" }],
  ["admin-avis", "admin", { hash: "#/avis" }],
  ["admin-sav", "admin", { hash: "#/sav" }],
  ["admin-statistiques", "admin", { hash: "#/statistiques" }],
  ["admin-historique", "admin", { hash: "#/historique" }],
  ["admin-comptes", "admin", { hash: "#/comptes" }],
  ["admin-livreurs", "admin", { hash: "#/livreurs" }],
  ["admin-compte", "admin", { hash: "#/compte", role: "moderateur" }],
  ["admin-reglages", "admin", { hash: "#/reglages" }],
  ["admin-reglages-boutique", "admin", { hash: "#/reglages", role: "administrateur" }],
];

const rapport = {};
for (const [nom, app, options] of ECRANS) {
  if (SEUL && !nom.includes(SEUL)) continue;
  const { page, ctx, erreurs } = await ouvrir(app, options);
  await zoomer(page);
  const m = await mesurer(page);
  const fichier = path.join(DOSSIER, nom + (ZOOM !== 1 ? "-z" + String(ZOOM).replace(".", "") : "") + ".png");
  /* L'écran prend la hauteur de la page avant la capture : les barres
     fixes (onglets, action du bas) se posent ainsi tout en bas de
     l'image, et non au milieu, là où finissait le premier écran. */
  const hauteur = Math.max(600, Math.min(m.hauteur, 2600));
  await page.setViewportSize({ width: LARGEUR, height: hauteur });
  await page.waitForTimeout(150);
  await page.screenshot({ path: fichier, clip: { x: 0, y: 0, width: LARGEUR, height: hauteur } });
  rapport[nom] = { ...m, erreurs, fichier };
  const soucis = [];
  if (m.largeurPage > m.viewport) soucis.push("DÉBORDE de " + (m.largeurPage - m.viewport) + " px");
  if (m.fixes.length) soucis.push("barre plus large que l'écran : " + m.fixes.join(", "));
  if (m.boutons.length) soucis.push(m.boutons.length + " bouton(s) sur deux lignes");
  if (m.titres.length) soucis.push("titre coupé " + m.titres.join(" "));
  if (m.coupes.length) soucis.push(m.coupes.length + " texte(s) coupé(s)");
  if (m.iconesApres.length) soucis.push("icône après le texte sans « ic-apres » : " + m.iconesApres.join(", "));
  if (erreurs.length) soucis.push("ERREUR JS : " + erreurs[0].slice(0, 80));
  console.log((soucis.length ? "  !!  " : "  ok  ") + nom.padEnd(30) + (soucis.length ? soucis.join(" ; ") : ""));
  for (const d of m.deborde.slice(0, 3)) console.log("         ↳ " + d);
  for (const b of m.boutons.slice(0, 4)) console.log("         ↳ bouton " + b);
  for (const c of m.composes.slice(0, 4)) console.log("         ↳ bouton composé " + c);
  await ctx.close();
}
fs.writeFileSync(path.join(DOSSIER, "rapport" + (ZOOM !== 1 ? "-z" + String(ZOOM).replace(".", "") : "") + ".json"), JSON.stringify(rapport, null, 1));
await nav.close();
console.log("\nCaptures dans " + path.resolve(DOSSIER));
