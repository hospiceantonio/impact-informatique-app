/* =========================================================
   Discussions — la messagerie interne.

   Deux sortes de fils : celui d'un PROFIL (tous ses membres, son
   responsable, et l'administration) et les messages PRIVÉS entre
   deux personnes. Un message privé reste privé : l'administration
   ne le lit pas. C'est la base qui le garantit.

   Le fil ouvert se relit toutes les 8 secondes, tant qu'il est à
   l'écran.
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
        h("a", { class: "btn btn-petit", href: "#/discussions/nouveau" }, UI.icone("plus", "ic-sm"), "Message privé")),
      conversations.length ? h("div", { class: "liste" }, conversations.map((c) =>
        h("a", { class: "element" + (c.non_lus ? " non-lu" : ""), href: "#/discussions/" + c.cle },
          h("div", { class: "avatar", style: c.genre === "profil" ? { background: "var(--orange-clair)", color: "var(--orange-fonce)" } : null },
            c.genre === "profil" ? UI.icone("equipe", "ic-sm") : UI.initiales(...(c.titre || "").split(" ").reverse())),
          h("div", { class: "etire" },
            h("div", { class: "ligne" },
              h("span", { class: "titre etire coupe" }, c.genre === "profil" ? "Profil " + c.titre : c.titre),
              h("span", { class: "doux tres-petit" }, UI.quand(c.dernier_le))),
            h("div", { class: "coupe petit doux" }, c.dernier_texte || "Aucun message pour l'instant")),
          c.non_lus ? h("span", { class: "pastille" }, c.non_lus) : null)))
        : UI.vide("Vous n'êtes rattaché à aucun profil pour l'instant."));
  }

  /** À qui puis-je écrire ? Le même calcul que la base, pour l'affichage. */
  function destinatairesPossibles() {
    const moi = App.moi();
    const responsables = new Set(annuaire.filter((e) => e.responsable).map((e) => e.id));
    return annuaire.filter((e) => e.id !== moi.id && e.a_un_compte && (
      App.estAdmin() || e.administration || e.ceo ||
      (e.profil_id && e.profil_id === moi.profil_id) ||
      App.responsableDe(e.profil_id) ||
      (responsables.has(e.id) && e.profil_id === moi.profil_id)));
  }

  function nouveau(zone) {
    App.titre("Message privé");
    const possibles = destinatairesPossibles();
    UI.vider(zone,
      h("p", { class: "doux" }, "Vous pouvez écrire aux membres de votre profil, à votre responsable et à l'administration."),
      possibles.length ? h("div", { class: "liste" }, possibles.map((e) =>
        h("a", { class: "element", href: "#/discussions/d:" + e.id },
          h("div", { class: "avatar" }, UI.initiales(e.nom, e.prenoms)),
          h("div", { class: "etire" }, h("div", { class: "gras" }, UI.nomComplet(e)),
            h("div", { class: "petit doux" }, [e.poste, e.profil].filter(Boolean).join(" · "))),
          UI.icone("chevron", "ic-sm")))) : UI.vide("Personne à qui écrire pour l'instant."));
  }

  async function fil(zone, cle) {
    const [genre, cible] = cle.split(":");
    const moi = App.moi();
    let titre;
    if (genre === "p") {
      const profils = await Supabase.lire("rh_profils?select=id,nom&id=eq." + encodeURIComponent(cible));
      titre = profils[0] ? "Profil " + profils[0].nom : "Profil";
    } else {
      titre = UI.nomComplet(personne(cible));
    }
    App.titre(titre);

    const conteneur = h("div", { class: "fil" }, UI.chargement());
    const saisie = h("textarea", { placeholder: "Votre message…", rows: 1, maxlength: 4000 });
    const bouton = h("button", { class: "btn", type: "submit", "aria-label": "Envoyer" }, UI.icone("envoyer", "ic-sm"));
    const form = h("form", { class: "saisie" }, saisie, bouton);
    UI.vider(zone, conteneur, form);

    let dernier = 0;
    const chemin = genre === "p"
      ? "rh_messages?select=*&profil_id=eq." + cible
      : "rh_messages?select=*&destinataire_id=not.is.null&or=(and(auteur_id.eq." + moi.id + ",destinataire_id.eq." + cible +
        "),and(auteur_id.eq." + cible + ",destinataire_id.eq." + moi.id + "))";

    async function charger(premiere) {
      const messages = await Supabase.lire(chemin + "&id=gt." + dernier + "&order=id.desc&limit=200");
      if (!conteneur.isConnected) return false;
      if (premiere) conteneur.replaceChildren();
      if (premiere && !messages.length) conteneur.append(UI.vide("Aucun message. Écrivez le premier !"));
      if (!messages.length) return true;
      if (conteneur.querySelector(".vide")) conteneur.replaceChildren();
      const enBas = window.innerHeight + window.scrollY >= document.body.scrollHeight - 80;
      for (const m of messages.reverse()) {
        const auteur = personne(m.auteur_id);
        const mien = m.auteur_id === moi.id;
        conteneur.append(h("div", { class: "bulle" + (mien ? " moi" : "") },
          !mien && genre === "p" ? h("div", { class: "auteur" }, UI.nomComplet(auteur)) : null,
          h("div", { class: "pre" }, m.texte),
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
      if (!texte) return;
      bouton.disabled = true;
      try {
        await Supabase.ajouter("rh_messages", genre === "p" ? { profil_id: cible, texte } : { destinataire_id: cible, texte });
        saisie.value = "";
        await charger(false);
        window.scrollTo(0, document.body.scrollHeight);
      } catch (err) {
        UI.echec(err);
      } finally {
        bouton.disabled = false;
        saisie.focus();
      }
    });
    saisie.focus();
  }

  return { titre: "Discussions", afficher, oublier: () => { annuaire = null; } };
})();
