/* =========================================================
   Le pixel Meta — ce que la publicité apprend du site

   Dix événements, et pas un de plus : les pages vues, le produit
   consulté, l'ajout au panier, la commande lancée, le moyen de
   paiement choisi, l'achat payé, l'inscription, la demande de
   compte revendeur, la recherche, et le contact par WhatsApp,
   téléphone ou e-mail.

   QUATRE RÈGLES, et c'est ce module qui les tient — pas les
   écrans, qui ne font que dire « ceci vient d'arriver ».

   1. LE SITE, ET RIEN D'AUTRE. Le pixel ne se charge que sur
      l'adresse officielle. L'application Android sert ces mêmes
      fichiers depuis appassets.androidx.dev, celle de l'iPhone
      depuis le téléphone lui-même, la copie de GitHub Pages depuis
      github.io : aucune ne parle à Meta. La fiche Google Play n'a
      donc rien à déclarer de plus, et l'iPhone n'a pas à demander
      l'autorisation de suivre.

   2. AUCUNE DONNÉE PERSONNELLE. Ni nom, ni numéro, ni e-mail : des
      identifiants de produits, des montants, un numéro de commande.
      Une recherche qui ressemble à un numéro ou à une adresse
      e-mail ne part pas. La configuration automatique de Meta est
      coupée : elle relève d'elle-même les clics et le contenu des
      pages, et ce n'est pas ce que BIZZOO a choisi d'envoyer.

   3. UN ENVOI PAR ACTION. Un écran redessiné — le catalogue qui se
      met à jour, les prix d'un revendeur qui arrivent — n'est pas
      une nouvelle visite. Un achat ne compte qu'une fois, même si
      le reçu se rouvre dix fois. Meta suit aussi tout seul les
      changements d'adresse des applications d'une page : on le lui
      interdit, sinon chaque écran compterait deux fois.

   4. JAMAIS DE JETON VERS META. Le lien « mot de passe oublié »
      ramène le client avec sa session dans l'adresse. Meta reçoit
      l'adresse de la page avec chaque événement : rien ne part tant
      qu'elle porte un jeton. C'est pourquoi le pixel ne se charge
      qu'au premier écran dessiné — après que l'application a lu le
      jeton et nettoyé l'adresse.
   ========================================================= */
