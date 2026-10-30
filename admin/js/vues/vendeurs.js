/* =========================================================
   Vendeurs — les boutiques à vendeurs multiples (3.70.0)

   DEUX ÉCRANS.

     1. « Mes ventes » (#/ventes) : l'espace du VENDEUR. Ses produits,
        ce qu'il en a vendu, ce qui lui revient — en attente tant que
        le colis n'est pas remis, disponible ensuite —, son numéro de
        réception et ses demandes de versement. Aucun client, aucune
        commande à modifier : il consulte.

     2. « Vendeurs » (#/vendeurs) : le SUPERADMINISTRATEUR. Chaque
        vendeur, ses ventes, sa part et la commission de BIZZOO ; le
        bouton qui crée un vendeur ; l'historique des parts. Toucher un
        vendeur ouvre son espace, tel qu'il le voit.

   Tout se calcule en base, ligne par ligne, et se fige à la vente :
   ces écrans ne font que montrer.
   ========================================================= */
const VueVendeurs = (() => {
  const e = Utils.echapper;
  const m = (n, d) => Utils.fmtMontant(n, d || "FCFA");
  const pc = (t) => (t == null ? "—" : Utils.fmtTaux(t) + " %");
  const STATUTS = {
    en_attente: ["En attente", "badge-commande"],
    disponible: ["Disponible", "badge-disponible"],
    annulee: ["Annulée", "badge-rupture"],
  };

  /** Le contenu d'un espace vendeur — le sien, ou celui qu'ouvre BIZZOO. */
  function htmlEspace(x, pourBizzoo) {
    const s = x.solde;
    const d = s.devise;
    const r = s.reception;
    return (
      '<div class="carte sd-solde" id="vd-solde">' +
        '<div class="sd-etiquette">Disponible</div>' +
        '<div class="sd-montant" id="vd-disponible">' + e(m(s.disponible, d)) + "</div>" +
        '<div class="sd-details">' +
          "<div><span>Ventes livrées</span><strong>" + e(m(s.ventes, d)) + "</strong></div>" +
          "<div><span>Ce qui " + (pourBizzoo ? "lui" : "vous") + " revient</span><strong>" + e(m(s.gagne, d)) + "</strong></div>" +
          "<div><span>Déjà versé</span><strong>− " + e(m(s.reverse, d)) + "</strong></div>" +
          (s.enAttente
            ? "<div><span>Demande de versement en cours</span><strong>− " + e(m(s.enAttente, d)) + "</strong></div>"
            : "") +
          '<div class="sd-a-venir"><span>En attente (payé, pas encore livré)</span><strong>' +
            e(m(s.aVenir, d)) + "</strong></div>" +
        "</div>" +
        '<p class="aide" style="margin:10px 0 0">Une vente compte dès que le colis est <strong>remis au ' +
          "client</strong> et que la commande est payée. La part est celle du jour de la vente : un " +
          "pourcentage changé ensuite ne touche pas les ventes déjà faites.</p>" +
        (pourBizzoo ? ""
          : '<button type="button" class="btn" id="vd-demander" style="margin-top:12px"' +
              (s.disponible > 0 && r ? "" : " disabled") + ">Demander un versement</button>" +
            (!r ? '<p class="aide" style="margin:8px 0 0">Réglez d\'abord le numéro qui recevra vos gains.</p>' : "")) +
      "</div>" +

      (pourBizzoo ? ""
        : '<div class="carte" id="vd-reception">' +
            '<div class="carte-titre">' + UI.icone("tel", "ic-sm") + " Numéro qui reçoit vos gains</div>" +
            (r
              ? '<p style="margin:0 0 6px"><strong>' + e(r.reseau) + " " + e(r.tel) + "</strong>" +
                  (r.titulaire ? " — " + e(r.titulaire) : "") + "</p>" +
                '<p class="aide" style="margin:0 0 10px">Réglé le ' + e(Utils.fmtDateHeure(r.majLe)) +
                  ". BIZZOO est prévenu de chaque changement.</p>"
              : '<p class="aide" style="margin:0 0 10px">Aucun numéro : BIZZOO ne saurait pas où vous envoyer l\'argent.</p>') +
            '<button type="button" class="btn btn-clair" id="vd-regler">' + UI.icone("crayon") +
              (r ? "Changer le numéro" : "Régler le numéro") + "</button>" +
          "</div>") +

      '<div class="titre-section">' + (pourBizzoo ? "Ses produits" : "Mes produits") +
        " (" + x.produits.length + ")</div>" +
      (x.produits.length
        ? '<div class="carte" id="vd-produits">' + x.produits.map((p) =>
            '<div class="sd-ligne vd-produit">' +
              '<div class="sd-ligne-haut"><strong>' + e(p.nom) + "</strong><span>" + e(m(p.prix)) + "</span></div>" +
              '<div class="aide">' + e(p.boutique) + (p.code ? " · code " + e(p.code) : "") +
                " · part " + e(pc(p.taux)) + " = <strong>" + e(m(p.part)) + "</strong> la pièce" +
                " · stock " + (p.surCommande ? "sur commande" : e(String(p.stock))) + "</div>" +
              '<div class="aide">Vendus : <strong>' + e(String(p.vendus)) + "</strong>" +
                (p.enCours ? " (+ " + e(String(p.enCours)) + " en cours)" : "") +
                " · ventes " + e(m(p.ventes)) + " · revient " + e(m(p.gagne)) + "</div>" +
            "</div>").join("") + "</div>"
        : '<div class="carte"><p class="aide" style="margin:0">Aucun produit pour l\'instant : ' +
            "BIZZOO les ajoute dans une boutique à vendeurs multiples.</p></div>") +

      '<div class="titre-section">' + (pourBizzoo ? "Ses ventes" : "Mes ventes") + "</div>" +
      (x.lignes.length
        ? '<div class="carte" id="vd-lignes">' + x.lignes.map((l) => {
            const st = STATUTS[l.statut] || STATUTS.en_attente;
            return '<div class="sd-ligne vd-ligne">' +
              '<div class="sd-ligne-haut"><strong>+ ' + e(m(l.part)) + "</strong>" +
                '<span class="badge ' + st[1] + '">' + e(st[0]) + "</span></div>" +
              '<div class="aide">' + e(Utils.fmtDateHeure(l.le)) + " · " + e(l.numero) + " — " +
                e(String(l.quantite)) + " × " + e(l.produit) + " à " + e(m(l.prix)) + " · part " + e(pc(l.taux)) +
              "</div></div>";
          }).join("") + "</div>"
        : '<div class="carte"><p class="aide" style="margin:0">Aucune vente payée pour l\'instant.</p></div>') +

      '<div class="titre-section">Versements</div>' +
      (x.versements.length
        ? '<div class="carte" id="vd-versements">' + x.versements.map((v) =>
            '<div class="sd-ligne"><div class="sd-ligne-haut"><strong>' + e(m(v.montant)) + "</strong>" +
              '<span class="badge ' + (v.etat === "valide" ? "badge-disponible" : v.etat === "refuse" ? "badge-rupture" : "badge-commande") + '">' +
                (v.etat === "valide" ? "Versé" : v.etat === "refuse" ? "Refusé" : "En attente") + "</span></div>" +
              '<div class="aide">Demandé le ' + e(Utils.fmtDateHeure(v.demandeLe)) + " · vers " + e(v.reseau) + " " + e(v.tel) +
                (v.etat === "valide" ? " · référence " + e(v.reference) : "") +
                (v.etat === "refuse" && v.motif ? " · « " + e(v.motif) + " »" : "") + "</div></div>").join("") + "</div>"
        : '<div class="carte"><p class="aide" style="margin:0">Aucun versement pour l\'instant.</p></div>')
    );
  }

  /* ---------- 1. L'espace du vendeur ---------- */
  async function espace(vue) {
    UI.entete({ titre: "Mes ventes", sous: "Vos produits et ce qui vous revient" });
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Lecture de vos ventes…</div>';
    let x;
    try {
      x = await Store.espaceVendeur(null);
    } catch (err) {
      vue.innerHTML = '<div class="carte"><div class="carte-titre">Ventes indisponibles</div>' +
        '<p class="aide" style="margin:0">' + e(err.message) + "</p></div>";
      return;
    }
    vue.innerHTML = htmlEspace(x, false);
    const relire = () => espace(vue);
    UI.$("#vd-regler", vue).onclick = () =>
      VueSoldes.feuilleReception(x.solde.reception, relire, Store.reglerReceptionVendeur);
    const demander = UI.$("#vd-demander", vue);
    if (demander) {
      demander.onclick = () => VueSoldes.feuilleDemande(x.solde, relire, Store.demanderReversementVendeur);
    }
  }

  /* ---------- 2. Le tableau du superadministrateur ---------- */
  async function liste(vue) {
    UI.entete({ titre: "Vendeurs", sous: "Boutiques à vendeurs multiples", retour: true });
    if (!Supabase.estSuper()) {
      vue.innerHTML = UI.vide("magasin", "Réservé au superadministrateur",
        "Seul le superadministrateur suit les vendeurs et leurs ventes.");
      return;
    }
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Lecture des vendeurs…</div>';
    let vendeurs, historique;
    try {
      [vendeurs, historique] = await Promise.all([Store.ventesVendeurs(), Store.historiqueParts()]);
    } catch (err) {
      vue.innerHTML = '<div class="carte"><p class="aide" style="margin:0">' + e(err.message) +
        " — la base est-elle à jour (supabase/vendeurs-multiples.sql) ?</p></div>";
      return;
    }
    const total = (cle) => vendeurs.reduce((t, v) => t + v[cle], 0);
    vue.innerHTML =
      '<div class="carte sd-solde" id="vv-totaux">' +
        '<div class="sd-etiquette">Commission de BIZZOO (ventes livrées)</div>' +
        '<div class="sd-montant">' + e(m(total("commission"))) + "</div>" +
        '<div class="sd-details">' +
          "<div><span>Ventes livrées des vendeurs</span><strong>" + e(m(total("ventes"))) + "</strong></div>" +
          "<div><span>Part des vendeurs</span><strong>" + e(m(total("part"))) + "</strong></div>" +
          "<div><span>Déjà versé aux vendeurs</span><strong>" + e(m(total("reverse"))) + "</strong></div>" +
          "<div><span>Demandes en attente</span><strong>" + e(m(total("enAttente"))) + "</strong></div>" +
          '<div class="sd-a-venir"><span>À venir (payé, pas encore livré)</span><strong>' + e(m(total("aVenir"))) + "</strong></div>" +
        "</div>" +
        '<p class="aide" style="margin:10px 0 0">La commission est comptée avant les codes promo, qui se prennent ' +
          "sur elle : un vendeur garde toujours sa part entière.</p>" +
      "</div>" +
      '<div class="btn-rangee">' +
        '<button type="button" class="btn" id="vv-nouveau">' + UI.icone("plus") + "Nouveau vendeur</button>" +
        '<a class="btn btn-clair" href="#/reversements">' + UI.icone("promo") + "Versements</a>" +
      "</div>" +
      '<div class="titre-section">' + vendeurs.length + " vendeur" + (vendeurs.length > 1 ? "s" : "") + "</div>" +
      (vendeurs.length
        ? '<div class="carte" id="vv-liste">' + vendeurs.map((v) =>
            '<button type="button" class="sd-ligne vv-vendeur" data-vendeur="' + e(v.id) + '">' +
              '<div class="sd-ligne-haut"><strong>' + e(v.nom) + "</strong>" +
                (v.actif ? "<span>" + e(v.tel) + "</span>" : '<span class="badge badge-rupture">Inactif</span>') + "</div>" +
              '<div class="aide">' + e(String(v.produits)) + " produit" + (v.produits > 1 ? "s" : "") +
                " · ventes " + e(m(v.ventes)) + " · sa part " + e(m(v.part)) +
                " · BIZZOO " + e(m(v.commission)) + "</div>" +
              '<div class="aide">Disponible ' + e(m(v.disponible)) + " · versé " + e(m(v.reverse)) +
                (v.enAttente ? " · demandé " + e(m(v.enAttente)) : "") +
                (v.aVenir ? " · en attente " + e(m(v.aVenir)) : "") + "</div>" +
            "</button>").join("") + "</div>"
        : '<div class="carte"><p class="aide" style="margin:0">Aucun vendeur. Créez-en un, puis attribuez-lui ' +
            "ses produits dans une boutique à vendeurs multiples.</p></div>") +
      '<details class="carte" id="vv-historique"><summary class="carte-titre">Historique des parts (' +
        historique.length + ")</summary>" +
        (historique.length
          ? historique.map((h) =>
              '<div class="sd-ligne"><div class="sd-ligne-haut"><strong>' + e(h.produit) + "</strong><span>" +
                e(Utils.fmtDateHeure(h.le)) + "</span></div>" +
                '<div class="aide">' + e(h.boutique) + " · " +
                  (h.vendeurAvant && h.vendeurAvant !== h.vendeurApres
                    ? e(h.vendeurAvant) + " → " + e(h.vendeurApres || "—")
                    : e(h.vendeurApres || "—")) +
                  " · part " + (h.tauxAvant != null && h.tauxAvant !== h.tauxApres
                    ? e(pc(h.tauxAvant)) + " → " : "") + e(pc(h.tauxApres)) +
                  " · par " + e(h.par) + "</div></div>").join("")
          : '<p class="aide" style="margin:0">Aucun changement pour l\'instant.</p>') +
      "</details>";

    UI.$("#vv-nouveau", vue).onclick = () => VueComptes.creerVendeur(() => liste(vue));
    for (const b of UI.$$("[data-vendeur]", vue)) {
      b.onclick = async () => {
        const v = vendeurs.find((x) => x.id === b.dataset.vendeur) || {};
        const corps = UI.ouvrirFeuille(v.nom || "Vendeur",
          '<div class="chargement"><span class="chargement-rond"></span>Lecture…</div>');
        try {
          const x = await Store.espaceVendeur(b.dataset.vendeur);
          corps.innerHTML = htmlEspace(x, true);
        } catch (err) {
          corps.innerHTML = '<p class="aide" style="margin:0">' + e(err.message) + "</p>";
        }
      };
    }
  }

  return { espace, liste };
})();
