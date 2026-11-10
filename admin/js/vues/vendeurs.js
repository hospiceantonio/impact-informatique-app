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
            /* (3.80.0) Sa photo, et « Disponible / Non disponible » d'un geste. */
            '<div class="sd-ligne vd-produit' + (p.enPause ? " vd-pause" : "") + '" data-produit="' + e(p.id) + '">' +
              '<div class="vd-produit-tete">' +
                (p.image
                  ? '<img class="vd-photo" src="' + e(p.image) + '" alt="" loading="lazy">'
                  : '<span class="vd-photo vd-photo-vide">' + UI.icone("boite") + "</span>") +
                '<div class="vd-produit-mots">' +
                  '<div class="sd-ligne-haut"><strong>' + e(p.nom) + "</strong><span>" + e(m(p.prix)) + "</span></div>" +
                  '<button type="button" class="vd-dispo' + (p.enPause ? "" : " actif") + '" data-dispo="' +
                    (p.enPause ? "1" : "0") + '" aria-pressed="' + !p.enPause + '">' +
                    '<span class="vd-dispo-rond"></span>' +
                    (p.enPause ? "Non disponible" : "Disponible") + "</button>" +
                "</div>" +
              "</div>" +
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
    /* (3.80.0) Son compte, d'un toucher : profil, mot de passe, déconnexion. */
    UI.entete({ titre: "Mes ventes", sous: "Vos produits et ce qui vous revient",
      actions: '<button type="button" class="btn-ic" id="vd-rafraichir" aria-label="Actualiser">' +
          UI.icone("actualiser") + "</button>" +
        '<a class="btn-ic" href="#/compte" aria-label="Mon compte" id="vd-compte">' + UI.icone("personne") + "</a>" });
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Lecture de vos ventes…</div>';
    let x;
    try {
      x = await Store.espaceVendeur(null);
    } catch (err) {
      vue.innerHTML = '<div class="carte"><div class="carte-titre">Ventes indisponibles</div>' +
        '<p class="aide" style="margin:0">' + e(err.message) + "</p></div>";
      return;
    }
    vue.innerHTML = htmlEspace(x, false) +
      /* (3.80.0) Prévenu de chaque commande, même le site fermé. */
      '<div class="carte" id="vd-notifs" hidden></div>' +
      '<div class="titre-section">Mon compte</div>' +
      '<div class="carte" id="vd-mon-compte">' +
        '<p class="aide" style="margin:0 0 10px">Votre nom, votre mot de passe, la langue.</p>' +
        '<a class="btn btn-clair" href="#/compte" id="vd-profil">' + UI.icone("personne") +
          "Modifier mon profil et mon mot de passe</a>" +
        '<button type="button" class="btn btn-clair" id="vd-deconnexion" style="margin-top:8px">Se déconnecter</button>' +
      "</div>";
    const relire = () => espace(vue);
    const rafraichir = UI.$("#vd-rafraichir");
    if (rafraichir) rafraichir.onclick = relire;
    brancherDisponibilite(vue, relire);
    if (typeof PushWeb !== "undefined") {
      PushWeb.monter(UI.$("#vd-notifs", vue), { application: "admin", rpc: Supabase.rpc });
    }
    UI.$("#vd-deconnexion", vue).onclick = async () => {
      await Supabase.deconnexion();
      location.reload();
    };
    UI.$("#vd-regler", vue).onclick = () =>
      VueSoldes.feuilleReception(x.solde.reception, relire, Store.reglerReceptionVendeur);
    const demander = UI.$("#vd-demander", vue);
    if (demander) {
      demander.onclick = () => VueSoldes.feuilleDemande(x.solde, relire, Store.demanderReversementVendeur);
    }
  }

  /* (3.80.0) « Disponible » / « Non disponible » : non disponible, le
     produit reste visible chez les clients mais ne se commande pas. */
  function brancherDisponibilite(vue, apres) {
    for (const b of UI.$$(".vd-dispo", vue)) {
      b.onclick = async () => {
        const ligne = b.closest("[data-produit]");
        const rendre = b.dataset.dispo === "1";
        b.disabled = true;
        try {
          await Store.produitDisponible(ligne.dataset.produit, rendre);
          UI.toast(rendre ? "Disponible : les clients peuvent le commander."
                          : "Non disponible : il reste visible, mais ne se commande plus.", "ok");
          apres();
        } catch (err) {
          UI.toast(err.message, "err");
          b.disabled = false;
        }
      };
    }
  }

  /* ---------- (3.78.0) Le lieu d'un vendeur ----------
     Un vendeur est une vraie boutique sur le terrain : son commerce, son
     numéro, son adresse écrite, SA position, ses jours et heures. Ce
     qu'on lui commande se récupère chez lui — jamais à la position de la
     boutique multivendeur, qui ne sert qu'à l'identifier. */
  function positionDuLien(texte) {
    const t = String(texte || "");
    const trouve = t.match(/(-?\d{1,3}\.\d{3,})[,\s/@]+(-?\d{1,3}\.\d{3,})/);
    if (!trouve) return null;
    const p = { latitude: Number(trouve[1]), longitude: Number(trouve[2]) };
    return Math.abs(p.latitude) <= 90 && Math.abs(p.longitude) <= 180 ? p : null;
  }

  async function feuilleLieu(id, nomCompte, apres) {
    const corps = UI.ouvrirFeuille("Le lieu de " + (nomCompte || "ce vendeur"),
      '<div class="chargement"><span class="chargement-rond"></span>Lecture…</div>');
    let l;
    try {
      l = await Store.lieuVendeur(id);
    } catch (err) {
      corps.innerHTML = '<p class="aide" style="margin:0">' + e(err.message) +
        " — la base est-elle à jour (supabase/lieux-vendeurs.sql) ?</p>";
      return;
    }
    let pos = l.latitude != null ? { latitude: l.latitude, longitude: l.longitude } : null;
    let carte = null;
    corps.innerHTML =
      '<p class="aide" style="margin:0 0 10px">Ce que le client commande chez ce vendeur se récupère <strong>chez ' +
        "lui</strong> : les frais de livraison partent de sa position, et le livreur reçoit son adresse et son " +
        "numéro. La position de la boutique multivendeur ne le remplace jamais.</p>" +
      UI.champTexte({ id: "vl-nom", label: "Nom de son commerce", valeur: l.nom || nomCompte || "",
        placeholder: "Ex. : Pagnes Afi" }) +
      UI.champTexte({ id: "vl-tel", label: "Numéro de sa boutique", valeur: l.tel, type: "tel",
        placeholder: "01 00 00 00 00", aide: "Celui que le livreur appellera pour récupérer le colis." }) +
      UI.champZone({ id: "vl-adresse", label: "Adresse écrite", valeur: l.adresse, lignes: 2, max: 300,
        placeholder: "Quartier, rue, repère (ex. : Dantokpa, allée 4, porte bleue)" }) +
      '<div class="champ"><label>Sa position <span class="obligatoire">*</span></label>' +
        '<div id="vl-chercher"></div>' +
        '<div class="btn-rangee" style="margin-top:8px">' +
          '<button type="button" class="btn btn-clair btn-petit" id="vl-ici">' + UI.icone("carte", "ic-sm") +
            "Je suis chez lui : ma position</button>" +
        "</div>" +
        UI.champTexte({ id: "vl-lien", label: "Ou un lien de carte / des coordonnées",
          placeholder: "https://maps.google.com/… ou 6.3702, 2.4289" }) +
        '<div class="km-carte" id="vl-carte"></div>' +
        '<div class="aide" id="vl-etat" style="margin-top:6px"></div>' +
      "</div>" +
      UI.champsHoraires("vl", l.ouvertures,
        "En dehors de ces heures, ses produits ne sont pas visibles des clients, et on ne peut pas lui commander.") +
      '<button type="button" class="btn" id="vl-enregistrer">' + UI.icone("check") + "Enregistrer son lieu</button>" +
      '<div id="vl-erreur"></div>';

    const etat = UI.$("#vl-etat", corps);
    const dire = () => {
      if (!pos) {
        etat.innerHTML = '<span class="lieu-ligne" style="color:var(--rouge)">' + UI.icone("alerte", "ic-sm") +
          "<span>Position manquante : touchez la carte, cherchez le quartier, ou collez un lien.</span></span>";
        return;
      }
      const nom = typeof Lieu !== "undefined" ? Lieu.connu(pos) : "";
      etat.innerHTML = '<span class="lieu-ligne">' + UI.icone("check", "ic-sm") + "<span>" +
        (nom ? "<strong>" + e(nom) + "</strong> · " : "") +
        e(pos.latitude.toFixed(5)) + ", " + e(pos.longitude.toFixed(5)) + "</span></span>";
      if (!nom && typeof Lieu !== "undefined") {
        const ici = pos;
        Lieu.nommer(ici).then((n) => { if (n && pos === ici && etat.isConnected) dire(); });
      }
    };
    const poser = (p, recentrer) => {
      pos = { latitude: Number(Number(p.latitude).toFixed(6)), longitude: Number(Number(p.longitude).toFixed(6)) };
      if (carte) carte.placer(pos, recentrer);
      dire();
    };
    try {
      carte = await Carte.monter(UI.$("#vl-carte", corps), { position: pos, deplace: (p) => poser(p, false) });
    } catch (_) {
      UI.$("#vl-carte", corps).innerHTML = '<p class="aide" style="padding:12px">La carte ne s\'affiche pas sans ' +
        "connexion : collez un lien de carte.</p>";
    }
    dire();
    if (typeof Lieu !== "undefined") {
      Lieu.monterRecherche(UI.$("#vl-chercher", corps), (x) => poser(x, true),
        { id: "vl-lieu-q", indication: "Quartier du vendeur : Dantokpa, Missèbo…" });
    }
    UI.$("#vl-lien", corps).addEventListener("change", (ev) => {
      const p = positionDuLien(ev.target.value);
      if (!p) { UI.toast("Ce lien ne contient pas de position", "err"); return; }
      poser(p, true);
      ev.target.value = "";
    });
    UI.$("#vl-ici", corps).onclick = () => {
      if (!navigator.geolocation) { UI.toast("Position indisponible sur cet appareil", "err"); return; }
      navigator.geolocation.getCurrentPosition(
        (r) => poser({ latitude: r.coords.latitude, longitude: r.coords.longitude }, true),
        () => UI.toast("Position introuvable : activez la localisation, ou touchez la carte.", "err"),
        { enableHighAccuracy: true, timeout: 15000 });
    };
    UI.$("#vl-enregistrer", corps).onclick = async () => {
      const bouton = UI.$("#vl-enregistrer", corps);
      const zone = UI.$("#vl-erreur", corps);
      zone.innerHTML = "";
      try {
        UI.$("#vl-erreur", corps).innerHTML = "";
        if (!pos) throw new Error("Posez la position du vendeur : c'est d'elle que partent les frais de livraison.");
        const ouvertures = UI.lireHoraires(corps, "vl");
        bouton.disabled = true;
        await Store.enregistrerLieuVendeur(id, {
          nom: UI.$("#vl-nom", corps).value.trim(), tel: UI.$("#vl-tel", corps).value,
          adresse: UI.$("#vl-adresse", corps).value.trim(),
          latitude: pos.latitude, longitude: pos.longitude, ouvertures,
        });
        UI.fermerFeuille();
        UI.toast("Lieu du vendeur enregistré.", "ok");
        if (typeof apres === "function") apres();
      } catch (err) {
        bouton.disabled = false;
        zone.innerHTML = '<p class="aide" style="color:var(--rouge);margin:10px 0 0">' + e(err.message) + "</p>";
      }
    };
  }

  /* ---------- 2. Le tableau du superadministrateur ---------- */
  async function liste(vue, ouvrirId) {
    UI.entete({ titre: "Vendeurs", sous: "Boutiques à vendeurs multiples", retour: true });
    if (!Supabase.estSuper()) {
      vue.innerHTML = UI.vide("magasin", "Réservé au superadministrateur",
        "Seul le superadministrateur suit les vendeurs et leurs ventes.");
      return;
    }
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Lecture des vendeurs…</div>';
    let vendeurs, historique, comptes, lieux;
    try {
      /* (3.72.0) Les comptes aussi : les vendeurs se gèrent ici, comme les
         livreurs dans leur écran — plus dans la liste de l'équipe. */
      [vendeurs, historique, comptes, lieux] = await Promise.all([Store.ventesVendeurs(), Store.historiqueParts(),
        Store.listerComptes().catch(() => []), Store.lieuxVendeurs()]);
    } catch (err) {
      vue.innerHTML = '<div class="carte"><p class="aide" style="margin:0">' + e(err.message) +
        " — la base est-elle à jour (supabase/vendeurs-multiples.sql) ?</p></div>";
      return;
    }
    const total = (cle) => vendeurs.reduce((t, v) => t + v[cle], 0);
    vendeurs = vendeurs.slice().sort((a, b) =>
      String(a.nom || "").localeCompare(String(b.nom || ""), "fr", { sensitivity: "base" }));
    const compteDe = (id) => comptes.find((c) => c.id === id && c.role === "vendeur");
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
      (vendeurs.length > 5
        ? '<input type="search" class="recherche-liste" id="vv-chercher" autocomplete="off" ' +
            'placeholder="Rechercher un vendeur : nom, numéro…" aria-label="Rechercher un vendeur">' +
          '<div class="aide recherche-liste-vide" id="vv-aucun" hidden>Aucun vendeur ne correspond.</div>'
        : "") +
      (vendeurs.length
        ? '<div class="carte" id="vv-liste">' + vendeurs.map((v) =>
            '<div class="vv-rangee" data-cherche="' + e(Utils.sansAccent([v.nom, v.tel].filter(Boolean).join(" "))) + '">' +
            /* (3.78.0) Son lieu : où le livreur récupère ce qu'on lui commande. */
            (lieux
              ? '<button type="button" class="btn-ic btn-ic-clair vv-lieu" data-lieu="' + e(v.id) +
                  '" data-nom="' + e(v.nom) + '" aria-label="Le lieu de ' + e(v.nom) + '">' +
                  UI.icone("carte", "ic-sm") + "</button>"
              : "") +
            (compteDe(v.id)
              ? '<button type="button" class="btn-ic btn-ic-clair vv-compte" data-compte="' + e(v.id) +
                  '" aria-label="Modifier le compte de ' + e(v.nom) + '">' + UI.icone("crayon", "ic-sm") + "</button>"
              : "") +
            '<button type="button" class="sd-ligne vv-vendeur" data-vendeur="' + e(v.id) + '">' +
              '<div class="sd-ligne-haut"><strong>' + e(v.nom) + "</strong>" +
                (v.actif ? "<span>" + e(v.tel) + "</span>" : '<span class="badge badge-rupture">Inactif</span>') + "</div>" +
              (lieux
                ? (lieux.get(v.id) && lieux.get(v.id).position
                    ? '<div class="aide lieu-ligne">' + UI.icone("carte", "ic-sm") + "<span>" +
                        e(lieux.get(v.id).adresse || "Position enregistrée") +
                        (lieux.get(v.id).horaires ? "" : " · horaires manquants") + "</span></div>"
                    : '<div class="aide vv-sans-lieu lieu-ligne" style="color:var(--rouge)">' + UI.icone("alerte", "ic-sm") +
                        "<span>Position manquante : les frais partent du point BIZZOO en attendant.</span></div>")
                : "") +
              '<div class="aide">' + e(String(v.produits)) + " produit" + (v.produits > 1 ? "s" : "") +
                " · ventes " + e(m(v.ventes)) + " · sa part " + e(m(v.part)) +
                " · BIZZOO " + e(m(v.commission)) + "</div>" +
              '<div class="aide">Disponible ' + e(m(v.disponible)) + " · versé " + e(m(v.reverse)) +
                (v.enAttente ? " · demandé " + e(m(v.enAttente)) : "") +
                (v.aVenir ? " · en attente " + e(m(v.aVenir)) : "") + "</div>" +
            "</button></div>").join("") + "</div>"
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

    /* (3.78.0) Créé : son lieu tout de suite — numéro, adresse, position,
       horaires. */
    UI.$("#vv-nouveau", vue).onclick = () => VueComptes.creerVendeur((compte) => {
      liste(vue);
      if (compte && compte.id) feuilleLieu(compte.id, compte.nom || "", () => liste(vue));
    });
    for (const b of UI.$$("[data-lieu]", vue)) {
      b.onclick = () => feuilleLieu(b.dataset.lieu, b.dataset.nom, () => liste(vue));
    }
    /* (3.72.0) Le compte : nom, numéro, mot de passe, actif ou non. */
    for (const b of UI.$$("[data-compte]", vue)) {
      b.onclick = () => {
        const c = compteDe(b.dataset.compte);
        if (c) VueComptes.ficheCompte(c, () => liste(vue));
      };
    }
    /* (3.73.0) « #/vendeurs/<id> » : son espace s'ouvre de lui-même. */
    if (ouvrirId) {
      const b = UI.$('[data-vendeur="' + CSS.escape(ouvrirId) + '"]', vue);
      if (b) b.click();
      else UI.toast("Ce vendeur n'est plus dans la liste.", "err");
    }
    const chercher = UI.$("#vv-chercher", vue);
    if (chercher) {
      chercher.oninput = () => {
        const q = Utils.sansAccent(chercher.value.trim());
        let vus = 0;
        for (const r of UI.$$(".vv-rangee", vue)) {
          r.hidden = !!q && !r.dataset.cherche.includes(q);
          if (!r.hidden) vus++;
        }
        UI.$("#vv-aucun", vue).hidden = vus > 0;
      };
    }
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

  return { espace, liste, feuilleLieu };
})();