const Pixel = (() => {
  const ID = "1786119222612781";
  const SITES = ["www.bizzoomarket.com", "bizzoomarket.com"];
  const actif = SITES.indexOf(location.hostname) >= 0;

  /* ---------- Le chargement, au premier envoi ---------- */

  let charge = false;
  function charger() {
    if (charge) return;
    charge = true;
    /* Le code de base de Meta, tel qu'il le donne. */
    !function (f, b, e, v, n, t, s) {
      if (f.fbq) return; n = f.fbq = function () {
        n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments);
      };
      if (!f._fbq) f._fbq = n; n.push = n; n.loaded = !0; n.version = "2.0";
      n.queue = []; t = b.createElement(e); t.async = !0;
      t.src = v; s = b.getElementsByTagName(e)[0];
      s.parentNode.insertBefore(t, s);
    }(window, document, "script", "https://connect.facebook.net/en_US/fbevents.js");
    window.fbq.disablePushState = true;
    window.fbq("set", "autoConfig", false, ID);
    window.fbq("init", ID);
  }

  const adresseAJeton = () =>
    /(^|[#&?/])(access_token|refresh_token|error_code|token_hash)=/.test(location.href);

  function envoyer(nom, donnees, options) {
    if (!actif || adresseAJeton()) return false;
    charger();
    try {
      if (options) window.fbq("track", nom, donnees || {}, options);
      else window.fbq("track", nom, donnees || {});
    } catch (_) { /* la publicité ne casse jamais la boutique */ }
    return true;
  }

  /* ---------- Les montants et la monnaie ----------
     Un nombre simple — 18500, ni espace ni symbole — et le code de la
     monnaie. « FCFA » est le franc d'Afrique de l'Ouest : XOF. */

  const valeur = (x) => {
    const n = Math.round(Number(x));
    return isFinite(n) && n > 0 ? n : 0;
  };

  function devise(d) {
    const brut = String(d || "").toUpperCase().replace(/[\s.]/g, "");
    if (!brut || /^(F?CFA|FRANCSCFA|F|XOF)$/.test(brut)) return "XOF";
    return /^[A-Z]{3}$/.test(brut) ? brut : "XOF";
  }

  const ids = (liste) => [...new Set(liste.map((x) => String(x || "")).filter(Boolean))];

  /* ---------- Ce qui a déjà été dit ----------
     Gardé sur le téléphone, pour qu'un reçu rouvert demain ne
     rapporte pas l'achat une seconde fois. Sans stockage — navigation
     privée —, la mémoire de la page suffit à ne rien doubler. */

  const CLE = "bizzoo-pixel";
  const memoire = { achats: [], comptes: [] };
  try {
    const lu = JSON.parse(localStorage.getItem(CLE) || "{}");
    if (Array.isArray(lu.achats)) memoire.achats = lu.achats;
    if (Array.isArray(lu.comptes)) memoire.comptes = lu.comptes;
  } catch (_) { /* rien de gardé */ }

  function noter(liste, id) {
    memoire[liste] = [String(id)].concat(memoire[liste].filter((x) => x !== String(id))).slice(0, 60);
    try { localStorage.setItem(CLE, JSON.stringify(memoire)); } catch (_) { /* la mémoire de la page suffit */ }
  }
  const dejaDit = (liste, id) => memoire[liste].indexOf(String(id)) >= 0;

  /* ---------- 1. PageView, à chaque écran ----------
     Le routeur annonce le début d'un écran, puis sa fin. La page vue
     ne part qu'à la fin, et seulement si l'écran est resté celui qu'on
     a demandé : un écran qui renvoie aussitôt ailleurs — le panier vide
     qui ramène à l'accueil — n'est pas une visite, et la suivante
     comptera. Le produit consulté attend la page vue, pour arriver
     dans l'ordre.

     Un écran qui travaille longtemps est pourtant bien sous les yeux du
     client : le reçu qui patiente pour le paiement ne rend la main
     qu'une fois le versement confirmé, jusqu'à une minute et demie plus
     tard. Au bout de deux secondes, s'il est toujours là, il compte. */

  let navigation = 0;
  let dite = -1;
  let minuteur = null;
  let enAttente = [];
  const vusIci = new Set();

  function debutEcran(ecran) {
    navigation++;
    enAttente = [];
    vusIci.clear();
    clearTimeout(minuteur);
    const ici = navigation;
    if (ecran) minuteur = setTimeout(() => { if (ici === navigation) finEcran(ecran); }, 2000);
  }

  function finEcran(ecran) {
    if (dite === navigation) return;
    clearTimeout(minuteur);
    const attente = enAttente;
    enAttente = [];
    if ((location.hash || "#/") !== ecran) return;
    dite = navigation;
    envoyer("PageView");
    for (const [nom, donnees] of attente) envoyer(nom, donnees);
  }

  /* ---------- 2. ViewContent, la fiche ouverte ---------- */

  function produitVu(p, deviseProduit) {
    if (!p || !p.id || vusIci.has(p.id)) return;
    vusIci.add(p.id);
    const vu = ["ViewContent", {
      content_ids: [String(p.id)],
      content_name: String(p.nom || ""),
      content_type: "product",
      value: valeur(p.prix),
      currency: devise(deviseProduit),
    }];
    /* La page vue est déjà partie — écran lent : on n'attend plus. */
    if (dite === navigation) envoyer(vu[0], vu[1]);
    else enAttente.push(vu);
  }

  /* ---------- 3. AddToCart, ce qui est vraiment entré ---------- */

  function ajoutPanier(p, quantite, deviseProduit) {
    const n = Math.max(0, Math.round(Number(quantite) || 0));
    if (!p || !p.id || !n) return;
    envoyer("AddToCart", {
      content_ids: [String(p.id)],
      content_name: String(p.nom || ""),
      content_type: "product",
      num_items: n,
      value: valeur((Number(p.prix) || 0) * n),
      currency: devise(deviseProduit),
    });
  }

  /* ---------- 4 et 9. Le panier qu'on commande ---------- */

  function contenuDuPanier(lignes) {
    return {
      content_ids: ids((lignes || []).map((l) => l.produit && l.produit.id)),
      content_type: "product",
      num_items: (lignes || []).reduce((s, l) => s + (Number(l.quantite) || 0), 0),
    };
  }

  function debutCommande(lignes, total, deviseDuPanier) {
    if (!lignes || !lignes.length) return;
    envoyer("InitiateCheckout", Object.assign(contenuDuPanier(lignes), {
      value: valeur(total), currency: devise(deviseDuPanier),
    }));
  }

  /** Une fois par écran de paiement : au choix de l'opérateur, ou au
      « Payer » si le client a gardé celui qu'on lui proposait. */
  let paiementDit = -1;
  function infosPaiement(lignes, montant, deviseDuPanier, moyen) {
    if (paiementDit === navigation || !lignes || !lignes.length) return;
    paiementDit = navigation;
    envoyer("AddPaymentInfo", Object.assign(contenuDuPanier(lignes), {
      value: valeur(montant), currency: devise(deviseDuPanier),
      payment_method: String(moyen || ""),
    }));
  }

  /* ---------- 5. Purchase, le paiement confirmé ----------
     Appelé quand la BASE confirme le versement, jamais au clic sur
     « Payer » : ce que dit le téléphone n'engage personne. Seules les
     commandes passées depuis ce téléphone comptent — une commande
     d'un autre appareil, relue ici, a déjà été rapportée là-bas. */

  function achat(commande) {
    if (!commande || !commande.id || dejaDit("achats", commande.id)) return;
    noter("achats", commande.id);
    /* Une commande d'il y a plus d'une semaine, dont la confirmation
       n'est relue qu'aujourd'hui, n'est pas un achat du jour : Meta la
       daterait de maintenant. */
    if (commande.gardeeLe && Date.now() - Number(commande.gardeeLe) > 7 * 864e5) return;
    const lignes = [];
    for (const b of commande.boutiques || []) for (const l of b.lignes || []) lignes.push(l);
    const numero = String(commande.numero || commande.id);
    envoyer("Purchase", {
      content_ids: ids(lignes.map((l) => l.produit_id)),
      content_type: "product",
      num_items: lignes.reduce((s, l) => s + (Number(l.quantite) || 0), 0),
      value: valeur(commande.total),
      currency: devise(commande.devise),
      order_id: numero,
    }, { eventID: "achat-" + numero });
  }

  /* ---------- 6 et 7. Le compte, et la demande de revendeur ---------- */

  /** Un compte ouvert par son numéro : le code validé dit-il une
      naissance, ou un retour ? Le compte est né à la demande du code ;
      un client qui revient l'a vu naître il y a longtemps. */
  function compteNeuf(user) {
    if (!user) return false;
    const ne = Date.parse(user.created_at || "");
    const entre = Date.parse(user.last_sign_in_at || "") || Date.now();
    if (!isFinite(ne)) return false;
    const ecart = entre - ne;
    return ecart >= 0 && ecart < 15 * 60000;
  }

  function inscription(type) {
    envoyer("CompleteRegistration", {
      content_name: type === "revendeur" ? "revendeur" : "client",
      status: true,
    });
  }

  /** Entrer par son numéro crée le compte au premier code : seule cette
      fois-là est une inscription. */
  function entreeParCode(user, type) {
    if (!compteNeuf(user) || !user.id || dejaDit("comptes", user.id)) return;
    noter("comptes", user.id);
    inscription(type || "client");
  }

  function demandeRevendeur() {
    envoyer("Lead", { content_name: "revendeur" });
  }

  /* ---------- 8. Search ----------
     La recherche se fait pendant qu'on tape : une lettre n'est pas une
     recherche. Elle part quand le client s'arrête, ou appuie sur
     Entrée — et une seule fois pour les mêmes mots. */

  let derniereRecherche = "";
  function recherche(terme) {
    const t = String(terme || "").trim().replace(/\s+/g, " ");
    if (t.length < 2 || t.toLowerCase() === derniereRecherche) return;
    /* Un numéro ou une adresse e-mail tapés dans la recherche ne
       partent pas : ce serait une donnée personnelle, en clair. */
    if (/@/.test(t) || /(\d[\s.-]?){8,}/.test(t)) return;
    derniereRecherche = t.toLowerCase();
    envoyer("Search", { search_string: t });
  }

  /* ---------- 10. Contact ----------
     Les liens WhatsApp, téléphone et e-mail de la boutique sont des
     liens ordinaires : on les écoute tous à un seul endroit. Un lien
     WhatsApp sans numéro est un PARTAGE, pas un contact. */

  if (actif) {
    document.addEventListener("click", (ev) => {
      const lien = ev.target && ev.target.closest ? ev.target.closest("a[href]") : null;
      if (!lien) return;
      const href = lien.getAttribute("href") || "";
      const canal = /^https:\/\/(wa\.me|api\.whatsapp\.com\/send\?phone=)\/?\d/.test(href) ? "whatsapp"
        : /^tel:/.test(href) ? "telephone"
        : /^mailto:/.test(href) ? "email" : "";
      if (canal) envoyer("Contact", { content_name: canal });
    }, true);
  }

  return {
    actif, debutEcran, finEcran, produitVu, ajoutPanier, debutCommande,
    infosPaiement, achat, inscription, entreeParCode, demandeRevendeur, recherche,
  };
})();
