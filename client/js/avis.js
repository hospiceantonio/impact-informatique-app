/* =========================================================
   BIZZOO — les avis

   Une note de 1 à 5 et quelques mots, sur un produit ou sur une
   boutique. Trois choses à savoir avant de lire :

   1. LES AVIS SE LISENT SANS COMPTE. C'est tout leur intérêt :
      un avis que seuls les inscrits peuvent lire ne sert à
      personne. La lecture passe donc par la clé publiable, comme
      le catalogue.

   2. ON N'EN DÉPOSE PAS D'ICI. « deposer_avis » est une fonction
      de la base : elle vérifie que l'achat a été PAYÉ, et relit
      la boutique dans le catalogue plutôt que de croire ce qu'on
      lui envoie. Ce module ne fait que lui parler.

   3. LA NOTE MOYENNE NE SE CALCULE PAS ICI. Elle vit sur le
      produit et sur la boutique, tenue par la base. L'écran la
      lit, il ne l'additionne pas — sinon il faudrait charger
      tous les avis de tous les produits pour dessiner une carte.
   ========================================================= */

const Avis = (() => {

  /** Lecture publique : la clé publiable suffit, et c'est voulu. */
  async function lire(chemin) {
    const c = Catalogue.configuration();
    if (!c) return [];
    let reponse;
    try {
      reponse = await fetch(c.url + "/rest/v1/" + chemin, {
        headers: { "apikey": c.cle },
      });
    } catch (_) {
      return [];   // hors connexion : pas d'avis, pas d'erreur à l'écran
    }
    if (!reponse.ok) return [];
    return (await reponse.json().catch(() => [])) || [];
  }

  const CHAMPS = "id,client_id,note,texte,auteur,reponse,reponse_le,cree_le,maj_le";

  /* Masquer un auteur est un choix personnel, conservé sur cet appareil.
     Cela fonctionne aussi pour les visiteurs, sans exposer leur identité. */
  const cleAuteurs = () => "bizzoo-auteurs-masques:" +
    ((typeof Compte !== "undefined" && Compte.identifiant()) || "visiteur");
  const secoursAuteurs = new Map();

  function auteursMasques() {
    try {
      const liste = JSON.parse(localStorage.getItem(cleAuteurs()) || "[]");
      return Array.isArray(liste)
        ? liste.filter((a) => a && typeof a.id === "string").slice(0, 100)
        : [];
    } catch (_) { return secoursAuteurs.get(cleAuteurs()) || []; }
  }

  function garderAuteurs(liste) {
    secoursAuteurs.set(cleAuteurs(), liste.slice(0, 100));
    try { localStorage.setItem(cleAuteurs(), JSON.stringify(liste.slice(0, 100))); }
    catch (_) { /* le masquage vaut au moins pour cette session */ }
  }

  function masquerAuteur(id, nom) {
    const liste = auteursMasques().filter((a) => a.id !== id);
    liste.unshift({ id, nom: String(nom || "Auteur").slice(0, 40) });
    garderAuteurs(liste);
  }

  function revoirAuteur(id) {
    garderAuteurs(auteursMasques().filter((a) => a.id !== id));
  }

  /** Les avis d'un produit, les plus récents d'abord. */
  const duProduit = (id) =>
    lire("avis?select=" + CHAMPS + "&produit_id=eq." + encodeURIComponent(id) +
         "&order=cree_le.desc&limit=50");

  /** Les avis d'une boutique — ceux qui la visent ELLE, pas ses produits. */
  const deLaBoutique = (id) =>
    lire("avis?select=" + CHAMPS + "&boutique_id=eq." + encodeURIComponent(id) +
         "&produit_id=is.null&order=cree_le.desc&limit=50");

  /**
   * Ce compte a-t-il le droit de donner son avis ici ?
   *
   * La question est posée À LA BASE, qui vérifie une commande PAYÉE.
   * L'écran ne fait que ne pas proposer un formulaire qui serait de
   * toute façon refusé — la serrure est ailleurs.
   */
  async function peutDonner(produitId, boutiqueId) {
    if (typeof Compte === "undefined" || !Compte.connecte()) return false;
    try {
      return await Compte.rpc("a_achete", {
        cible_produit: produitId || null,
        cible_boutique: boutiqueId || null,
      }) === true;
    } catch (_) {
      return false;
    }
  }

  /** Déposer, ou modifier : la base range les deux au même endroit. */
  async function deposer({ produit, boutique, note, texte }) {
    return Compte.rpc("deposer_avis", {
      cible_produit: produit || null,
      cible_boutique: boutique || null,
      note: Number(note) || 0,
      texte: String(texte || ""),
    });
  }

  /** Retirer le sien. On a le droit de se taire. */
  const retirer = (id) => Compte.rpc("retirer_mon_avis", { cible: id });

  /** Un avis ou son auteur est porté à la connaissance de la modération. */
  const signaler = (id, cible, motif, details) => Compte.rpc("signaler_avis", {
    avis_cible: id, cible_signalee: cible, motif_signalement: motif,
    precisions: String(details || "").slice(0, 500),
  });

  /** Le mien dans une liste, s'il y est — pour proposer de le modifier. */
  function lemien(liste) {
    if (typeof Compte === "undefined" || !Compte.connecte()) return null;
    const moi = Compte.identifiant();
    return (liste || []).find((a) => a.client_id === moi) || null;
  }

  return { duProduit, deLaBoutique, peutDonner, deposer, retirer, lemien,
    signaler, auteursMasques, masquerAuteur, revoirAuteur };
})();
