/* =========================================================
   BIZZOO — ce que le client met de côté

   Les favoris, les boutiques suivies, et les adresses de
   livraison. Trois listes qui n'appartiennent qu'à lui : la base
   les ferme à tout le monde d'autre, y compris à l'enseigne.

   Trois choses méritent d'être sues avant de lire ce module :

   1. IL FAUT UN COMPTE. Un favori se range dans la base, pas
      dans le téléphone — sans quoi il disparaîtrait au premier
      changement d'appareil, ce qui est précisément ce qu'on
      cherche à éviter. Sans compte, le cœur invite à se
      connecter plutôt que de faire semblant.

   2. LE CŒUR RÉPOND AVANT LA BASE. Un aller-retour réseau à
      Cotonou prend parfois deux secondes ; un cœur qui attend
      deux secondes donne l'impression d'un bouton cassé, et le
      client appuie une seconde fois. On peint donc tout de
      suite, et on remet en place si la base refuse.

   3. LA LISTE SE GARDE EN MÉMOIRE, pas dans le téléphone. Elle
      est courte, elle se relit en une requête, et la garder
      ailleurs ferait vivre deux vérités — celle de l'écran et
      celle de la base.
   ========================================================= */

const Favoris = (() => {
  /* Ce que la base nous a dit la dernière fois. Deux ensembles :
     on y cherche par identifiant, et c'est tout ce qu'on en demande. */
  let produits = null;     // Set d'identifiants, ou null tant qu'on n'a pas lu
  let boutiques = null;
  const ecouteurs = [];

  function prevenir() {
    ecouteurs.forEach((f) => { try { f(); } catch (_) { /* un écran parti */ } });
  }

  /** S'abonner aux changements : les cœurs de l'écran se repeignent. */
  function surChangement(f) {
    ecouteurs.push(f);
    return () => {
      const i = ecouteurs.indexOf(f);
      if (i >= 0) ecouteurs.splice(i, 1);
    };
  }

  /* ---------- Lire ---------- */

  /**
   * Charger les deux listes. Sans compte, elles sont vides — et c'est
   * la vérité, pas un repli : un visiteur n'a pas de favoris.
   */
  async function charger(relire) {
    if (!Compte.connecte()) { produits = new Set(); boutiques = new Set(); return; }
    if (produits && boutiques && !relire) return;
    try {
      const [pf, bf] = await Promise.all([
        Compte.rest("GET", "favoris?select=produit_id"),
        Compte.rest("GET", "boutiques_suivies?select=boutique_id"),
      ]);
      produits = new Set((pf || []).map((l) => l.produit_id));
      boutiques = new Set((bf || []).map((l) => l.boutique_id));
    } catch (_) {
      /* Hors connexion : on ne sait pas, et on ne prétend pas savoir.
         Les cœurs restent vides plutôt que d'annoncer un faux « non ». */
      produits = produits || new Set();
      boutiques = boutiques || new Set();
    }
    prevenir();
  }

  function aProduit(id) { return !!produits && produits.has(id); }
  function aBoutique(id) { return !!boutiques && boutiques.has(id); }
  function nombreProduits() { return produits ? produits.size : 0; }
  function nombreBoutiques() { return boutiques ? boutiques.size : 0; }

  /** Les identifiants, du dernier ajouté au premier. */
  async function listeProduits() {
    if (!Compte.connecte()) return [];
    const l = await Compte.rest("GET",
      "favoris?select=produit_id&order=cree_le.desc");
    produits = new Set((l || []).map((x) => x.produit_id));
    return (l || []).map((x) => x.produit_id);
  }

  async function listeBoutiques() {
    if (!Compte.connecte()) return [];
    const l = await Compte.rest("GET",
      "boutiques_suivies?select=boutique_id&order=cree_le.desc");
    boutiques = new Set((l || []).map((x) => x.boutique_id));
    return (l || []).map((x) => x.boutique_id);
  }

  /* ---------- Écrire ---------- */

  /* Le corps de l'écriture. « client_id » part avec la ligne parce que
     PostgREST l'exige ; la base, elle, ne le croit pas sur parole — sa
     règle veut que cette colonne soit celle du compte connecté, et
     refuse tout le reste. On n'envoie donc jamais autre chose. */
  function moi() {
    const id = Compte.identifiant();
    if (!id) throw new Error("Connectez-vous pour garder vos favoris.");
    return id;
  }

  /**
   * Basculer un produit. Rend l'état APRÈS le geste, pour que l'appelant
   * sache quoi dire — « ajouté » ou « retiré ».
   */
  async function basculerProduit(id) {
    if (!Compte.connecte()) throw new Error("Connectez-vous pour garder vos favoris.");
    if (!produits) await charger();
    const avait = produits.has(id);

    /* On peint d'abord : voir plus haut, un cœur qui attend le réseau
       passe pour un bouton cassé. */
    if (avait) produits.delete(id); else produits.add(id);
    prevenir();

    try {
      if (avait) {
        await Compte.rest("DELETE",
          "favoris?produit_id=eq." + encodeURIComponent(id));
      } else {
        await Compte.rest("POST", "favoris",
          { client_id: moi(), produit_id: id });
      }
    } catch (e) {
      /* La base a refusé : on remet l'écran dans l'état vrai, sinon le
         client croirait son favori enregistré et ne le retrouverait
         pas demain. */
      if (avait) produits.add(id); else produits.delete(id);
      prevenir();
      throw e;
    }
    return !avait;
  }

  async function basculerBoutique(id) {
    if (!Compte.connecte()) throw new Error("Connectez-vous pour suivre une boutique.");
    if (!boutiques) await charger();
    const avait = boutiques.has(id);
    if (avait) boutiques.delete(id); else boutiques.add(id);
    prevenir();
    try {
      if (avait) {
        await Compte.rest("DELETE",
          "boutiques_suivies?boutique_id=eq." + encodeURIComponent(id));
      } else {
        await Compte.rest("POST", "boutiques_suivies",
          { client_id: moi(), boutique_id: id });
      }
    } catch (e) {
      if (avait) boutiques.add(id); else boutiques.delete(id);
      prevenir();
      throw e;
    }
    return !avait;
  }

  /* ---------- Les adresses de livraison ---------- */

  /**
   * Les adresses du client, celle par défaut d'abord.
   *
   * L'ordre n'est pas cosmétique : le formulaire de commande prend la
   * première, et c'est ainsi que « par défaut » veut dire quelque chose.
   */
  async function adresses() {
    if (!Compte.connecte()) return [];
    const l = await Compte.rest("GET",
      "adresses?select=*&order=par_defaut.desc,cree_le.desc");
    return (l || []).map((a) => ({
      id: a.id, libelle: a.libelle || "", texte: a.texte || "",
      ville: a.ville || "", parDefaut: !!a.par_defaut,
    }));
  }

  /** Celle que le formulaire de commande doit proposer, ou null. */
  async function adresseParDefaut() {
    const l = await adresses();
    return l.length ? l[0] : null;
  }

  function identifiantAdresse() {
    return "adr_" + Date.now().toString(36) +
           Math.random().toString(36).slice(2, 8);
  }

  /**
   * Enregistrer une adresse, nouvelle ou modifiée.
   *
   * « par_defaut » se contente d'être envoyé : c'est la BASE qui décoche
   * l'ancienne, par un déclencheur. Le faire ici demanderait deux
   * écritures, et un réseau qui lâche entre les deux laisserait le
   * client avec deux adresses par défaut — ou aucune.
   */
  async function enregistrerAdresse(a) {
    const texte = (a.texte || "").trim();
    if (!texte) throw new Error("Écrivez l'adresse où livrer.");
    const ligne = {
      client_id: moi(),
      libelle: (a.libelle || "").trim().slice(0, 40),
      texte: texte.slice(0, 300),
      ville: (a.ville || "").trim().slice(0, 80),
      par_defaut: !!a.parDefaut,
    };
    if (a.id) {
      await Compte.rest("PATCH",
        "adresses?id=eq." + encodeURIComponent(a.id), ligne);
      return a.id;
    }
    ligne.id = identifiantAdresse();
    await Compte.rest("POST", "adresses", ligne);
    return ligne.id;
  }

  async function supprimerAdresse(id) {
    await Compte.rest("DELETE", "adresses?id=eq." + encodeURIComponent(id));
  }

  /** Cocher celle-ci comme adresse par défaut. */
  async function choisirParDefaut(id) {
    await Compte.rest("PATCH", "adresses?id=eq." + encodeURIComponent(id),
      { par_defaut: true });
  }

  /* Se déconnecter vide les listes : les favoris du compte précédent
     n'ont rien à faire devant les yeux du suivant. */
  if (typeof Compte !== "undefined" && Compte.surChangement) {
    Compte.surChangement(() => {
      produits = null; boutiques = null;
      charger(true);
    });
  }

  return {
    charger, surChangement,
    aProduit, aBoutique, nombreProduits, nombreBoutiques,
    listeProduits, listeBoutiques,
    basculerProduit, basculerBoutique,
    adresses, adresseParDefaut, enregistrerAdresse,
    supprimerAdresse, choisirParDefaut,
  };
})();
