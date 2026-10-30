/* =========================================================
   Ma file — les alertes de la place de marché devenues des
   tâches, confiées à un profil.

   #/file            : ce qui est à faire (libre, ou prise) ;
   #/file/terminees  : ce qui a été terminé, ou s'est réglé tout
                       seul, ces 7 derniers jours ;
   #/file/routage    : quel profil reçoit quel type d'alerte, et au
                       bout de combien de minutes une tâche que
                       personne n'a prise remonte (administration).

   « Je prends » dit aux collègues qui s'en occupe : deux personnes
   n'appellent plus la même boutique. Une note de relance est datée et
   signée. On appelle ou l'on écrit sur WhatsApp à la boutique ou au
   livreur ; au client, l'administration seule. Une tâche dont
   l'alerte n'existe plus disparaît d'elle-même. La base décide de
   tout (rh_ma_file, rh_tache_prendre, rh_tache_relancer,
   rh_tache_terminer, rh_routage_regler) et ne donne aucun montant.
   ========================================================= */
const VueFile = (() => {
  const { h } = UI;
  const ROUTE = "#/file";

  /** « 01 97 00 00 11 » → « 2290197000011 » : WhatsApp veut l'indicatif. */
  function international(tel) {
    const c = String(tel || "").replace(/\D/g, "");
    if (!c) return "";
    return c.length <= 10 ? "229" + c : c;
  }

  /** Appeler, écrire sur WhatsApp : deux boutons pour un numéro. */
  function contact(qui, nom, tel) {
    if (!tel) return null;
    return h("div", { class: "ligne petit" },
      h("span", { class: "etire coupe" }, h("span", { class: "doux" }, qui + " "), h("b", {}, nom || "—"), " · " + tel),
      h("a", { class: "btn btn-second btn-petit", href: "tel:" + String(tel).replace(/[^\d+]/g, "") }, "Appeler"),
      h("a", { class: "btn btn-second btn-petit", href: "https://wa.me/" + international(tel), target: "_blank", rel: "noopener" }, "WhatsApp"));
  }

  function onglets(actif, routage) {
    const items = [["", "À faire"], ["terminees", "Terminées"]].concat(routage ? [["routage", "Routage"]] : []);
    return h("div", { class: "filtres" }, items.map(([v, l]) =>
      h("button", { class: v === actif ? "actif" : "", onclick: () => { location.hash = ROUTE + (v ? "/" + v : ""); } }, l)));
  }

  async function afficher(zone, morceaux) {
    if (morceaux[0] === "routage") return routage(zone);
    return liste(zone, morceaux[0] === "terminees" ? "terminees" : "a_faire");
  }

  /* ---------- Les tâches ---------- */

  function etatDe(t) {
    if (t.etat === "terminee") return UI.etiquette("Terminée" + (t.terminee_nom ? " par " + t.terminee_nom : ""), "vert");
    if (t.etat === "disparue") return UI.etiquette("Réglée d'elle-même", "vert");
    if (t.etat === "prise") return UI.etiquette(t.a_moi ? "Prise par moi" : "Prise par " + (t.prise_nom || "un collègue"), "bleu");
    return t.escalade_le ? UI.etiquette("Personne ne l'a prise", "rouge") : UI.etiquette("Libre", "orange");
  }

  async function liste(zone, vue) {
    const d = await Supabase.rpc("rh_ma_file", { v_vue: vue });
    if (!zone.isConnected) return;
    const recharger = () => { App.rafraichir(); liste(zone, vue); };
    const taches = d.taches || [];
    const ouvertes = vue === "a_faire";

    const carte = (t) => {
      const actions = [];
      if (ouvertes) {
        if (t.etat === "ouverte") {
          actions.push(h("button", { class: "btn btn-petit", onclick: async (ev) => {
            await UI.agir(ev.currentTarget, () => Supabase.rpc("rh_tache_prendre", { v_tache: t.id }), "Tâche prise : elle est à vous.");
            recharger();
          } }, UI.icone("check", "ic-sm"), "Je prends"));
        } else if (!t.a_moi && t.reprendre) {
          actions.push(h("button", { class: "btn btn-second btn-petit", onclick: async (ev) => {
            const bouton = ev.currentTarget;
            if (!await UI.confirmer("Reprendre cette tâche à " + (t.prise_nom || "votre collègue") + " ? Une note le dira.", { valider: "Reprendre" })) return;
            await UI.agir(bouton, () => Supabase.rpc("rh_tache_prendre", { v_tache: t.id, v_reprendre: true }), "Tâche reprise.");
            recharger();
          } }, "Reprendre"));
        }
        actions.push(h("button", { class: "btn btn-second btn-petit", onclick: async (ev) => {
          const bouton = ev.currentTarget;
          const v = await UI.formulaire({
            titre: "Noter une relance", valider: "Noter",
            champs: [{ nom: "note", libelle: "Ce qui a été fait", type: "textarea", requis: true,
                       indice: "Boutique appelée : prêt dans 20 min" }],
            verifier: (x) => (x.note.length < 3 ? "Écrivez ce qui a été fait." : null),
          });
          if (!v) return;
          await UI.agir(bouton, () => Supabase.rpc("rh_tache_relancer", { v_tache: t.id, v_note: v.note }), "Relance notée.");
          recharger();
        } }, UI.icone("crayon", "ic-sm"), "Relance"));
        if (t.etat === "ouverte" || t.a_moi || t.reprendre) {
          actions.push(h("button", { class: "btn btn-second btn-petit", onclick: async (ev) => {
            const bouton = ev.currentTarget;
            const v = await UI.formulaire({
              titre: "Terminer la tâche", valider: "Terminé",
              texte: "Si l'alerte revient plus tard après avoir disparu, la tâche se rouvrira.",
              champs: [{ nom: "note", libelle: "Un mot (facultatif)", type: "textarea" }],
            });
            if (!v) return;
            await UI.agir(bouton, () => Supabase.rpc("rh_tache_terminer", { v_tache: t.id, v_note: v.note }), "Tâche terminée.");
            recharger();
          } }, "Terminé"));
        }
      }
      if (t.lien) actions.push(h("a", { class: "btn btn-second btn-petit", href: t.lien }, "Ouvrir", UI.icone("chevron", "ic-sm")));

      const contacts = [
        (t.boutiques || []).map((b) => contact("Boutique", b.nom, b.tel)),
        (t.livreurs || []).map((l) => contact("Livreur", l.nom, l.tel)),
        t.client && t.client.tel ? contact("Client", t.client.nom || "", t.client.tel) : null,
      ];
      return h("div", { class: "carte pile" + (t.escalade_le && t.etat === "ouverte" ? " alerte" : "") },
        h("div", { class: "ligne" }, h("b", { class: "etire" }, t.type_libelle), etatDe(t)),
        h("div", {}, t.libelle),
        h("div", { class: "petit doux" }, [
          "Créée " + UI.quand(t.cree_le),
          t.profil ? "Profil " + t.profil : "Administration",
          t.prise_le && t.etat === "prise" ? "prise " + UI.quand(t.prise_le) : null,
          t.escalade_le ? "remontée " + UI.quand(t.escalade_le) : null,
          t.terminee_le ? "close " + UI.quand(t.terminee_le) : null,
        ].filter(Boolean).join(" · ")),
        ouvertes ? contacts : null,
        (t.notes || []).length ? h("div", { class: "petit" }, t.notes.map((n) =>
          h("div", {}, h("span", { class: "doux" }, UI.dateHeure(n.le) + " · " + (n.par || "—") + " : "), n.note))) : null,
        actions.length ? h("div", { class: "actions" }, actions) : null);
    };

    const libres = taches.filter((t) => t.etat === "ouverte").length;
    const miennes = taches.filter((t) => t.a_moi).length;
    UI.vider(zone,
      onglets(vue === "terminees" ? "terminees" : "", d.droits && d.droits.routage),
      ouvertes ? h("div", { class: "tuiles compactes" },
        h("div", { class: "tuile" + (libres ? " alerte" : "") }, h("b", {}, UI.entier(libres)), h("span", {}, "libres")),
        h("div", { class: "tuile" }, h("b", {}, UI.entier(miennes)), h("span", {}, "prises par moi")),
        h("div", { class: "tuile" }, h("b", {}, UI.entier(taches.filter((t) => t.escalade_le && t.etat === "ouverte").length)),
          h("span", {}, "remontées au responsable"))) : null,
      d.synchro_le ? h("p", { class: "tres-petit doux" }, "File recalculée " + UI.quand(d.synchro_le) + ".") : null,
      taches.length ? h("div", { class: "pile" }, taches.map(carte))
        : UI.vide(ouvertes ? "Rien à faire : aucune alerte en cours pour vous." : "Aucune tâche close ces 7 derniers jours."));
  }

  /* ---------- Le routage (administration) ---------- */

  async function routage(zone) {
    const d = await Supabase.rpc("rh_routage_lire");
    if (!zone.isConnected) return;
    const options = [{ valeur: "", libelle: "Administration" }].concat(d.profils.map((p) => ({ valeur: p.id, libelle: p.nom })));
    let groupe = "";
    const lignes = [];
    for (const t of d.types) {
      if (t.groupe !== groupe) {
        groupe = t.groupe;
        lignes.push(h("h3", { style: { marginTop: "10px" } }, groupe));
      }
      const profil = h("select", { "aria-label": "Profil chargé" }, options.map((o) =>
        h("option", { value: o.valeur, selected: String(o.valeur) === String(t.profil_id || "") }, o.libelle)));
      const delai = h("input", { type: "number", min: 5, max: 10080, step: 5, value: t.escalade_min, style: { width: "90px" },
        "aria-label": "Minutes avant de remonter" });
      const actif = h("input", { type: "checkbox", checked: t.actif });
      const bouton = h("button", { class: "btn btn-second btn-petit", onclick: async () => {
        const n = Number(delai.value);
        if (!Number.isInteger(n) || n < 5 || n > 10080) return UI.echec("Le délai va de 5 à 10 080 minutes.");
        await UI.agir(bouton, () => Supabase.rpc("rh_routage_regler", {
          v_type: t.type, v_profil: profil.value || null, v_escalade_min: n, v_actif: actif.checked }), "Routage enregistré.");
        App.rafraichir();
      } }, "Enregistrer");
      lignes.push(h("div", { class: "ligne petit", style: { padding: "6px 0", borderTop: "1px solid var(--trait)" } },
        h("span", { class: "etire" }, h("b", {}, t.libelle),
          t.maj_par ? h("div", { class: "tres-petit doux" }, "Réglé par " + t.maj_par + ", " + UI.quand(t.maj_le)) : null),
        profil, delai, h("span", { class: "doux" }, "min"), h("label", { class: "case" }, actif, "Active"), bouton));
    }
    UI.vider(zone, onglets("routage", true),
      h("div", { class: "carte pile" },
        h("h2", {}, "Qui reçoit quelle alerte"),
        h("p", { class: "doux petit" }, "Chaque alerte devient une tâche dans la file du profil choisi (« Administration » : elle reste à " +
          "l'administration). Si personne ne la prend dans le délai, elle remonte au responsable du profil, ou à l'administration " +
          "s'il n'en a pas. Une alerte désactivée ne crée plus de tâche."),
        lignes));
  }

  return { titre: "Ma file", afficher };
})();
