/* =========================================================
   Panier — ce que le client a mis de côté.

   Le panier ne retient QUE des identifiants et des quantités.
   Jamais un prix : celui qui compte est celui du catalogue au
   moment de commander, et c'est la base qui le relira de toute
   façon. Un panier laissé ouvert une semaine ne fige donc pas
   un tarif périmé.

   Les commandes passées sont gardées à côté, sur le téléphone :
   c'est le reçu du client, et de quoi suivre ce qu'il attend.
   ========================================================= */
const Panier = (() => {

  const CLE = "bizzoo-panier";
  const CLE_COMMANDES = "bizzoo-commandes";
  const MAX_ARTICLES = 40;   // articles différents — la base refuse au-delà
  const MAX_QUANTITE = 99;
  const MAX_COMMANDES = 20;  // au-delà, on oublie les plus anciennes

  /* ---------- Ce qui est gardé sur le téléphone ---------- */

  /* (3.80.0) LES ACCOMPAGNEMENTS d'une ligne : { riz: 2, alloco: 1 }. Deux
     choix différents du même plat font deux lignes ; le même choix
     s'additionne. La clé d'une ligne sans accompagnement reste l'identifiant
     du produit, comme avant. */
  function nettoyerAcc(acc) {
    const propre = {};
    if (acc && typeof acc === "object") {
      for (const [id, q] of Object.entries(acc)) {
        const n = Math.max(0, Math.min(20, Math.round(Number(q) || 0)));
        if (id && n) propre[String(id)] = n;
      }
    }
    return propre;
  }
  const cleDe = (produitId, acc) => {
    const ids = Object.keys(acc || {}).filter((id) => acc[id] > 0).sort();
    return ids.length ? produitId + "~" + ids.map((id) => id + ":" + acc[id]).join(",") : produitId;
  };
  /** Les accompagnements choisis, relus sur le catalogue (nom, prix) ; ceux qui n'existent plus tombent. */
  function accompagnementsDe(produit, acc) {
    const offre = (produit && produit.accompagnements) || [];
    return offre.filter((a) => (acc || {})[a.id] > 0)
      .map((a) => ({ id: a.id, nom: a.nom, prix: a.prix, quantite: Math.min(a.max, acc[a.id]) }));
  }
  const supplementDe = (accs) => accs.reduce((s, a) => s + a.prix * a.quantite, 0);

  function lireBrut() {
    try {
      const brut = JSON.parse(localStorage.getItem(CLE) || "[]");
      if (!Array.isArray(brut)) return [];
      return brut
        .map((l) => ({
          produitId: String((l && l.produitId) || ""),
          quantite: Math.max(1, Math.min(MAX_QUANTITE, Math.round(Number(l && l.quantite) || 1))),
          /* (3.80.0) Les accompagnements choisis : { id: quantité }. */
          acc: nettoyerAcc(l && l.acc),
        }))
        .filter((l) => l.produitId);
    } catch (_) {
      return [];   // navigation privée, ou contenu abîmé
    }
  }

  function ecrire(lignes) {
    try {
      localStorage.setItem(CLE, JSON.stringify(lignes.map((l) =>
        (l.acc && Object.keys(l.acc).length ? l : { produitId: l.produitId, quantite: l.quantite }))));
    } catch (_) { /* stockage plein : le panier vivra le temps de la visite */ }
    document.dispatchEvent(new CustomEvent("panier:maj"));
  }

  /* ---------- Ce que le client voit ----------
     Un produit retiré du catalogue disparaît du panier de lui-même :
     mieux vaut une ligne en moins qu'une commande impossible à
     honorer. */

  function lignes() {
    return lireBrut()
      .map((l) => {
        const produit = Catalogue.produit(l.produitId);
        if (!produit) return null;
        const accompagnements = accompagnementsDe(produit, l.acc);
        return { cle: cleDe(l.produitId, l.acc), produit, quantite: l.quantite, accompagnements,
                 /* Le prix d'une portion, accompagnements compris. */
                 prixUnitaire: (produit.prix || 0) + supplementDe(accompagnements) };
      })
      .filter(Boolean);
  }

  const vide = () => !lignes().length;
  const nombre = () => lignes().reduce((somme, l) => somme + l.quantite, 0);
  const contient = (id) => lireBrut().some((l) => l.produitId === id);
  /** La quantité d'une ligne (par sa clé) ; ou, pour un produit, de toutes ses lignes. */
  const quantiteDe = (id) => {
    const brut = lireBrut();
    const ligne = brut.find((l) => cleDe(l.produitId, l.acc) === id);
    if (ligne) return ligne.quantite;
    return brut.filter((l) => l.produitId === id).reduce((s, l) => s + l.quantite, 0);
  };

  const total = () => lignes().reduce((somme, l) => somme + l.prixUnitaire * l.quantite, 0);

  /** La monnaie du panier : celle des boutiques concernées. */
  function devise() {
    const premiere = lignes()[0];
    return premiere ? Catalogue.deviseDe(premiere.produit) : Catalogue.boutique().devise;
  }

  /**
   * Deux boutiques qui ne comptent pas dans la même monnaie ne se
   * paient pas d'un seul versement — la base refuse, autant le dire
   * avant.
   */
  function monnaiesMelangees() {
    const monnaies = new Set(lignes().map((l) => Catalogue.deviseDe(l.produit)));
    return monnaies.size > 1;
  }

  /** Le panier rangé par boutique : c'est ainsi qu'il se prépare et se règle. */
  function parBoutique() {
    const table = new Map();
    for (const ligne of lignes()) {
      const b = Catalogue.boutiqueDuProduit(ligne.produit);
      const id = (b && b.id) || "";
      if (!table.has(id)) {
        table.set(id, { boutique: b, lignes: [], montant: 0 });
      }
      const groupe = table.get(id);
      groupe.lignes.push(ligne);
      groupe.montant += ligne.prixUnitaire * ligne.quantite;
    }
    return [...table.values()].sort((a, b) => b.montant - a.montant);
  }

  /** Ce qui part à la base : des identifiants et des quantités, rien d'autre. */
  const articles = () =>
    lignes().map((l) => (l.accompagnements.length
      ? { produit_id: l.produit.id, quantite: l.quantite,
          accompagnements: l.accompagnements.map((a) => ({ id: a.id, quantite: a.quantite })) }
      : { produit_id: l.produit.id, quantite: l.quantite }));

  /* ---------- Pas plus que ce qui reste ----------
     La base refuse une commande qui dépasse le stock : autant ne pas
     laisser le client remplir un panier qu'on lui refusera au moment
     de payer. Un produit « sur commande » ou en approvisionnement n'a
     pas de stock à suivre — la boutique le fait venir. */

  /** Combien de pièces de ce produit un client peut prendre. */
  function plafond(produit) {
    if (!produit) return 0;
    const statut = Catalogue.statut(produit);
    if (statut === "commande" || statut === "approvisionnement") return MAX_QUANTITE;
    return Math.max(0, Math.min(MAX_QUANTITE, Math.floor(Number(produit.stock) || 0)));
  }

  /* CE QUE LE STOCK A RETIRÉ DU PANIER, gardé jusqu'à ce que le client
     y touche. Une quantité qui baisse en silence ressemble à une erreur ;
     et l'écran se redessine souvent — catalogue relu, retour depuis la
     commande —, le message ne doit pas partir avec le premier dessin. */
  const ramenees = new Map();   // produitId → { produit, avant, apres }
  const oublierRamenees = () => ramenees.clear();

  /**
   * Ramène chaque ligne au stock du moment. Le catalogue a pu changer
   * depuis l'ajout : une autre vente, une boutique qui a recompté sa
   * réserve. Rend ce qui vient de bouger À L'INSTANT — ce qui a bougé
   * avant et que le client n'a pas encore vu, « ramenees() » le rend.
   */
  function ajusterAuStock() {
    const lignesActuelles = lireBrut();
    const nouvelles = [];
    for (const l of lignesActuelles) {
      const produit = Catalogue.produit(l.produitId);
      if (!produit) continue;
      /* Les autres lignes du même produit comptent dans le même stock. */
      const ailleurs = lignesActuelles.filter((x) => x !== l && x.produitId === l.produitId)
        .reduce((s, x) => s + x.quantite, 0);
      const max = Math.max(0, plafond(produit) - ailleurs);
      if (max > 0 && l.quantite > max) {
        const deja = ramenees.get(l.produitId);
        const r = { produit, avant: deja ? deja.avant : l.quantite, apres: max };
        ramenees.set(l.produitId, r);
        nouvelles.push(r);
        l.quantite = max;
      }
    }
    if (nouvelles.length) ecrire(lignesActuelles);
    return nouvelles;
  }

  /** Les quantités ramenées que le client n'a pas encore touchées. */
  const lesRamenees = () => [...ramenees.values()]
    .filter((r) => quantiteDe(r.produit.id) === r.apres);

  /** Les lignes dont il ne reste plus rien : elles empêchent de commander. */
  const enRupture = () => lignes().filter((l) => plafond(l.produit) === 0);

  /* ---------- Modifier le panier ---------- */

  /**
   * Ajoute des pièces, jamais plus que le stock. Rend ce qui s'est
   * passé — { ajoute, plein, plafond } : « ajoute » peut être moindre
   * que la demande, et vaut zéro quand le panier contient déjà tout ce
   * qui reste.
   */
  function ajouter(produitId, combien, acc) {
    const lignesActuelles = lireBrut();
    const qte = Math.max(1, Math.round(Number(combien) || 1));
    const max = plafond(Catalogue.produit(produitId));
    const choix = nettoyerAcc(acc);
    const cle = cleDe(produitId, choix);
    const existante = lignesActuelles.find((l) => cleDe(l.produitId, l.acc) === cle);
    /* Le stock compte toutes les lignes du produit, quels qu'en soient les accompagnements. */
    const deja = lignesActuelles.filter((l) => l.produitId === produitId).reduce((s, l) => s + l.quantite, 0);
    const ajoute = Math.max(0, Math.min(qte, max - deja));
    if (!ajoute) return { ajoute: 0, plein: false, plafond: max };
    if (existante) {
      existante.quantite = existante.quantite + ajoute;
    } else {
      if (lignesActuelles.length >= MAX_ARTICLES) return { ajoute: 0, plein: true, plafond: max };
      lignesActuelles.push(Object.keys(choix).length ? { produitId, quantite: ajoute, acc: choix }
                                                     : { produitId, quantite: ajoute });
    }
    oublierRamenees();
    ecrire(lignesActuelles);
    return { ajoute, plein: false, plafond: max };
  }

  /**
   * Poser une quantité ; à zéro, la ligne s'en va. On peut toujours
   * DESCENDRE ; monter s'arrête au stock, et la réponse est alors false.
   */
  function regler(cle, quantite) {
    const voulue = Math.round(Number(quantite) || 0);
    if (voulue <= 0) return retirer(cle);
    const lignesActuelles = lireBrut();
    const ligne = lignesActuelles.find((l) => cleDe(l.produitId, l.acc) === cle);
    if (!ligne) return false;
    const ailleurs = lignesActuelles.filter((l) => l !== ligne && l.produitId === ligne.produitId)
      .reduce((s, l) => s + l.quantite, 0);
    if (voulue > ligne.quantite && voulue + ailleurs > plafond(Catalogue.produit(ligne.produitId))) return false;
    oublierRamenees();
    ligne.quantite = Math.min(MAX_QUANTITE, voulue);
    ecrire(lignesActuelles);
    return true;
  }

  function retirer(cle) {
    oublierRamenees();
    ecrire(lireBrut().filter((l) => cleDe(l.produitId, l.acc) !== cle));
    return true;
  }

  const vider = () => { oublierRamenees(); ecrire([]); };

  /* ---------- Les commandes passées ----------
     Le reçu du client. Il n'est pas connecté : sans cette trace, il
     n'aurait aucun moyen de retrouver son numéro de commande. */

  function mesCommandes() {
    try {
      const brut = JSON.parse(localStorage.getItem(CLE_COMMANDES) || "[]");
      return Array.isArray(brut) ? brut : [];
    } catch (_) {
      return [];
    }
  }

  function ecrireCommandes(liste) {
    try {
      localStorage.setItem(CLE_COMMANDES, JSON.stringify(liste.slice(0, MAX_COMMANDES)));
    } catch (_) { /* sans importance : la boutique a la sienne */ }
  }

  function memoriser(commande) {
    const liste = mesCommandes().filter((c) => c.id !== commande.id);
    liste.unshift({ ...commande, gardeeLe: Date.now() });
    ecrireCommandes(liste);
  }

  const commande = (id) => mesCommandes().find((c) => c.id === id) || null;

  /** (3.59.0) La commande relue en base remplace la copie du téléphone —
      étapes, livreur, paiement — en gardant sa place dans la liste. Rend
      vrai si quelque chose a changé. */
  function remplacer(fraiche) {
    if (!fraiche || !fraiche.id) return false;
    const liste = mesCommandes();
    const i = liste.findIndex((x) => x.id === fraiche.id);
    if (i < 0) return false;
    const avant = JSON.stringify(liste[i]);
    liste[i] = { ...liste[i], ...fraiche, gardeeLe: liste[i].gardeeLe };
    if (JSON.stringify(liste[i]) === avant) return false;
    ecrireCommandes(liste);
    return true;
  }

  /** L'état vient de la base, jamais du téléphone : on ne fait que le noter. */
  function majEtat(id, etat, extra) {
    const liste = mesCommandes();
    const c = liste.find((x) => x.id === id);
    if (!c) return null;
    const avant = c.etat;
    c.etat = etat;
    Object.assign(c, extra || {});
    ecrireCommandes(liste);
    /* LA BASE vient de confirmer le versement d'une commande passée sur
       ce téléphone : c'est le seul moment où un achat existe. */
    if (etat === "payee" && avant !== "payee" && typeof Pixel !== "undefined") Pixel.achat(c);
    return c;
  }

  return {
    MAX_ARTICLES, MAX_QUANTITE,
    plafond, ajusterAuStock, ramenees: lesRamenees, enRupture,
    lignes, vide, nombre, contient, quantiteDe, total, devise,
    monnaiesMelangees, parBoutique, articles,
    ajouter, regler, retirer, vider,
    mesCommandes, memoriser, commande, majEtat, remplacer,
  };
})();
