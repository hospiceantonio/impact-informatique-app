/* =========================================================
   BIZZOO — le service après-vente, côté client

   LA BOUTIQUE D'ABORD, BIZZOO EN RECOURS. Ce module ne fait
   qu'en parler à la base ; c'est elle qui applique la règle, et
   c'est voulu : un écran ne garde rien.

   Deux portes seulement mènent à l'enseigne — la boutique a
   répondu, ou elle n'a pas répondu passé le délai. L'écran
   n'affiche donc le bouton « BIZZOO » que lorsque la base dit
   qu'il est ouvert (« recours_possible »), et si l'écran se
   trompait, la base refuserait de toute façon.
   ========================================================= */

const SAV = (() => {

  const SUJETS = {
    non_recu: "Je n'ai rien reçu",
    abime: "L'article est abîmé",
    pas_conforme: "Ce n'est pas ce que j'ai commandé",
    incomplet: "Il manque quelque chose",
    autre: "Autre problème",
  };

  const ETATS = {
    ouverte: { nom: "La boutique doit répondre", classe: "sav-attente" },
    repondue: { nom: "La boutique a répondu", classe: "sav-repondue" },
    resolue: { nom: "Réglé", classe: "sav-resolue" },
    escaladee: { nom: "BIZZOO a été saisie", classe: "sav-recours" },
    tranchee: { nom: "BIZZOO a tranché", classe: "sav-tranchee" },
  };

  const CHAMPS = "id,commande_id,boutique_id,produit_id,sujet,etat," +
    "escalade_le,escalade_motif,decision,decide_le,repondu_le,cree_le,maj_le";

  /** Mes réclamations, les plus récentes d'abord. */
  async function mesReclamations() {
    if (typeof Compte === "undefined" || !Compte.connecte()) return [];
    const lignes = await Compte.rest("GET",
      "reclamations?select=" + CHAMPS + "&order=cree_le.desc&limit=50");
    return (lignes || []).map(depuisLigne);
  }

  /** Celles qui portent sur une commande précise. */
  async function pourCommande(id) {
    if (typeof Compte === "undefined" || !Compte.connecte() || !id) return [];
    const lignes = await Compte.rest("GET",
      "reclamations?select=" + CHAMPS + "&commande_id=eq." + encodeURIComponent(id) +
      "&order=cree_le.desc");
    return (lignes || []).map(depuisLigne);
  }

  /** Le fil d'une réclamation : ce qui a été dit, dans l'ordre. */
  async function messages(id) {
    const lignes = await Compte.rest("GET",
      "reclamation_messages?select=id,auteur_role,auteur_nom,texte,cree_le" +
      "&reclamation_id=eq." + encodeURIComponent(id) + "&order=cree_le.asc");
    return lignes || [];
  }

  function depuisLigne(l) {
    return {
      id: l.id,
      commandeId: l.commande_id || "",
      boutiqueId: l.boutique_id || "",
      produitId: l.produit_id || "",
      sujet: l.sujet || "autre",
      etat: l.etat || "ouverte",
      escaladeLe: l.escalade_le ? Date.parse(l.escalade_le) || 0 : 0,
      escaladeMotif: l.escalade_motif || "",
      decision: l.decision || "",
      decideLe: l.decide_le ? Date.parse(l.decide_le) || 0 : 0,
      reponduLe: l.repondu_le ? Date.parse(l.repondu_le) || 0 : 0,
      creeLe: Date.parse(l.cree_le || "") || 0,
      majLe: Date.parse(l.maj_le || "") || 0,
    };
  }

  const ouvrir = (commande, produit, sujet, message) =>
    Compte.rpc("ouvrir_reclamation", {
      commande, produit: produit || null, sujet: sujet || "autre",
      message: String(message || ""),
    });

  const repondre = (cible, message) =>
    Compte.rpc("repondre_reclamation", { cible, message: String(message || "") });

  const clore = (cible) => Compte.rpc("clore_reclamation", { cible });

  const escalader = (cible, motif) =>
    Compte.rpc("escalader_reclamation", { cible, motif: String(motif || "") });

  /**
   * Le recours est-il ouvert ?
   *
   * On DEMANDE à la base plutôt que de recalculer le délai ici : deux
   * horloges finissent toujours par diverger, et celle du téléphone se
   * règle à la main.
   */
  async function recoursPossible(cible) {
    try {
      return await Compte.rpc("recours_possible", { cible }) === true;
    } catch (_) {
      return false;
    }
  }

  return {
    SUJETS, ETATS,
    mesReclamations, pourCommande, messages,
    ouvrir, repondre, clore, escalader, recoursPossible,
  };
})();
