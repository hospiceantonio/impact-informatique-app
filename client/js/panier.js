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

  function lireBrut() {
    try {
      const brut = JSON.parse(localStorage.getItem(CLE) || "[]");
      if (!Array.isArray(brut)) return [];
      return brut
        .map((l) => ({
          produitId: String((l && l.produitId) || ""),
          quantite: Math.max(1, Math.min(MAX_QUANTITE, Math.round(Number(l && l.quantite) || 1))),
        }))
        .filter((l) => l.produitId);
    } catch (_) {
      return [];   // navigation privée, ou contenu abîmé
    }
  }

  function ecrire(lignes) {
    try {
      localStorage.setItem(CLE, JSON.stringify(lignes));
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
        return produit ? { produit, quantite: l.quantite } : null;
      })
      .filter(Boolean);
  }

  const vide = () => !lignes().length;
  const nombre = () => lignes().reduce((somme, l) => somme + l.quantite, 0);
  const contient = (id) => lireBrut().some((l) => l.produitId === id);
  const quantiteDe = (id) => {
    const ligne = lireBrut().find((l) => l.produitId === id);
    return ligne ? ligne.quantite : 0;
  };

  const total = () => lignes().reduce((somme, l) => somme + (l.produit.prix || 0) * l.quantite, 0);

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
      groupe.montant += (ligne.produit.prix || 0) * ligne.quantite;
    }
    return [...table.values()].sort((a, b) => b.montant - a.montant);
  }

  /** Ce qui part à la base : des identifiants et des quantités, rien d'autre. */
  const articles = () =>
    lignes().map((l) => ({ produit_id: l.produit.id, quantite: l.quantite }));

  /* ---------- Modifier le panier ---------- */

  /** Renvoie false si le panier est déjà plein. */
  function ajouter(produitId, combien) {
    const lignesActuelles = lireBrut();
    const qte = Math.max(1, Math.round(Number(combien) || 1));
    const existante = lignesActuelles.find((l) => l.produitId === produitId);
    if (existante) {
      existante.quantite = Math.min(MAX_QUANTITE, existante.quantite + qte);
    } else {
      if (lignesActuelles.length >= MAX_ARTICLES) return false;
      lignesActuelles.push({ produitId, quantite: Math.min(MAX_QUANTITE, qte) });
    }
    ecrire(lignesActuelles);
    return true;
  }

  /** Poser une quantité ; à zéro, la ligne s'en va. */
  function regler(produitId, quantite) {
    const voulue = Math.round(Number(quantite) || 0);
    if (voulue <= 0) return retirer(produitId);
    const lignesActuelles = lireBrut();
    const ligne = lignesActuelles.find((l) => l.produitId === produitId);
    if (!ligne) return false;
    ligne.quantite = Math.min(MAX_QUANTITE, voulue);
    ecrire(lignesActuelles);
    return true;
  }

  function retirer(produitId) {
    ecrire(lireBrut().filter((l) => l.produitId !== produitId));
    return true;
  }

  const vider = () => ecrire([]);

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

  /** L'état vient de la base, jamais du téléphone : on ne fait que le noter. */
  function majEtat(id, etat, extra) {
    const liste = mesCommandes();
    const c = liste.find((x) => x.id === id);
    if (!c) return null;
    c.etat = etat;
    Object.assign(c, extra || {});
    ecrireCommandes(liste);
    return c;
  }

  return {
    MAX_ARTICLES, MAX_QUANTITE,
    lignes, vide, nombre, contient, quantiteDe, total, devise,
    monnaiesMelangees, parBoutique, articles,
    ajouter, regler, retirer, vider,
    mesCommandes, memoriser, commande, majEtat,
  };
})();
