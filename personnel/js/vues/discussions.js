/* =========================================================
   Discussions — la messagerie interne.

   Trois sortes de fils : « Tout le monde » (le fil général, que tous
   les employés lisent), celui d'un PROFIL (ses membres, son
   responsable, l'administration, et quiconque y a écrit depuis un
   autre service) et les messages PRIVÉS entre deux personnes, à
   n'importe quel employé. Un message privé reste privé :
   l'administration ne le lit pas. C'est la base qui le garantit.

   Le fil ouvert se relit toutes les 8 secondes, tant qu'il est à
   l'écran. Un message porte du texte, ou une pièce : photo, vidéo,
   audio (fichier ou message vocal enregistré ici). Les pièces vivent
   dans un seau privé et se lisent par des liens signés, valables
   une heure. Tout message s'efface 7 jours après son envoi : c'est
   la base qui le fait, chaque heure.
   ========================================================= */
const VueDiscussions = (() => {
  const { h } = UI;
  let annuaire = null;

  async function chargerAnnuaire() {
    if (!annuaire) annuaire = await Supabase.rpc("rh_annuaire");
    return annuaire;
  }
  const personne = (id) => (annuaire || []).find((e) => e.id === id);

  async function afficher(zone, morceaux) {
    await chargerAnnuaire();
    if (morceaux[0] === "nouveau") return nouveau(zone);
    if (morceaux[0]) return fil(zone, morceaux[0]);
    return liste(zone);
  }

  async function liste(zone) {
    UI.vider(zone, UI.chargement());
    const conversations = await Supabase.rpc("rh_conversations");
    if (!zone.isConnected) return;
    UI.vider(zone,
      h("div", { class: "titre-section" }, h("h2", {}, "Discussions"),
        h("a", { class: "btn btn-petit", href: "#/discussions/nouveau" }, UI.icone("plus", "ic-sm"), "Nouveau message")),
      conversations.length ? h("div", { class: "liste" }, conversations.map((c) =>
        h("a", { class: "element" + (c.non_lus ? " non-lu" : ""), href: "#/discussions/" + c.cle },
          h("div", { class: "avatar", style: c.genre === "profil" ? { background: "var(--orange-clair)", color: "var(--orange-fonce)" }
              : c.genre === "general" ? { background: "var(--bleu)", color: "#fff" } : null },
            c.genre === "personne" ? UI.initiales(...(c.titre || "").split(" ").reverse()) : UI.icone(c.genre === "general" ? "bulle" : "equipe", "ic-sm")),
          h("div", { class: "etire" },
            h("div", { class: "ligne" },
              h("span", { class: "titre etire coupe" }, c.genre === "profil" ? "Profil " + c.titre : c.titre),
              h("span", { class: "doux tres-petit" }, UI.quand(c.dernier_le))),
            h("div", { class: "coupe petit doux" }, c.dernier_texte || (c.dernier_le ? "Pièce jointe" : "Aucun message pour l'instant"))),
          c.non_lus ? h("span", { class: "pastille" }, c.non_lus) : null)))
        : UI.vide("Vous n'êtes rattaché à aucun profil pour l'instant."),
      h("p", { class: "ephemere" }, "Les messages s'effacent automatiquement 7 jours après leur envoi."));
  }

  /** À qui puis-je écrire en privé ? À tout employé qui a un accès, sauf moi. */
  function destinatairesPossibles() {
    const moi = App.moi();
    return annuaire.filter((e) => e.id !== moi.id && e.a_un_compte);
  }

  /** Écrire : à tout le monde, à un profil, ou à une personne. */
  async function nouveau(zone) {
    App.titre("Nouveau message");
    const profils = await Supabase.lire("rh_profils?select=id,nom&order=nom").catch(() => []);
    if (!zone.isConnected) return;
    const possibles = destinatairesPossibles();
    const recherche = h("input", { type: "search", placeholder: "Chercher un employé…", "aria-label": "Chercher un employé" });
    const personnes = h("div", { class: "liste" });
    const dessinerPersonnes = () => {
      const q = recherche.value.trim().toLowerCase();
      const liste = possibles.filter((e) => !q || [UI.nomComplet(e), e.poste, e.profil].join(" ").toLowerCase().includes(q));
      UI.vider(personnes, liste.length ? liste.map((e) =>
        h("a", { class: "element", href: "#/discussions/d:" + e.id },
          h("div", { class: "avatar" }, UI.initiales(e.nom, e.prenoms)),
          h("div", { class: "etire" }, h("div", { class: "gras" }, UI.nomComplet(e)),
            h("div", { class: "petit doux" }, [e.poste, e.profil].filter(Boolean).join(" · "))),
          UI.icone("chevron", "ic-sm"))) : UI.vide("Personne ne correspond."));
    };
    recherche.addEventListener("input", dessinerPersonnes);
    dessinerPersonnes();
    UI.vider(zone,
      h("div", { class: "carte pile" },
        h("h2", {}, "À tout le monde"),
        h("a", { class: "element", href: "#/discussions/g:tous" },
          h("div", { class: "avatar", style: { background: "var(--bleu)", color: "#fff" } }, UI.icone("bulle", "ic-sm")),
          h("div", { class: "etire" }, h("div", { class: "gras" }, "Tout le monde"),
            h("div", { class: "petit doux" }, "Le fil général : tous les employés le lisent.")),
          UI.icone("chevron", "ic-sm"))),
      h("div", { class: "carte pile" },
        h("h2", {}, "À un profil"),
        profils.length ? h("div", { class: "liste" }, profils.map((p) =>
          h("a", { class: "element", href: "#/discussions/p:" + p.id },
            h("div", { class: "avatar", style: { background: "var(--orange-clair)", color: "var(--orange-fonce)" } }, UI.icone("equipe", "ic-sm")),
            h("div", { class: "etire" }, h("div", { class: "gras" }, "Profil " + p.nom),
              p.id === App.moi().profil_id ? h("div", { class: "petit doux" }, "Votre profil") : null),
            UI.icone("chevron", "ic-sm")))) : UI.vide("Aucun profil.")),
      h("div", { class: "carte pile" },
        h("h2", {}, "À un employé (message privé)"),
        recherche, personnes));
  }

  async function fil(zone, cle) {
    const [genre, cible] = cle.split(":");
    const moi = App.moi();
    let titre;
    if (genre === "g") {
      titre = "Tout le monde";
    } else if (genre === "p") {
      const profils = await Supabase.lire("rh_profils?select=id,nom&id=eq." + encodeURIComponent(cible));
      titre = profils[0] ? "Profil " + profils[0].nom : "Profil";
    } else {
      titre = UI.nomComplet(personne(cible));
    }
    App.titre(titre);

    const conteneur = h("div", { class: "fil" }, UI.chargement());
    const saisie = h("textarea", { placeholder: "Votre message…", rows: 1, maxlength: 4000 });
    const bouton = h("button", { class: "btn", type: "submit", "aria-label": "Envoyer" }, UI.icone("envoyer", "ic-sm"));
    const choixFichier = h("input", { type: "file", accept: "image/*,video/*,audio/*", hidden: true });
    const trombone = h("button", { class: "outil", type: "button", "aria-label": "Joindre une photo, une vidéo ou un audio",
      title: "Photo, vidéo ou audio", onclick: () => choixFichier.click() }, UI.icone("trombone", "ic-sm"));
    const micro = h("button", { class: "outil", type: "button", "aria-label": "Enregistrer un message vocal",
      title: "Message vocal" }, UI.icone("micro", "ic-sm"));
    const attente = h("div", {});
    const form = h("form", { class: "saisie" }, choixFichier, trombone, micro, saisie, bouton);
    UI.vider(zone, conteneur,
      h("div", { class: "saisie-bloc" }, attente, form,
        h("p", { class: "ephemere" }, "Les messages s'effacent automatiquement 7 jours après leur envoi.")));

    /* ---------- La pièce en attente d'envoi ---------- */
    let piece = null;   // { blob, type, nom }
    const montrerPiece = () => {
      if (!piece) return UI.vider(attente);
      const apercu = piece.type.startsWith("image/") ? h("img", { src: URL.createObjectURL(piece.blob), alt: "" })
        : piece.type.startsWith("video/") ? h("video", { src: URL.createObjectURL(piece.blob), muted: true })
        : h("audio", { src: URL.createObjectURL(piece.blob), controls: true });
      UI.vider(attente, h("div", { class: "piece-attente" }, apercu,
        h("div", { class: "etire coupe" }, h("div", { class: "gras coupe" }, piece.nom), h("div", { class: "doux" }, taille(piece.blob.size))),
        h("button", { class: "outil", type: "button", "aria-label": "Retirer la pièce", onclick: () => { piece = null; montrerPiece(); } },
          UI.icone("fermer", "ic-sm"))));
    };
    choixFichier.addEventListener("change", async () => {
      const f = choixFichier.files[0];
      choixFichier.value = "";
      if (!f) return;
      const type = typeBase(f.type);
      if (!/^(image|video|audio)\//.test(type)) return UI.echec("Photos, vidéos et audio seulement.");
      try {
        const blob = type.startsWith("image/") ? await alleger(f, type) : f;
        if (blob.size > MAX) return UI.echec("Fichier trop lourd (" + taille(blob.size) + ") : 50 Mo au plus.");
        piece = { blob, type: blob.type || type, nom: f.name || "fichier" };
        montrerPiece();
      } catch (err) { UI.echec(err); }
    });

    /* ---------- Le message vocal ---------- */
    let enregistreur = null;
    let finVocal = null;
    micro.addEventListener("click", async () => {
      if (enregistreur) return enregistreur.stop();
      if (!navigator.mediaDevices || typeof MediaRecorder === "undefined") {
        return UI.echec("Ce navigateur n'enregistre pas le son : joignez un fichier audio avec le trombone.");
      }
      let flux;
      try {
        flux = await navigator.mediaDevices.getUserMedia({ audio: true });
      } catch (_) {
        return UI.echec("Le micro est refusé : autorisez-le dans les réglages du navigateur.");
      }
      const format = ["audio/webm;codecs=opus", "audio/mp4", "audio/ogg;codecs=opus", "audio/webm"]
        .find((t) => MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported(t)) || "";
      const morceaux = [];
      enregistreur = new MediaRecorder(flux, format ? { mimeType: format } : undefined);
      enregistreur.addEventListener("dataavailable", (ev) => { if (ev.data.size) morceaux.push(ev.data); });
      enregistreur.addEventListener("stop", () => {
        flux.getTracks().forEach((t) => t.stop());
        clearTimeout(finVocal);
        micro.classList.remove("enregistre");
        const type = typeBase(enregistreur.mimeType || format || "audio/webm");
        enregistreur = null;
        const blob = new Blob(morceaux, { type });
        if (!blob.size) return;
        piece = { blob, type, nom: "Message vocal" };
        montrerPiece();
      });
      enregistreur.start();
      micro.classList.add("enregistre");
      UI.succes("Enregistrement… touchez le micro pour l'arrêter.");
      /* Cinq minutes au plus : au-delà, un fichier audio s'envoie mieux. */
      finVocal = setTimeout(() => enregistreur && enregistreur.stop(), 5 * 60 * 1000);
    });

    let dernier = 0;
    const chemin = genre === "g" ? "rh_messages?select=*&general=is.true"
      : genre === "p" ? "rh_messages?select=*&profil_id=eq." + cible
      : "rh_messages?select=*&destinataire_id=not.is.null&or=(and(auteur_id.eq." + moi.id + ",destinataire_id.eq." + cible +
        "),and(auteur_id.eq." + cible + ",destinataire_id.eq." + moi.id + "))";

    async function charger(premiere) {
      const messages = await Supabase.lire(chemin + "&id=gt." + dernier + "&order=id.desc&limit=200");
      if (!conteneur.isConnected) return false;
      if (premiere) conteneur.replaceChildren();
      if (premiere && !messages.length) {
        /* Le fil d'un autre service : on n'y voit rien avant d'y avoir écrit. */
        const autreProfil = genre === "p" && cible !== moi.profil_id && !App.estAdmin();
        conteneur.append(UI.vide(autreProfil
          ? "Vous n'êtes pas membre de ce profil : votre message sera lu par ses membres, et vous verrez ensuite leurs réponses ici."
          : "Aucun message. Écrivez le premier !"));
      }
      if (!messages.length) return true;
      if (conteneur.querySelector(".vide")) conteneur.replaceChildren();
      const enBas = window.innerHeight + window.scrollY >= document.body.scrollHeight - 80;
      messages.reverse();
      /* Les liens de lecture des pièces, d'un seul appel. */
      const liens = await Supabase.signer(messages.filter((m) => m.piece).map((m) => m.piece), 3600).catch(() => ({}));
      if (!conteneur.isConnected) return false;
      for (const m of messages) {
        const auteur = personne(m.auteur_id);
        const mien = m.auteur_id === moi.id;
        conteneur.append(h("div", { class: "bulle" + (mien ? " moi" : "") },
          !mien && genre !== "d" ? h("div", { class: "auteur" }, UI.nomComplet(auteur)) : null,
          m.piece ? h("div", { class: "piece" }, lecteur(m, liens[m.piece])) : null,
          m.texte ? h("div", { class: "pre" }, m.texte) : null,
          h("div", { class: "heure" }, UI.dateHeure(m.cree_le))));
        dernier = Math.max(dernier, m.id);
      }
      if (premiere || enBas) window.scrollTo(0, document.body.scrollHeight);
      Supabase.rpc("rh_marquer_lu", { conversation: cle }).catch(() => {});
      return true;
    }

    await charger(true);
    const minuterie = setInterval(async () => {
      try {
        if (!(await charger(false))) clearInterval(minuterie);
      } catch (_) { /* réseau : on retentera */ }
    }, 8000);

    saisie.addEventListener("keydown", (ev) => {
      if (ev.key === "Enter" && !ev.shiftKey && window.matchMedia("(min-width: 900px)").matches) {
        ev.preventDefault();
        form.requestSubmit();
      }
    });
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const texte = saisie.value.trim();
      if (!texte && !piece) return;
      if (enregistreur) return UI.echec("Arrêtez d'abord l'enregistrement (touchez le micro).");
      bouton.disabled = true;
      let chemin = null;
      try {
        const ligne = genre === "g" ? { general: true, texte } : genre === "p" ? { profil_id: cible, texte } : { destinataire_id: cible, texte };
        if (piece) {
          /* Le fichier d'abord, dans MON dossier ; puis le message qui le cite. */
          chemin = moi.id + "/" + crypto.randomUUID() + extension(piece.type);
          UI.succes("Envoi du fichier…");
          await Supabase.deposer(chemin, piece.blob, piece.type);
          Object.assign(ligne, { piece: chemin, piece_nom: piece.nom });
        }
        await Supabase.ajouter("rh_messages", ligne);
        chemin = null;
        piece = null;
        montrerPiece();
        saisie.value = "";
        await charger(false);
        window.scrollTo(0, document.body.scrollHeight);
      } catch (err) {
        if (chemin) Supabase.retirer(chemin);
        UI.echec(err);
      } finally {
        bouton.disabled = false;
        saisie.focus();
      }
    });
    saisie.focus();
  }

  /* ---------- Les pièces ---------- */

  const MAX = 50 * 1024 * 1024;
  const typeBase = (t) => String(t || "").split(";")[0].trim().toLowerCase();
  const taille = (o) => (o >= 1048576 ? (Math.round(o / 104857.6) / 10).toString().replace(".", ",") + " Mo" : Math.max(1, Math.round(o / 1024)) + " Ko");
  const EXTENSIONS = { "image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp", "image/gif": ".gif", "image/heic": ".heic",
    "video/mp4": ".mp4", "video/webm": ".webm", "video/quicktime": ".mov", "video/3gpp": ".3gp",
    "audio/mpeg": ".mp3", "audio/mp4": ".m4a", "audio/x-m4a": ".m4a", "audio/aac": ".aac", "audio/ogg": ".ogg",
    "audio/webm": ".webm", "audio/wav": ".wav", "audio/x-wav": ".wav", "audio/3gpp": ".3gp", "audio/amr": ".amr" };
  const extension = (t) => EXTENSIONS[t] || "";

  /** Une photo de téléphone pèse lourd pour rien : 1 600 px suffisent à l'écran. */
  async function alleger(fichier, type) {
    if (!/^image\/(jpeg|png|webp)$/.test(type)) return fichier;
    const image = await createImageBitmap(fichier).catch(() => null);
    if (!image) return fichier;
    const echelle = Math.min(1, 1600 / Math.max(image.width, image.height));
    if (echelle === 1 && fichier.size < 1.5 * 1048576) return fichier;
    const toile = document.createElement("canvas");
    toile.width = Math.round(image.width * echelle);
    toile.height = Math.round(image.height * echelle);
    toile.getContext("2d").drawImage(image, 0, 0, toile.width, toile.height);
    const blob = await new Promise((ok) => toile.toBlob(ok, "image/jpeg", 0.85));
    return blob && blob.size < fichier.size ? blob : fichier;
  }

  /** L'image, la vidéo ou le son d'un message ; un lien manquant le dit. */
  function lecteur(m, lien) {
    if (!lien) return h("div", { class: "petit doux" }, "Pièce jointe indisponible");
    if (m.piece_type === "image") {
      return h("img", { src: lien, alt: m.piece_nom || "Photo", loading: "lazy", onclick: () => window.open(lien, "_blank", "noopener") });
    }
    if (m.piece_type === "video") return h("video", { src: lien, controls: true, preload: "metadata", playsinline: true });
    return h("audio", { src: lien, controls: true, preload: "metadata" });
  }

  return { titre: "Discussions", afficher, oublier: () => { annuaire = null; } };
})();
