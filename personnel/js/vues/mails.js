/* =========================================================
   Mails — la boîte professionnelle @bizzoomarket.com.

   Tout passe par la fonction Edge « rh-messagerie », qui parle
   IMAP et SMTP au serveur de LWS. L'écran ne voit jamais le mot
   de passe de la boîte après l'avoir saisi une fois.

   LE HTML D'UN MAIL N'EST PAS DE CONFIANCE. Il s'affiche dans un
   cadre isolé (« sandbox » sans script ni accès à la page), avec
   une règle qui bloque les images distantes : une image distante
   dit à l'expéditeur que vous avez ouvert son mail, et quand.
   Un bouton les affiche à la demande.
   ========================================================= */
const VueMails = (() => {
  const { h } = UI;
  let dossiers = null;

  const nomDe = (l) => (l && l.length ? (l[0].nom || l[0].adresse) : "—");
  const listeAdresses = (l) => (l || []).map((a) => (a.nom ? a.nom + " <" + a.adresse + ">" : a.adresse)).join(", ");

  async function afficher(zone, morceaux, params) {
    const action = morceaux[0] || "";
    if (action === "reglage") return reglage(zone);
    UI.vider(zone, UI.chargement());
    try {
      if (!dossiers) dossiers = (await Supabase.messagerie("dossiers")).dossiers;
    } catch (err) {
      if (err.code === "a_configurer" || err.code === "mot_de_passe") return reglage(zone, err.message);
      throw err;
    }
    if (action === "lire") return lire(zone, params.d || "INBOX", Number(params.u));
    if (action === "ecrire") return ecrire(zone, params);
    return boite(zone, params);
  }

  /* ---------- Le réglage : relier sa boîte ---------- */

  async function reglage(zone, raison) {
    const moi = App.moi();
    const mdp = h("input", { type: "password", autocomplete: "off", required: true });
    const bouton = h("button", { class: "btn", type: "submit" }, "Relier ma boîte");
    const erreur = h("div", { class: "erreur", hidden: !raison }, raison || "");
    const form = h("form", { class: "carte pile" },
      h("h2", {}, "Relier ma boîte mail"),
      h("p", { class: "doux" }, "Adresse : ", h("b", {}, moi.email_pro || "aucune — voyez l'administration")),
      h("p", { class: "doux petit" },
        "Saisissez le mot de passe de votre boîte mail (celui du webmail de LWS). ",
        "Il est vérifié auprès du serveur de mail, puis gardé chiffré : personne, pas même le CEO, ne peut le lire."),
      h("label", { class: "champ" }, h("span", {}, "Mot de passe de la boîte mail"), mdp),
      erreur, h("div", { class: "actions" }, bouton));
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      erreur.hidden = true;
      bouton.disabled = true;
      bouton.textContent = "Vérification…";
      try {
        await Supabase.messagerie("enregistrer", { mot_de_passe: mdp.value });
        mdp.value = "";
        dossiers = null;
        UI.succes("Boîte mail reliée.");
        location.hash = "#/mails";
      } catch (err) {
        erreur.textContent = err.message;
        erreur.hidden = false;
      } finally {
        bouton.disabled = false;
        bouton.textContent = "Relier ma boîte";
      }
    });
    UI.vider(zone, form);
    mdp.focus();
  }

  /* ---------- La liste ---------- */

  async function boite(zone, params) {
    const dossier = params.dossier || "INBOX";
    const page = Number(params.page || 0);
    const recherche = params.q || "";
    const courant = dossiers.find((d) => d.chemin === dossier) || { nom: dossier };
    App.titre(courant.nom);

    const champRecherche = h("input", { type: "search", placeholder: "Rechercher dans " + courant.nom, value: recherche });
    const formRecherche = h("form", { class: "ligne" },
      h("label", { class: "champ etire" }, champRecherche),
      h("a", { class: "btn", href: "#/mails/ecrire" }, UI.icone("crayon", "ic-sm"), "Écrire"));
    formRecherche.addEventListener("submit", (ev) => {
      ev.preventDefault();
      location.hash = "#/mails?dossier=" + encodeURIComponent(dossier) + "&q=" + encodeURIComponent(champRecherche.value.trim());
    });

    const barre = h("div", { class: "dossiers" }, dossiers.map((d) =>
      h("button", { class: d.chemin === dossier ? "actif" : "", onclick: () => {
        location.hash = "#/mails?dossier=" + encodeURIComponent(d.chemin);
      } }, d.nom, d.non_lus ? h("span", { class: "pastille" }, d.non_lus) : null)));

    const liste = h("div", {}, UI.chargement());
    UI.vider(zone, formRecherche, barre, liste);

    const r = await Supabase.messagerie("lister", { dossier, page, par_page: 25, recherche });
    if (!liste.isConnected) return;
    if (!r.messages.length) {
      UI.vider(liste, UI.vide(recherche ? "Aucun message ne correspond." : "Aucun message dans ce dossier."));
      return;
    }
    const envoyes = courant.role === "\\Sent";
    UI.vider(liste,
      h("div", { class: "liste" }, r.messages.map((m) =>
        h("a", { class: "element" + (m.lu ? "" : " non-lu"),
                 href: "#/mails/lire?d=" + encodeURIComponent(dossier) + "&u=" + m.uid },
          h("div", { class: "avatar" }, UI.initiales(nomDe(envoyes ? m.a : m.de))),
          h("div", { class: "etire" },
            h("div", { class: "ligne" },
              h("span", { class: "titre etire coupe" }, envoyes ? "À : " + nomDe(m.a) : nomDe(m.de)),
              h("span", { class: "doux tres-petit" }, UI.quand(m.date))),
            h("div", { class: "coupe petit" + (m.lu ? " doux" : " gras") }, m.sujet || "(sans objet)")),
          m.pieces ? UI.icone("trombone", "ic-sm") : null))),
      pagination(dossier, recherche, page, r.total, r.par_page));
  }

  function pagination(dossier, recherche, page, total, parPage) {
    const pages = Math.ceil(total / parPage);
    if (pages <= 1) return null;
    const lien = (p) => "#/mails?dossier=" + encodeURIComponent(dossier) + "&page=" + p +
      (recherche ? "&q=" + encodeURIComponent(recherche) : "");
    return h("div", { class: "ligne", style: { justifyContent: "center" } },
      page > 0 ? h("a", { class: "btn btn-second btn-petit", href: lien(page - 1) }, "Plus récents") : null,
      h("span", { class: "doux petit" }, "Page " + (page + 1) + " / " + pages),
      page + 1 < pages ? h("a", { class: "btn btn-second btn-petit", href: lien(page + 1) }, "Plus anciens") : null);
  }

  /* ---------- Lire ---------- */

  function documentDuMail(m, imagesDistantes) {
    const regle = "default-src 'none'; style-src 'unsafe-inline'; font-src data:; img-src data:" +
      (imagesDistantes ? " https: http:" : "");
    const corps = m.html ||
      "<pre style=\"white-space:pre-wrap;font-family:inherit\">" +
      String(m.texte || "").replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c])) + "</pre>";
    return "<!doctype html><html><head><meta charset=\"utf-8\">" +
      "<meta http-equiv=\"Content-Security-Policy\" content=\"" + regle + "\">" +
      "<base target=\"_blank\">" +
      "<style>body{font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;font-size:15px;line-height:1.5;color:#1F2937;margin:12px;word-wrap:break-word}img{max-width:100%;height:auto}</style>" +
      "</head><body>" + corps + "</body></html>";
  }

  async function lire(zone, dossier, uid) {
    UI.vider(zone, UI.chargement());
    const { message: m } = await Supabase.messagerie("lire", { dossier, uid });
    if (!zone.isConnected) return;
    App.titre(m.sujet || "(sans objet)");
    /* Le dossier a un message lu de plus : on recompte au prochain passage. */
    dossiers = null;

    const cadre = h("iframe", { class: "mail-cadre", sandbox: "allow-popups allow-popups-to-escape-sandbox",
      referrerpolicy: "no-referrer", title: "Contenu du message" });
    cadre.srcdoc = documentDuMail(m, false);
    cadre.addEventListener("load", () => {
      try {
        /* Le cadre isolé ne se laisse pas mesurer : hauteur généreuse. */
        cadre.style.height = Math.max(360, window.innerHeight - 260) + "px";
      } catch (_) { /* rien */ }
    });
    const aDesImages = /<img[^>]+src=["']?https?:/i.test(m.html || "");
    const boutonImages = aDesImages ? h("button", { class: "btn btn-second btn-petit", onclick: () => {
      cadre.srcdoc = documentDuMail(m, true);
      boutonImages.remove();
    } }, "Afficher les images") : null;

    const retour = "#/mails?dossier=" + encodeURIComponent(dossier);
    const lienAction = (quoi) => "#/mails/ecrire?" + quoi + "=1&d=" + encodeURIComponent(dossier) + "&u=" + uid;

    UI.vider(zone,
      h("div", { class: "carte pile" },
        h("div", { class: "mail-entete pile" },
          h("h2", { style: { fontSize: "17px", marginBottom: 0 } }, m.sujet || "(sans objet)"),
          h("div", { class: "petit" }, h("b", {}, "De : "), listeAdresses(m.de)),
          h("div", { class: "petit doux" }, h("b", {}, "À : "), listeAdresses(m.a)),
          m.cc.length ? h("div", { class: "petit doux" }, h("b", {}, "Cc : "), listeAdresses(m.cc)) : null,
          h("div", { class: "tres-petit doux" }, UI.dateHeure(m.date))),
        h("div", { class: "actions" },
          h("a", { class: "btn btn-petit", href: lienAction("repondre") }, UI.icone("repondre", "ic-sm"), "Répondre"),
          (m.cc.length || m.a.length > 1) ? h("a", { class: "btn btn-second btn-petit", href: lienAction("tous") }, "Répondre à tous") : null,
          h("a", { class: "btn btn-second btn-petit", href: lienAction("transferer") }, "Transférer"),
          h("button", { class: "btn btn-second btn-petit", onclick: async (ev) => {
            await UI.agir(ev.currentTarget, () => Supabase.messagerie("marquer", { dossier, uid, lu: false }), "Marqué non lu");
            location.hash = retour;
          } }, "Non lu"),
          h("button", { class: "btn btn-danger btn-petit", onclick: async (ev) => {
            if (!await UI.confirmer("Mettre ce message à la corbeille ?", { danger: true, valider: "Supprimer" })) return;
            await UI.agir(ev.currentTarget, () => Supabase.messagerie("supprimer", { dossier, uid }), "Message supprimé");
            dossiers = null;
            location.hash = retour;
          } }, UI.icone("poubelle", "ic-sm"), "Supprimer"),
          boutonImages),
        m.pieces.filter((p) => !p.en_ligne).length ? h("div", { class: "actions" },
          m.pieces.filter((p) => !p.en_ligne).map((p) => h("button", { class: "btn btn-second btn-petit", onclick: (ev) =>
            telecharger(ev.currentTarget, dossier, uid, p) },
            UI.icone("trombone", "ic-sm"), p.nom + " (" + taille(p.taille) + ")"))) : null,
        cadre));
  }

  const taille = (o) => (o > 1048576 ? (o / 1048576).toFixed(1) + " Mo" : Math.max(1, Math.round(o / 1024)) + " Ko");

  async function telecharger(bouton, dossier, uid, p) {
    const { piece } = await UI.agir(bouton, () => Supabase.messagerie("piece", { dossier, uid, index: p.index }));
    const octets = Uint8Array.from(atob(piece.contenu), (c) => c.charCodeAt(0));
    const url = URL.createObjectURL(new Blob([octets], { type: piece.type }));
    const a = h("a", { href: url, download: piece.nom });
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
  }

  /* ---------- Écrire ---------- */

  async function ecrire(zone, params) {
    App.titre("Nouveau message");
    let origine = null;
    if (params.u) {
      UI.vider(zone, UI.chargement());
      origine = (await Supabase.messagerie("lire", { dossier: params.d || "INBOX", uid: Number(params.u) })).message;
      if (!zone.isConnected) return;
    }
    const moi = App.moi().email_pro;
    let a = "", cc = "", sujet = "", texte = "", enReponseA = "", references = [];
    let piecesTransferees = [];
    if (origine) {
      const cite = "\n\n" + "Le " + UI.dateHeure(origine.date) + ", " + listeAdresses(origine.de) + " a écrit :\n" +
        String(origine.texte || "").split("\n").map((l) => "> " + l).join("\n");
      if (params.transferer) {
        sujet = /^tr\s*:/i.test(origine.sujet) ? origine.sujet : "Tr : " + origine.sujet;
        texte = "\n\n---------- Message transféré ----------\nDe : " + listeAdresses(origine.de) +
          "\nDate : " + UI.dateHeure(origine.date) + "\nObjet : " + origine.sujet +
          "\nÀ : " + listeAdresses(origine.a) + "\n\n" + (origine.texte || "");
        piecesTransferees = origine.pieces.filter((p) => !p.en_ligne);
      } else {
        const auteur = (origine.repondre_a.length ? origine.repondre_a : origine.de).map((x) => x.adresse);
        a = auteur.join(", ");
        if (params.tous) {
          const autres = [...origine.a, ...origine.cc].map((x) => x.adresse)
            .filter((x) => x && x.toLowerCase() !== (moi || "").toLowerCase() && !auteur.includes(x));
          cc = autres.join(", ");
        }
        sujet = /^re\s*:/i.test(origine.sujet) ? origine.sujet : "Re : " + origine.sujet;
        texte = cite;
        enReponseA = origine.message_id;
        references = [...origine.references, origine.message_id].filter(Boolean);
      }
    }

    /* Les collègues, proposés à la saisie. */
    let annuaire = [];
    try { annuaire = await Supabase.rpc("rh_annuaire"); } catch (_) { /* on s'en passe */ }
    const suggestions = h("datalist", { id: "adresses-collegues" },
      annuaire.filter((e) => e.email_pro).map((e) => h("option", { value: e.email_pro }, UI.nomComplet(e))));

    const champA = h("input", { value: a, list: "adresses-collegues", placeholder: "adresse@exemple.com, …" });
    const champCc = h("input", { value: cc, list: "adresses-collegues" });
    const champCci = h("input", { list: "adresses-collegues" });
    const champSujet = h("input", { value: sujet });
    const champTexte = h("textarea", { style: { minHeight: "240px" } });
    champTexte.value = texte;
    const fichiers = h("input", { type: "file", multiple: true });
    const listePieces = h("div", { class: "doux petit" },
      piecesTransferees.length ? "Pièces jointes transférées : " + piecesTransferees.map((p) => p.nom).join(", ") : "");
    const bouton = h("button", { class: "btn", type: "submit" }, UI.icone("envoyer", "ic-sm"), "Envoyer");

    const form = h("form", { class: "carte pile" },
      suggestions,
      h("div", { class: "petit doux" }, "De : ", h("b", {}, moi)),
      h("label", { class: "champ" }, h("span", {}, "À"), champA),
      h("details", {}, h("summary", { class: "petit doux" }, "Cc et Cci"),
        h("div", { class: "pile", style: { marginTop: "8px" } },
          h("label", { class: "champ" }, h("span", {}, "Cc"), champCc),
          h("label", { class: "champ" }, h("span", {}, "Cci (copie cachée)"), champCci))),
      h("label", { class: "champ" }, h("span", {}, "Objet"), champSujet),
      h("label", { class: "champ" }, h("span", {}, "Message"), champTexte),
      h("label", { class: "champ" }, h("span", {}, "Pièces jointes (15 Mo en tout)"), fichiers),
      listePieces,
      h("div", { class: "actions" }, bouton,
        h("a", { class: "btn btn-second", href: "#/mails" }, "Annuler")));

    const decouper = (t) => t.split(/[,;\s]+/).map((x) => x.trim()).filter(Boolean);
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const destinataires = decouper(champA.value);
      if (!destinataires.length && !decouper(champCc.value).length && !decouper(champCci.value).length) {
        UI.echec("Indiquez au moins un destinataire.");
        return;
      }
      if (!champSujet.value.trim() && !await UI.confirmer("Envoyer ce message sans objet ?")) return;
      bouton.disabled = true;
      bouton.lastChild.textContent = "Envoi…";
      try {
        const pieces = [];
        let total = 0;
        for (const f of fichiers.files) {
          total += f.size;
          if (total > 15 * 1024 * 1024) throw new Error("Les pièces jointes dépassent 15 Mo en tout.");
          pieces.push({ nom: f.name, type: f.type || "application/octet-stream", contenu: await enBase64(f) });
        }
        for (const p of piecesTransferees) {
          const { piece } = await Supabase.messagerie("piece", { dossier: params.d || "INBOX", uid: Number(params.u), index: p.index });
          pieces.push({ nom: piece.nom, type: piece.type, contenu: piece.contenu });
        }
        const r = await Supabase.messagerie("envoyer", {
          a: destinataires, cc: decouper(champCc.value), cci: decouper(champCci.value),
          sujet: champSujet.value.trim(), texte: champTexte.value, pieces,
          en_reponse_a: enReponseA || undefined, references,
        });
        UI.succes(r.range_dans_envoyes ? "Message envoyé." : "Message envoyé (mais pas rangé dans « Envoyés »).");
        dossiers = null;
        location.hash = "#/mails";
      } catch (err) {
        UI.echec(err);
      } finally {
        bouton.disabled = false;
        bouton.lastChild.textContent = "Envoyer";
      }
    });
    UI.vider(zone, form);
    (a ? champTexte : champA).focus();
    if (a) champTexte.setSelectionRange(0, 0);
  }

  function enBase64(fichier) {
    return new Promise((resoudre, rejeter) => {
      const lecteur = new FileReader();
      lecteur.onload = () => resoudre(String(lecteur.result).split(",")[1] || "");
      lecteur.onerror = () => rejeter(new Error("Impossible de lire « " + fichier.name + " »."));
      lecteur.readAsDataURL(fichier);
    });
  }

  return { titre: "Mails", afficher, oublier: () => { dossiers = null; } };
})();
