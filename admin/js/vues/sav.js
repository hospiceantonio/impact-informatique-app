/* =========================================================
   SAV — les réclamations des clients.

   LA BOUTIQUE D'ABORD, BIZZOO EN RECOURS.

   La boutique répond. Elle ne CLÔT pas : c'est le client qui
   dit que son problème est réglé. Une boutique capable de
   fermer une réclamation fermerait toutes celles qui la gênent,
   et le SAV ne serait plus qu'un formulaire à remplir pour rien.

   L'enseigne voit tout — c'est elle le recours — mais ne
   tranche que ce qui lui a été REMONTÉ. Retirer un dossier des
   mains d'une boutique sans qu'on le lui demande n'est pas un
   recours, c'est une mise sous tutelle. La base refuse ; cet
   écran ne montre le bouton que là où il a un sens.
   ========================================================= */
const VueSAV = (() => {

  const ETATS = {
    ouverte: { nom: "À répondre", classe: "sav-a-repondre" },
    repondue: { nom: "Répondu", classe: "sav-repondu" },
    resolue: { nom: "Réglé par le client", classe: "sav-regle" },
    escaladee: { nom: "Remonté à BIZZOO", classe: "sav-recours" },
    tranchee: { nom: "Tranché", classe: "sav-tranche" },
  };

  /** Depuis combien de temps la réclamation attend. */
  function depuis(quand) {
    const h = Math.floor((Date.now() - quand) / 3600000);
    if (h < 1) return "à l'instant";
    if (h < 24) return "il y a " + h + " h";
    const j = Math.floor(h / 24);
    return "il y a " + j + " jour" + (j > 1 ? "s" : "");
  }

  function htmlMessage(m) {
    const qui = m.role === "boutique" ? "La boutique"
      : m.role === "enseigne" ? "BIZZOO" : (m.nom || "Le client");
    return (
      '<div class="sav-msg sav-msg-' + Utils.echapper(m.role) + '">' +
        '<div class="sav-msg-qui">' +
          UI.icone(m.role === "boutique" ? "magasin"
            : m.role === "enseigne" ? "bouclier" : "personne", "ic-sm") +
          "<strong>" + Utils.echapper(qui) + "</strong>" +
          '<span class="sav-msg-quand">' + Utils.echapper(Utils.fmtDateHeure(m.quand)) + "</span>" +
        "</div>" +
        '<p class="sav-msg-texte">' + Utils.echapper(m.texte) + "</p>" +
      "</div>"
    );
  }

  function htmlReclamation(r, messages, peutTrancher) {
    const etat = ETATS[r.etat] || ETATS.ouverte;
    const close = r.etat === "resolue" || r.etat === "tranchee";
    /* Une réclamation ouverte depuis plus de 48 h, c'est un client qui
       peut déjà appeler BIZZOO. Le dire ici, c'est laisser une chance
       de répondre avant. */
    const tarde = r.etat === "ouverte" && Date.now() - r.creeLe > 48 * 3600000;
    return (
      '<div class="carte sav-carte' + (r.etat === "escaladee" ? " sav-en-recours" : "") +
        '" data-sav="' + Utils.echapper(r.id) + '">' +
        '<div class="dem-entete">' +
          '<span class="dem-boutique">' + UI.icone("alerte", "ic-sm") +
            Utils.echapper(Store.SUJETS_SAV[r.sujet] || "Problème") + "</span>" +
          '<span class="dem-quand">' + Utils.echapper(depuis(r.creeLe)) + "</span>" +
        "</div>" +
        '<div class="sav-ligne">' +
          '<span class="badge ' + etat.classe + '">' + Utils.echapper(etat.nom) + "</span>" +
          (r.nomBoutique
            ? '<span class="sav-ou">' + Utils.echapper(r.nomBoutique) + "</span>" : "") +
          (tarde
            ? '<span class="sav-tarde">' + UI.icone("horloge", "ic-sm") +
              " Passé 48 h : le client peut saisir BIZZOO</span>"
            : "") +
        "</div>" +
        (r.escaladeMotif
          ? '<div class="sav-motif">' + UI.icone("alerte", "ic-sm") +
            "<div><strong>Motif du recours</strong><br>" +
            Utils.echapper(r.escaladeMotif) + "</div></div>"
          : "") +
        '<div class="sav-fil">' + messages.map(htmlMessage).join("") + "</div>" +
        (close
          ? '<div class="sav-clos">' + UI.icone("check", "ic-sm") +
            (r.etat === "tranchee"
              ? " Tranché par BIZZOO" + (r.decidePar ? " (" + Utils.echapper(r.decidePar) + ")" : "")
              : " Le client a fermé la réclamation") + "</div>"
          : '<div class="btn-rangee" style="margin-top:12px">' +
              '<button type="button" class="btn btn-clair" data-repondre="' +
                Utils.echapper(r.id) + '">' + UI.icone("crayon") + "Répondre</button>" +
              /* Le bouton ne s'affiche QUE sur un recours : ailleurs, la
                 base refuserait, et un bouton qui refuse promet pour
                 rien. */
              (peutTrancher && r.etat === "escaladee"
                ? '<button type="button" class="btn" data-trancher="' +
                  Utils.echapper(r.id) + '">' + UI.icone("bouclier") + "Trancher</button>"
                : "") +
            "</div>") +
      "</div>"
    );
  }

  async function afficher(vue) {
    const peutTrancher = Supabase.estSuper();
    UI.entete({ titre: "Réclamations",
      sous: peutTrancher ? "Toutes les boutiques" : "Votre boutique", retour: true });
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>' +
      "Lecture des réclamations…</div>";

    let liste;
    try {
      liste = await Store.listerReclamations();
    } catch (err) {
      vue.innerHTML =
        '<div class="carte"><div class="carte-titre">Réclamations indisponibles</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si le SAV vient d'être mis en place, exécutez le fichier " +
        "supabase/sav.sql.</p></div>";
      return;
    }

    /* Les fils, tous d'un coup : une réclamation sans son fil ne se lit
       pas, et faire attendre un clic par dossier découragerait d'ouvrir. */
    const fils = new Map();
    await Promise.all(liste.slice(0, 40).map(async (r) => {
      try { fils.set(r.id, await Store.messagesReclamation(r.id)); }
      catch (_) { fils.set(r.id, []); }
    }));

    /* L'ordre dit quoi faire : ce qui est remonté à BIZZOO d'abord —
       un client attend déjà depuis deux tours — puis ce qui n'a pas
       de réponse, puis le reste. */
    const recours = liste.filter((r) => r.etat === "escaladee");
    const aRepondre = liste.filter((r) => r.etat === "ouverte");
    const suite = liste.filter((r) => !["escaladee", "ouverte"].includes(r.etat));

    const section = (titre, lot) => lot.length
      ? '<div class="titre-section">' + titre + "</div>" +
        lot.map((r) => htmlReclamation(r, fils.get(r.id) || [], peutTrancher)).join("")
      : "";

    vue.innerHTML =
      '<div class="carte carte-publier">' +
        '<div class="carte-titre">' + UI.icone("alerte", "ic-sm") + " " +
          (aRepondre.length + recours.length
            ? (aRepondre.length + recours.length) + " réclamation" +
              (aRepondre.length + recours.length > 1 ? "s" : "") + " en cours"
            : "Aucune réclamation en cours") + "</div>" +
        '<p class="aide" style="margin:0">Répondez sous 48 heures : passé ce délai, le ' +
          "client peut demander à BIZZOO de trancher. Vous ne pouvez pas fermer une " +
          "réclamation — c'est le client qui dit que son problème est réglé" +
          (peutTrancher ? ", ou vous qui tranchez ce qui vous est remonté." : ".") + "</p>" +
      "</div>" +
      section(peutTrancher ? "Remontées à BIZZOO" : "Remontées à BIZZOO", recours) +
      section("Sans réponse", aRepondre) +
      section("Déjà traitées", suite) +
      (!liste.length
        ? UI.vide("check", "Aucune réclamation",
            "Les réclamations de vos clients s'afficheront ici.")
        : "");

    const recharger = () => afficher(vue);

    for (const bouton of UI.$$("[data-repondre]", vue)) {
      bouton.onclick = async () => {
        const texte = await UI.demanderTexte({
          titre: "Répondre au client",
          texte: "Votre message s'ajoute au fil. Le client le lira dans son application.",
          libelle: "Votre réponse",
          bouton: "Envoyer",
        });
        if (texte === null) return;
        if (!texte.trim()) return UI.toast("Écrivez votre message.", "err");
        bouton.disabled = true;
        try {
          await Store.repondreReclamation(bouton.dataset.repondre, texte);
          UI.toast("Réponse envoyée", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }

    for (const bouton of UI.$$("[data-trancher]", vue)) {
      bouton.onclick = async () => {
        /* Une décision se motive : les DEUX parties la liront, et c'est
           elle qui s'impose à la boutique. */
        const verdict = await UI.demanderTexte({
          titre: "Trancher ce recours",
          texte: "Votre décision s'ajoute au fil et s'impose à la boutique. " +
            "Le client et la boutique la liront tous les deux.",
          libelle: "Votre décision",
          bouton: "Trancher",
        });
        if (verdict === null) return;
        if (!verdict.trim()) return UI.toast("Dites votre décision.", "err");
        bouton.disabled = true;
        try {
          await Store.trancherReclamation(bouton.dataset.trancher, verdict);
          UI.toast("Recours tranché", "ok");
          recharger();
        } catch (err) {
          UI.toast(err.message, "err");
          bouton.disabled = false;
        }
      };
    }
  }

  return { afficher, ETATS };
})();
