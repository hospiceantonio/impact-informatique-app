/* =========================================================
   BIZZOO — deux langues : français et anglais (3.73.0)

   UN SEUL FICHIER pour les trois applications (client, admin, personnel) :
   celui-ci est l'original ; tools/synchroniser-langue.sh le recopie à
   l'identique dans admin/js/ et personnel/js/.

   LA LANGUE : celle choisie au bouton FR / EN (retenue sur l'appareil),
   sinon celle du téléphone ou du navigateur — l'anglais s'il est en
   anglais, le français dans tous les autres cas.

   LA TRADUCTION se fait À L'AFFICHAGE. Les applications écrivent leurs
   écrans en français, comme toujours ; en anglais, chaque texte qui
   arrive à l'écran — et les attributs lus par l'utilisateur :
   placeholder, title, aria-label, alt — passe par le dictionnaire de
   l'application (js/traductions-en.js, fabriqué par
   tools/extraire-textes.mjs) :
     1. le texte entier, s'il y figure ;
     2. sinon un des « motifs » (phrases à trous : « Plus que 3 en stock ») ;
     3. sinon chaque morceau connu du texte, remplacé sur place
        (« Commande BZ-0042 payée » → « Order BZ-0042 paid »).
   Ce qui ne figure pas au dictionnaire reste tel quel.

   CE QUE SAISISSENT LES GENS N'EST JAMAIS TRADUIT : un élément marqué
   translate="no" (nom de produit, description, adresse, message…) et
   tout ce qu'il contient est laissé tel quel, comme les champs de saisie.

   LES DATES ET LES NOMBRES suivent la langue : en anglais, « fr-FR »
   devient « en-GB » pour toLocaleDateString, toLocaleString,
   toLocaleTimeString et Intl.DateTimeFormat / Intl.NumberFormat.
   ========================================================= */
