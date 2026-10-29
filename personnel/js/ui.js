/* =========================================================
   UI — les petits outils d'écran partagés par toutes les vues :
   fabriquer un élément, afficher un message, poser une question,
   écrire un montant ou une date à la béninoise.
   ========================================================= */
const UI = (() => {

  /**
   * h("div", { class: "carte", onclick: f }, enfant1, "texte", …)
   * Le texte passe toujours par textContent : rien de ce qui vient de
   * la base ou d'un mail n'est jamais interprété comme du HTML.
   */
  function h(balise, attributs, ...enfants) {
    const el = document.createElement(balise);
    for (const [cle, valeur] of Object.entries(attributs || {})) {
      if (valeur === undefined || valeur === null || valeur === false) continue;
      if (cle.startsWith("on") && typeof valeur === "function") el.addEventListener(cle.slice(2), valeur);
      else if (cle === "class") el.className = valeur;
      else if (cle === "style" && typeof valeur === "object") Object.assign(el.style, valeur);
      else if (cle in el && typeof valeur !== "string") el[cle] = valeur;
      else el.setAttribute(cle, valeur === true ? "" : valeur);
    }
    ajouter(el, enfants);
    return el;
  }

  function ajouter(parent, enfants) {
    for (const e of enfants.flat(Infinity)) {
      if (e === null || e === undefined || e === false) continue;
      parent.append(e instanceof Node ? e : document.createTextNode(String(e)));
    }
  }

  function icone(nom, classe) {
    const ns = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(ns, "svg");
    svg.setAttribute("class", "ic " + (classe || ""));
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    const use = document.createElementNS(ns, "use");
    use.setAttribute("href", "#i-" + nom);
    svg.append(use);
    return svg;
  }

  function vider(el, ...enfants) {
    el.replaceChildren();
    ajouter(el, enfants);
    return el;
  }

  /* ---------- Messages ---------- */

  function toast(message, genre) {
    const zone = document.getElementById("toasts");
    const t = h("div", { class: "toast " + (genre || ""), role: "status" }, message);
    zone.append(t);
    setTimeout(() => t.remove(), genre === "erreur" ? 6000 : 3500);
  }

  const succes = (m) => toast(m, "succes");
  const echec = (err) => toast((err && err.message) || String(err), "erreur");

  const chargement = () => h("div", { class: "chargement", role: "progressbar", "aria-label": "Chargement" });
  const vide = (texte) => h("div", { class: "vide" }, texte);
  const erreur = (err) => h("div", { class: "erreur" }, (err && err.message) || String(err));

  /* ---------- Fenêtres ---------- */

  /**
   * Ouvre une fenêtre avec un formulaire. « champs » : [{ nom, libelle,
   * type, valeur, options, requis, aide, large }]. Rend les valeurs, ou
   * null si l'on annule. « verifier(valeurs) » peut renvoyer un message
   * d'erreur : la fenêtre reste ouverte.
   */
  function formulaire({ titre, texte, champs, valider, danger, verifier, quandSaisie }) {
    return new Promise((resoudre) => {
      const dlg = h("dialog", { class: "fenetre" });
      const zoneErreur = h("div", { class: "erreur", hidden: true });
      const entrees = {};
      const corps = h("div", { class: "corps" },
        texte ? h("p", { class: "doux" }, texte) : null,
        (champs || []).map((c) => {
          let entree;
          if (c.type === "select") {
            entree = h("select", { name: c.nom, required: !!c.requis },
              (c.options || []).map((o) => h("option", { value: o.valeur, selected: String(o.valeur) === String(c.valeur ?? "") }, o.libelle)));
          } else if (c.type === "textarea") {
            entree = h("textarea", { name: c.nom, required: !!c.requis, placeholder: c.indice || "" });
            entree.value = c.valeur ?? "";
          } else if (c.type === "checkbox") {
            entree = h("input", { type: "checkbox", name: c.nom, checked: !!c.valeur });
            entrees[c.nom] = entree;
            return h("label", { class: "case" }, entree, c.libelle);
          } else {
            entree = h("input", { type: c.type || "text", name: c.nom, required: !!c.requis,
              placeholder: c.indice || "", min: c.min, max: c.max, step: c.pas, autocomplete: c.autocomplete || "off" });
            entree.value = c.valeur ?? "";
          }
          entrees[c.nom] = entree;
          return h("label", { class: "champ" }, h("span", {}, c.libelle + (c.requis ? " *" : "")), entree,
            c.aide ? h("small", {}, c.aide) : null);
        }),
        zoneErreur);
      const annuler = h("button", { type: "button", class: "btn btn-second", onclick: () => { dlg.close(); } }, "Annuler");
      const ok = h("button", { type: "submit", class: "btn " + (danger ? "btn-danger" : "") }, valider || "Valider");
      const form = h("form", { method: "dialog" }, h("div", { class: "tete" }, titre), corps, h("div", { class: "pied" }, annuler, ok));
      let rendu = null;
      form.addEventListener("submit", (ev) => {
        ev.preventDefault();
        const valeurs = {};
        for (const [nom, e] of Object.entries(entrees)) {
          valeurs[nom] = e.type === "checkbox" ? e.checked : e.value.trim();
        }
        const probleme = verifier ? verifier(valeurs) : null;
        if (probleme) {
          zoneErreur.textContent = probleme;
          zoneErreur.hidden = false;
          return;
        }
        rendu = valeurs;
        dlg.close();
      });
      /* LA PROMESSE SE RÈGLE ICI, dans le code qui ferme, et pas dans
         l'écouteur « close » : Chrome le délivre à l'image suivante. */
      dlg.addEventListener("close", () => { dlg.remove(); });
      const fermer = dlg.close.bind(dlg);
      dlg.close = () => { fermer(); resoudre(rendu); };
      dlg.addEventListener("cancel", (ev) => { ev.preventDefault(); dlg.close(); });
      /* (3.70.0) « quandSaisie(nom, entrees) » : un champ en fait suivre un
         autre pendant la saisie (le réseau d'après le numéro, par exemple). */
      if (quandSaisie) {
        form.addEventListener("input", (ev) => {
          const nom = ev.target && ev.target.name;
          if (nom) quandSaisie(nom, entrees);
        });
      }
      dlg.append(form);
      document.body.append(dlg);
      dlg.showModal();
      const premier = form.querySelector("input,select,textarea");
      if (premier) premier.focus();
    });
  }

  async function confirmer(message, { titre, valider, danger } = {}) {
    const r = await formulaire({ titre: titre || "Confirmer", texte: message, champs: [], valider: valider || "Confirmer", danger });
    return r !== null;
  }

  /** Une raison obligatoire (refus, rejet). Null si l'on annule. */
  async function motif(titre, libelle) {
    const r = await formulaire({ titre, champs: [{ nom: "motif", libelle: libelle || "Motif", type: "textarea", requis: true }],
      valider: "Envoyer", danger: true, verifier: (v) => (v.motif ? null : "Le motif est obligatoire.") });
    return r ? r.motif : null;
  }

  /** Exécute une action en désactivant le bouton, et dit ce qui se passe. */
  async function agir(bouton, action, reussite) {
    if (bouton) bouton.disabled = true;
    try {
      const r = await action();
      if (reussite) succes(reussite);
      return r;
    } catch (err) {
      echec(err);
      throw err;
    } finally {
      if (bouton) bouton.disabled = false;
    }
  }

  /* ---------- Écritures ---------- */

  const nombre = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });
  const fcfa = (n) => nombre.format(Number(n || 0)) + " FCFA";
  const entier = (n) => nombre.format(Number(n || 0));

  function enDate(v) {
    if (!v) return null;
    if (v instanceof Date) return v;
    /* « 2026-09-01 » seul est une date du calendrier, pas un instant UTC :
       sans cela, elle reculerait d'un jour à l'ouest de Greenwich. */
    if (/^\d{4}-\d{2}-\d{2}$/.test(v)) {
      const [a, m, j] = v.split("-").map(Number);
      return new Date(a, m - 1, j);
    }
    return new Date(v);
  }

  const date = (v) => (v ? enDate(v).toLocaleDateString("fr-FR", { day: "2-digit", month: "2-digit", year: "numeric" }) : "—");
  const dateLongue = (v) => (v ? enDate(v).toLocaleDateString("fr-FR", { day: "numeric", month: "long", year: "numeric" }) : "—");
  const dateHeure = (v) => (v ? enDate(v).toLocaleString("fr-FR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
  const mois = (v) => {
    const t = enDate(v).toLocaleDateString("fr-FR", { month: "long", year: "numeric" });
    return t.charAt(0).toUpperCase() + t.slice(1);
  };

  /** « il y a 5 min », « 14:32 », « hier », « 12/09 ». */
  function quand(v) {
    if (!v) return "";
    const d = enDate(v);
    const maintenant = new Date();
    const ecart = (maintenant - d) / 60000;
    if (ecart < 1) return "à l'instant";
    if (ecart < 60) return "il y a " + Math.floor(ecart) + " min";
    if (d.toDateString() === maintenant.toDateString()) return d.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
    const hier = new Date(maintenant); hier.setDate(hier.getDate() - 1);
    if (d.toDateString() === hier.toDateString()) return "hier";
    return d.toLocaleDateString("fr-FR", { day: "2-digit", month: "2-digit", year: d.getFullYear() === maintenant.getFullYear() ? undefined : "2-digit" });
  }

  function age(naissance) {
    if (!naissance) return null;
    const n = enDate(naissance), a = new Date();
    let ans = a.getFullYear() - n.getFullYear();
    if (a.getMonth() < n.getMonth() || (a.getMonth() === n.getMonth() && a.getDate() < n.getDate())) ans--;
    return ans;
  }

  /** La date du jour au format de la base, à l'heure du poste. */
  function aujourdhui() {
    const d = new Date();
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }
  const premierDuMois = (d) => (d || aujourdhui()).slice(0, 8) + "01";

  const initiales = (nom, prenoms) =>
    ((prenoms || "").trim().charAt(0) + (nom || "").trim().charAt(0)).toUpperCase() || "?";

  const nomComplet = (e) => (e ? ((e.prenoms || "") + " " + (e.nom || "")).trim() : "—");

  /** Une étiquette de statut, couleur comprise. */
  /**
   * La période sur une seule ligne : les raccourcis (« 7 jours »…), puis
   * « du … au … » et « Afficher ». periode = { liste: [[cle, libelle, du, au]…],
   * choix, depuis, jusqu } ; route : l'adresse de la page, extra : ce qui
   * suit (« &pas=mois »). Rend la ligne, à poser dans un cadre.
   */
  function lignePeriode(periode, route, extra) {
    const du = h("input", { type: "date", value: periode.depuis, "aria-label": "Du" });
    const au = h("input", { type: "date", value: periode.jusqu, "aria-label": "Au" });
    const form = h("form", { class: "barre-compacte" },
      h("span", { class: "doux texte-long" }, "du"), du, h("span", { class: "doux texte-long" }, "au"), au,
      h("button", { class: "btn btn-second", type: "submit" }, h("span", { class: "texte-long" }, "Afficher"), h("span", { class: "texte-court" }, "OK")));
    form.addEventListener("submit", (ev) => {
      ev.preventDefault();
      if (au.value < du.value) return echec("La fin de la période précède son début.");
      location.hash = route + "?du=" + du.value + "&au=" + au.value + (extra || "");
    });
    return h("div", { class: "barre-compacte" },
      h("div", { class: "filtres" }, periode.liste.map(([cle, libelle]) =>
        h("button", { class: periode.choix && periode.choix[0] === cle ? "actif" : "",
                      onclick: () => { location.hash = route + "?p=" + cle + (extra || ""); } }, libelle))),
      form);
  }
  /** La même, seule dans son cadre. */
  const barrePeriode = (periode, route, extra) => h("div", { class: "carte compacte" }, lignePeriode(periode, route, extra));

  function etiquette(texte, couleur) {
    return h("span", { class: "etiquette " + (couleur || "") }, texte);
  }

  /* ---------- (3.70.0) L'opérateur d'un numéro béninois ----------
     Depuis le 30 novembre 2024, un numéro mobile s'écrit « 01 » + les
     8 chiffres d'avant ; les deux chiffres qui suivent « 01 » disent le
     réseau d'origine. Ce sont ceux du SDK de FeexPay, et ceux du plan
     d'avant (« 97… » MTN, « 95… » Moov, « 40… » Celtiis) : un numéro
     dicté à l'ancienne, sur 8 chiffres, se lit de la même façon.
     On s'en sert pour CORRIGER le réseau choisi et pour repérer un
     numéro tapé à la place d'un ID de transaction — jamais pour
     interdire : le client reste maître de son choix. */
  const PREFIXES_OPERATEURS = {
    MTN: ["42", "46", "50", "51", "52", "53", "54", "56", "57", "59", "61", "62",
          "66", "67", "69", "90", "91", "92", "93", "96", "97"],
    MOOV: ["45", "55", "58", "60", "63", "64", "65", "68", "94", "95", "98", "99"],
    CELTIIS: ["40", "41", "43", "44", "47"],
  };
  const NOM_OPERATEUR = { MTN: "MTN", MOOV: "Moov", CELTIIS: "Celtiis" };

  /** Les chiffres nationaux d'un numéro : sans « +229 », « 00229 » ni espaces. */
  function chiffresNationaux(tel) {
    let n = String(tel || "").replace(/\D/g, "");
    if (/^00229/.test(n)) n = n.slice(5);
    else if (/^229/.test(n) && (n.length === 13 || n.length === 11)) n = n.slice(3);
    return n;
  }

  /** « MTN », « MOOV », « CELTIIS », ou "" si le numéro ne le dit pas. */
  function reseauDuNumero(tel) {
    const n = chiffresNationaux(tel);
    const p = n.length === 10 && n.startsWith("01") ? n.slice(2, 4)
      : n.length === 8 ? n.slice(0, 2) : "";
    if (!p) return "";
    return Object.keys(PREFIXES_OPERATEURS).find((r) => PREFIXES_OPERATEURS[r].includes(p)) || "";
  }

  /** Un texte qui n'est QU'UN numéro de téléphone (chiffres, espaces,
      « + », tirets, points) : rend son opérateur, sinon "". C'est ce qui
      trahit un numéro saisi à la place d'un ID de transaction. */
  function ressembleTelephone(texte) {
    const t = String(texte || "").trim();
    if (!t || /[^\d\s+().-]/.test(t)) return "";
    return reseauDuNumero(t);
  }

  /** Le message à montrer quand un ID de transaction ressemble à un numéro. */
  function alerteTransaction(texte) {
    const op = ressembleTelephone(texte);
    return op
      ? "« " + String(texte).trim() + " » ressemble à un numéro de téléphone " + NOM_OPERATEUR[op] +
        ", pas à un ID de transaction. Recopiez l'ID indiqué dans le SMS de paiement " +
        "(s'il est vraiment juste, validez à nouveau)."
      : "";
  }

  return {
    reseauDuNumero, ressembleTelephone, alerteTransaction, NOM_OPERATEUR,
    h, ajouter, icone, vider, toast, succes, echec, chargement, vide, erreur,
    formulaire, confirmer, motif, agir,
    fcfa, entier, date, dateLongue, dateHeure, mois, quand, age, aujourdhui, premierDuMois,
    initiales, nomComplet, etiquette, enDate, lignePeriode, barrePeriode,
  };
})();
