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

  /** Le mien dans une liste, s'il y est — pour proposer de le modifier. */
  function lemien(liste) {
    if (typeof Compte === "undefined" || !Compte.connecte()) return null;
    const moi = Compte.identifiant();
    return (liste || []).find((a) => a.client_id === moi) || null;
  }

  return { duProduit, deLaBoutique, peutDonner, deposer, retirer, lemien };
})();