(function () {
  "use strict";

  const CLE = "bizzoo-langue";
  const LANGUES = ["fr", "en"];

  function lireChoix() {
    try {
      const v = localStorage.getItem(CLE);
      if (LANGUES.includes(v)) return v;
    } catch (_) { /* stockage fermé : on suit l'appareil */ }
    return null;
  }

  function langueAppareil() {
    const liste = (navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "fr"]);
    const premiere = String(liste[0] || "fr").toLowerCase();
    return premiere.startsWith("en") ? "en" : "fr";
  }

  const courante = lireChoix() || langueAppareil();
  const enAnglais = courante === "en";

  /* L'application Android écrit elle-même quelques textes (canaux de
     notification, messages de position) : elle suit la langue de la page. */
  const direAuTelephone = (l) => {
    try { if (window.AndroidPont && typeof window.AndroidPont.langue === "function") window.AndroidPont.langue(l); }
    catch (_) { /* une application d'avant : rien à dire */ }
  };
  direAuTelephone(courante);

  /* ---------- Les dates et les nombres ---------- */
  if (enAnglais) {
    const versAnglais = (loc) => {
      if (loc === undefined || loc === null) return "en-GB";
      if (Array.isArray(loc)) return loc.map(versAnglais);
      return /^fr\b/i.test(String(loc)) ? "en-GB" : loc;
    };
    const habiller = (proto, nom) => {
      const original = proto[nom];
      if (typeof original !== "function") return;
      proto[nom] = function (loc, options) { return original.call(this, versAnglais(loc), options); };
    };
    habiller(Date.prototype, "toLocaleDateString");
    habiller(Date.prototype, "toLocaleString");
    habiller(Date.prototype, "toLocaleTimeString");
    habiller(Number.prototype, "toLocaleString");
    for (const nom of ["DateTimeFormat", "NumberFormat"]) {
      const Original = Intl[nom];
      if (typeof Original !== "function") continue;
      const Habille = function (loc, options) { return new Original(versAnglais(loc), options); };
      Habille.prototype = Original.prototype;
      Habille.supportedLocalesOf = Original.supportedLocalesOf;
      Intl[nom] = Habille;
    }
  }

  /* ---------- Le dictionnaire ---------- */
  let exact = null;          // Map texte français → anglais
  let motifs = [];           // [RegExp, remplacement]
  let morceaux = null;       // RegExp de tous les morceaux connus
  let morceauxMap = null;

  const LETTRE = "A-Za-zÀ-ÖØ-öø-ÿŒœ";
  const echapper = (t) => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

  function preparer() {
    if (exact) return true;
    const d = window.BIZZOO_EN;
    if (!d) return false;
    exact = new Map(Object.entries(d.exact || d));
    motifs = (d.motifs || []).map(([m, r]) => {
      try { return [new RegExp(m, "u"), r]; } catch (_) { return null; }
    }).filter(Boolean);
    /* Les morceaux : tout texte du dictionnaire d'au moins 4 caractères,
       les plus longs d'abord (« Commande payée » avant « Commande »), et
       seulement entre deux non-lettres : « Commande » ne se remplace pas
       dans « Commandez ». */
    const cles = [...exact.keys()].filter((k) => k.length >= 4 && k.length <= 800 && exact.get(k))
      .sort((a, b) => b.length - a.length);
    morceauxMap = new Map(cles.map((k) => [k.toLowerCase(), k]));
    /* La frontière ne vaut que du côté d'une lettre : « , ou vous… » se
       reconnaît aussi collé à « réglé ». */
    const lettre = new RegExp("[" + LETTRE + "]", "u");
    if (cles.length) {
      morceaux = new RegExp(cles.map((k) => (lettre.test(k[0]) ? "(?<![" + LETTRE + "])" : "") + echapper(k) +
        (lettre.test(k[k.length - 1]) ? "(?![" + LETTRE + "])" : "")).join("|"), "giu");
    }
    return true;
  }

  /** Respecter la casse du texte d'origine : « COMMANDE » → « ORDER ». */
  function casse(origine, traduit) {
    if (origine.length > 1 && origine === origine.toUpperCase() && origine !== origine.toLowerCase()) return traduit.toUpperCase();
    if (/^[a-zà-ÿ]/.test(origine) && /^[A-Z]/.test(traduit) && !/^[A-Z]{2}/.test(traduit)) {
      return traduit.charAt(0).toLowerCase() + traduit.slice(1);
    }
    return traduit;
  }

  const cache = new Map();

  /** La traduction d'un texte (ou le texte lui-même si rien ne s'applique). */
  function traduire(texte) {
    if (!enAnglais || !texte || !preparer()) return texte;
    /* Un texte de plusieurs lignes : d'abord en entier (un paragraphe écrit
       sur plusieurs lignes dans le HTML), sinon ligne par ligne (une alerte
       de course, une notification). */
    if (texte.includes("\n")) {
      const plat = texte.trim().replace(/[\s\u00a0\u202f]+/g, " ");
      if (exact.has(plat)) return traduireUn(texte);
      /* Des retours à la ligne suivis d'espaces : la mise en page du HTML,
         pas des lignes — le paragraphe se traduit d'un bloc. */
      if (/\n[ \t]/.test(texte.trim())) return traduireUn(texte);
      return texte.split("\n").map(traduireUn).join("\n");
    }
    return traduireUn(texte);
  }

  function traduireUn(texte) {
    const debut = texte.match(/^\s*/)[0];
    const fin = texte.match(/\s*$/)[0];
    /* Les espaces insécables (« Retour à&nbsp;Bizzoo ») comptent comme des
       espaces : le dictionnaire n'en a pas. */
    const s = texte.slice(debut.length, texte.length - fin.length).replace(/[\s\u00a0\u202f]+/g, " ");
    if (!s || !/[A-Za-zÀ-ÿ]/.test(s)) return texte;
    if (cache.has(s)) return debut + cache.get(s) + fin;
    let r = exact.get(s);
    if (r === undefined) {
      for (const [m, remplacement] of motifs) {
        if (m.test(s)) { r = s.replace(m, remplacement); break; }
      }
    }
    if (r === undefined && morceaux) {
      let trouves = 0;
      const essai = s.replace(morceaux, (trouve) => {
        const cle = exact.has(trouve) ? trouve : morceauxMap.get(trouve.toLowerCase());
        const t = cle ? exact.get(cle) : null;
        if (!t) return trouve;
        trouves++;
        return "\u0001" + casse(trouve, t) + "\u0002";
      });
      /* PAS DE TRADUCTION À MOITIÉ. Un texte fait de morceaux connus, de
         nombres, de codes et de noms propres (« Commande BZ-0042 payée »)
         se traduit morceau par morceau ; une phrase écrite par quelqu'un
         (« Très bon casque, livré avec son câble ») garde des mots français
         en minuscules que le dictionnaire ne connaît pas : elle reste telle
         quelle, plutôt que d'en sortir mi-française, mi-anglaise. */
      const reste = essai.replace(/\u0001[^\u0002]*\u0002/g, " ").replace(/\S+@\S+|https?:\/\/\S+/g, " ");
      const inconnus = (reste.match(/(?<![A-Za-zÀ-ÿ])[a-zà-ÿœ][a-zà-ÿœ'’-]{2,}/g) || []).length;
      r = trouves && inconnus <= Math.max(1, trouves - 1) && inconnus < 3
        ? essai.replace(/[\u0001\u0002]/g, "") : s;
    }
    if (r === undefined || r === null) r = s;
    if (cache.size > 5000) cache.clear();
    cache.set(s, r);
    return debut + r + fin;
  }

  /* ---------- L'écran ---------- */
  const ATTRIBUTS = ["placeholder", "title", "aria-label", "alt", "data-titre"];
  const IGNORER = new Set(["SCRIPT", "STYLE", "TEXTAREA", "CODE", "PRE", "NOSCRIPT", "TEMPLATE"]);
  const deja = new WeakMap();            // nœud texte → ce qu'on y a écrit

  function protege(el) {
    for (let e = el; e && e.nodeType === 1; e = e.parentElement) {
      if (IGNORER.has(e.tagName)) return true;
      const t = e.getAttribute("translate");
      if (t === "no") return true;
      if (t === "yes") return false;
      if (e.isContentEditable) return true;
    }
    return false;
  }

  function texteNoeud(n) {
    if (deja.get(n) === n.data) return;
    const p = n.parentElement;
    if (!p || protege(p)) return;
    const t = traduire(n.data);
    if (t !== n.data) n.data = t;
    deja.set(n, n.data);
  }

  function attributs(el) {
    if (protege(el)) return;
    for (const a of ATTRIBUTS) {
      const v = el.getAttribute(a);
      if (!v) continue;
      const marque = "data-en-" + a;
      if (el.getAttribute(marque) === v) continue;
      const t = traduire(v);
      if (t !== v) el.setAttribute(a, t);
      el.setAttribute(marque, t);
    }
    /* Les boutons écrits en valeur : <input type="button" value="…">. */
    if (el.tagName === "INPUT" && /^(button|submit|reset)$/i.test(el.type) && el.value) {
      const t = traduire(el.value);
      if (t !== el.value) el.value = t;
    }
  }

  function parcourir(racine) {
    if (!racine) return;
    if (racine.nodeType === 3) { texteNoeud(racine); return; }
    if (racine.nodeType !== 1 && racine.nodeType !== 9 && racine.nodeType !== 11) return;
    if (racine.nodeType === 1) {
      if (protege(racine)) return;
      attributs(racine);
    }
    const marcheur = document.createTreeWalker(racine, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
      acceptNode(n) {
        if (n.nodeType === 1) {
          if (IGNORER.has(n.tagName) || n.getAttribute("translate") === "no" || n.isContentEditable) return NodeFilter.FILTER_REJECT;
          return NodeFilter.FILTER_ACCEPT;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    let n;
    while ((n = marcheur.nextNode())) {
      if (n.nodeType === 3) texteNoeud(n); else attributs(n);
    }
  }

  /** « Langue · Language  [FR|EN] » : une ligne prête à poser dans un écran. */
  function ligne() {
    style();
    const l = document.createElement("div");
    l.className = "langue-ligne";
    l.setAttribute("translate", "no");
    const t = document.createElement("span");
    t.textContent = enAnglais ? "Language" : "Langue";
    l.appendChild(t);
    l.appendChild(bouton());
    return l;
  }

  /* UNE PLACE POUR LE BOUTON : tout élément vide marqué data-langue reçoit la
     ligne « Langue  [FR|EN] » — l'application n'a qu'à poser la place. */
  function poserBoutons(racine) {
    const liste = racine && racine.querySelectorAll ? racine.querySelectorAll("[data-langue]") : [];
    for (const el of liste) if (!el.querySelector(".langue-choix")) el.appendChild(ligne());
    if (racine && racine.nodeType === 1 && racine.hasAttribute("data-langue") && !racine.querySelector(".langue-choix")) {
      racine.appendChild(ligne());
    }
  }

  function demarrer() {
    poserBoutons(document);
    new MutationObserver((mutations) => {
      for (const m of mutations) for (const n of m.addedNodes) if (n.nodeType === 1) poserBoutons(n);
    }).observe(document.documentElement, { childList: true, subtree: true });
    /* La vitrine et les pages légales : un bouton flottant, en haut à droite. */
    if (document.documentElement.hasAttribute("data-langue-flottant") && document.body) {
      document.body.appendChild(bouton("langue-flottant"));
    }
    if (!enAnglais) return;
    document.documentElement.lang = "en";
    parcourir(document.documentElement);
    const obs = new MutationObserver((mutations) => {
      for (const m of mutations) {
        if (m.type === "characterData") texteNoeud(m.target);
        else if (m.type === "attributes") attributs(m.target);
        else for (const n of m.addedNodes) parcourir(n);
      }
    });
    obs.observe(document.documentElement, { childList: true, subtree: true, characterData: true,
      attributes: true, attributeFilter: ATTRIBUTS });
  }

  /* Les boîtes du navigateur (rares : les applications ont les leurs). */
  if (enAnglais) {
    for (const nom of ["alert", "confirm", "prompt"]) {
      const original = window[nom];
      if (typeof original !== "function") continue;
      window[nom] = function (message, ...reste) { return original.call(window, traduire(String(message ?? "")), ...reste); };
    }
  }

  /* ---------- Changer de langue ---------- */
  const rappels = [];

  function choisir(langue) {
    if (!LANGUES.includes(langue)) return;
    try { localStorage.setItem(CLE, langue); } catch (_) { /* tant pis : la session seule */ }
    direAuTelephone(langue);
    for (const f of rappels) {
      try { f(langue); } catch (_) { /* un rappel qui échoue n'empêche pas le changement */ }
    }
    if (langue !== courante) {
      /* Laisser une seconde aux rappels (la base retient la langue du compte). */
      setTimeout(() => location.reload(), 350);
    }
  }

  /* L'allure du bouton, la même dans les trois applications et la vitrine. */
  function style() {
    if (document.getElementById("langue-style")) return;
    const st = document.createElement("style");
    st.id = "langue-style";
    st.textContent = ".langue-choix{display:inline-flex;border:1px solid #cfd8e6;border-radius:999px;overflow:hidden;background:#fff;vertical-align:middle}" +
      ".langue-choix button{border:0;background:none;padding:6px 12px;font:600 13px/1 inherit;font-family:inherit;color:#334155;cursor:pointer;min-width:44px;min-height:32px}" +
      ".langue-choix button.actif{background:#0A7C88;color:#fff}" +
      ".langue-flottant{position:fixed;top:10px;right:10px;z-index:50;box-shadow:0 4px 14px -6px rgba(32,51,59,.45)}" +
      ".langue-ligne{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}";
    (document.head || document.documentElement).appendChild(st);
  }

  /** Un bouton « FR | EN » : la langue active est marquée. */
  function bouton(classe) {
    style();
    const zone = document.createElement("div");
    zone.className = "langue-choix" + (classe ? " " + classe : "");
    zone.setAttribute("role", "group");
    zone.setAttribute("aria-label", enAnglais ? "Language" : "Langue");
    zone.setAttribute("translate", "no");
    for (const l of LANGUES) {
      const b = document.createElement("button");
      b.type = "button";
      b.textContent = l.toUpperCase();
      b.setAttribute("aria-pressed", String(l === courante));
      b.setAttribute("aria-label", l === "fr" ? "Français" : "English");
      if (l === courante) b.className = "actif";
      b.addEventListener("click", () => choisir(l));
      zone.appendChild(b);
    }
    return zone;
  }

  window.Langue = {
    courante: () => courante,
    enAnglais: () => enAnglais,
    choisie: () => lireChoix() !== null,
    choisir,
    bouton,
    ligne,
    traduire,
    /* Appelé à chaque changement de langue (et par l'application, après la
       connexion, pour dire à la base la langue de ce compte). */
    surChoix: (f) => { if (typeof f === "function") rappels.push(f); },
    /* Pour l'application, un texte qu'elle compose hors de l'écran. */
    t: (texte) => traduire(texte),
  };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", demarrer);
  else demarrer();
})();
