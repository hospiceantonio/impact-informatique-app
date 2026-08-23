/* =========================================================
   Validations — ce que les boutiques demandent à l'enseigne.

   Une boutique ne change pas seule ce qui la représente
   auprès des clients : son nom, son logo, sa description,
   son adresse, ses contacts, et les écrans de son slider.
   Elle dépose une demande ; c'est ici qu'on tranche.

   L'écran met l'ancien et le nouveau côte à côte — sans
   quoi approuver reviendrait à signer sans lire.
   ========================================================= */
const VueValidations = (() => {

  /* Le nom lisible d'une colonne de la base. Les demandes parlent la
     langue de la base ; l'écran, celle du gérant. */
  const NOMS = {
    nom: "Nom", logo: "Logo", description: "Description",
    adresse: "Adresse", latitude: "Latitude", longitude: "Longitude",
    tel: "Téléphone", whatsapp: "WhatsApp", indicatif: "Indicatif",
    telephones: "Autres numéros", adresses: "Autres adresses",
    image: "Photo", video: "Vidéo", titre: "Légende",
    produit_id: "Produit lié", ordre: "Position", actif: "Visible",
  };

  /** Une valeur, telle qu'on la lit — pas telle qu'elle est rangée. */
  function lisible(cle, valeur) {
    if (valeur === null || valeur === undefined || valeur === "") return "—";
    if (cle === "actif") return valeur ? "oui" : "non";
    if (cle === "telephones") {
      return (Array.isArray(valeur) ? valeur : [])
        .map((t) => (t.libelle ? t.libelle + " : " : "") + (t.numero || "")).join(" · ") || "—";
    }
    if (cle === "adresses") {
      return (Array.isArray(valeur) ? valeur : [])
        .map((a) => (a.libelle ? a.libelle + " : " : "") + (a.texte || "")).join(" · ") || "—";
    }
    if (cle === "image" || cle === "video" || cle === "logo") {
      /* Un chemin de stockage ne dit rien à personne : on montre le
         fichier, pas son rangement. */
      return String(valeur).split("/").pop();
    }
    return String(valeur);
  }

  /** L'aperçu d'un média, quand la demande en porte un. */
  function apercuMedia(apres) {
    const video = apres.video ? Supabase.urlImage(apres.video) : "";
    const image = apres.image ? Supabase.urlImage(apres.image)
      : (apres.logo ? Supabase.urlImage(apres.logo) : "");
    if (video) {
      return '<div class="dem-apercu"><video src="' + Utils.echapper(video) +
        '" controls muted playsinline preload="metadata"></video></div>';
    }
    if (image) {
      return '<div class="dem-apercu"><img src="' + Utils.echapper(image) + '" alt=""></div>';
    }
    return "";
  }

  /** Les lignes « avant → après », champ par champ. */
  function comparaison(d) {
    const cles = Object.keys(d.apres || {}).filter((c) => c !== "id");
    if (!cles.length) return "";
    return '<div class="dem-champs">' + cles.map((c) => {
      const avant = d.avant ? d.avant[c] : null;
      const apres = d.apres[c];
      const change = JSON.stringify(avant ?? null) !== JSON.stringify(apres ?? null);
      return (
        '<div class="dem-champ' + (change ? "" : " dem-champ-egal") + '">' +
          '<span class="dem-cle">' + Utils.echapper(NOMS[c] || c) + "</span>" +
          '<span class="dem-avant">' + Utils.echapper(lisible(c, avant)) + "</span>" +
          UI.icone("chevron", "ic-sm") +
          '<span class="dem-apres">' + Utils.echapper(lisible(c, apres)) + "</span>" +
        "</div>"
      );
    }).join("") + "</div>";
  }

  function htmlDemande(d) {
    const quand = Utils.fmtDateHeure(d.demandeLe);
    return (
      '<div class="carte dem-carte" data-demande="' + Utils.echapper(d.id) + '">' +
        '<div class="dem-entete">' +
          '<span class="dem-boutique">' + UI.icone("magasin", "ic-sm") +
            Utils.echapper(d.nomBoutique || d.boutiqueId) + "</span>" +
          '<span class="dem-quand">' + Utils.echapper(quand) + "</span>" +
        "</div>" +
        '<div class="dem-objet">' +
          UI.icone(d.type === "slider" ? "image" : "reglages", "ic-sm") +
          Utils.echapper(d.objet || (d.type === "slider" ? "Écran du slider" : "Réglages")) +
        "</div>" +
        '<div class="aide" style="margin:0 0 10px">Demandé par ' +
          Utils.echapper(d.demandePar || "—") + "</div>" +
        apercuMedia(d.apres || {}) +
        comparaison(d) +
        (d.etat === "en_attente"
          ? '<div class="btn-rangee" style="margin-top:12px">' +
              '<button type="button" class="btn" data-approuver="' + Utils.echapper(d.id) + '">' +
                UI.icone("check") + "Approuver</button>" +
              '<button type="button" class="btn btn-danger-clair" data-refuser="' +
                Utils.echapper(d.id) + '">' + UI.icone("fermer") + "Refuser</button>" +
            "</div>"
          : '<div class="dem-verdict dem-verdict-' + Utils.echapper(d.etat) + '">' +
              UI.icone(d.etat === "approuvee" ? "check" : "fermer", "ic-sm") +
              (d.etat === "approuvee" ? "Approuvée" : "Refusée") +
              (d.decidePar ? " par " + Utils.echapper(d.decidePar) : "") +
              (d.motif ? " — " + Utils.echapper(d.motif) : "") +
            "</div>") +
      "</div>"
    );
  }

  async function afficher(vue) {
    UI.entete({ titre: "Validations", sous: "Ce que les boutiques demandent", retour: true });
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture des demandes…</div>";

    let demandes;
    try {
      demandes = await Store.listerDemandes();
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Validations indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si la validation vient d'être mise en place, exécutez le fichier " +
        "supabase/schema.sql.</p></div>";
      return;
    }

    const attente = demandes.filter((d) => d.etat === "en_attente");
    const traitees = demandes.filter((d) => d.etat !== "en_attente").slice(0, 20);

    vue.innerHTML =
      '<div class="carte carte-publier">' +
        '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") + " " +
          (attente.length
            ? attente.length + " demande" + (attente.length > 1 ? "s" : "") + " en attente"
            : "Aucune demande en attente") + "</div>" +
        '<p class="aide" style="margin:0">Une boutique ne change pas seule son nom, son logo, ' +
          "sa description, son adresse, ses contacts, ni les écrans de son slider. " +
          "Elle vous le demande ; vous tranchez.</p>" +
      "</div>" +
      (attente.length ? attente.map(htmlDemande).join("") : "") +
      (traitees.length
        ? '<div class="titre-section">Déjà traitées</div>' + traitees.map(htmlDemande).join("")
        : "") +
      (!demandes.length
        ? UI.vide("check", "Rien à valider",
            "Les demandes des boutiques s'afficheront ici.")
        : "");

    const recharger = () => afficher(vue);

    for (const bouton of UI.$$("[data-approuver]", vue)) {
      bouton.onclick = async () => {
        bouton.disabled = true;
        try {
          await Store.approuverDemande(bouton.dataset.approuver);
          UI.toast("Demande approuvée — la modification est en ligne", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }

    for (const bouton of UI.$$("[data-refuser]", vue)) {
      bouton.onclick = async () => {
        /* Un refus sans motif laisse la boutique deviner : on demande
           la raison, sans l'imposer. */
        const motif = await UI.demanderTexte({
          titre: "Refuser cette demande ?",
          texte: "Dites à la boutique pourquoi : elle verra votre réponse.",
          libelle: "Motif (facultatif)",
          bouton: "Refuser", danger: true,
        });
        if (motif === null) return;
        bouton.disabled = true;
        try {
          await Store.refuserDemande(bouton.dataset.refuser, motif);
          UI.toast("Demande refusée", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }
  }

  return { afficher };
})();
