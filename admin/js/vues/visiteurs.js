/* =========================================================
   Visiteurs (4.6.0) — qui passe dans la boutique.

   Combien de visiteurs par jour, combien de temps ils restent,
   ce qu'ils ouvrent le plus, et combien vont jusqu'au panier
   puis jusqu'à la commande payée. Le site et l'application
   Android comptent ensemble.

   Des totaux seulement : la boutique note ses visites sans nom
   ni numéro (client/js/audience.js), et la base ne rend que des
   nombres (statistiques_visiteurs, réservée au
   superadministrateur).
   ========================================================= */
const VueVisiteurs = (() => {
  const e = (s) => Utils.echapper(s);
  const PERIODES = [
    { cle: "7j", nom: "7 jours", jours: 6 },
    { cle: "30j", nom: "30 jours", jours: 29 },
    { cle: "mois", nom: "Ce mois" },
    { cle: "12m", nom: "12 mois", jours: 364 },
  ];
  let periode = "30j";

  const iso = (d) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  function bornes() {
    const j = new Date();
    const p = PERIODES.find((x) => x.cle === periode) || PERIODES[1];
    if (p.cle === "mois") return { depuis: iso(new Date(j.getFullYear(), j.getMonth(), 1)), jusqu: iso(j) };
    const d = new Date(j);
    d.setDate(d.getDate() - p.jours);
    return { depuis: iso(d), jusqu: iso(j) };
  }
  /** « 3 min 20 s », « 45 s », « 1 h 05 ». */
  function duree(s) {
    s = Math.max(0, Math.round(Number(s) || 0));
    if (s < 60) return s + " s";
    if (s < 3600) return Math.floor(s / 60) + " min " + String(s % 60).padStart(2, "0") + " s";
    return Math.floor(s / 3600) + " h " + String(Math.floor((s % 3600) / 60)).padStart(2, "0");
  }
  const part = (n, sur) => (sur > 0 ? Math.round(n / sur * 1000) / 10 : 0);
  const pc = (n) => String(n).replace(".", ",") + " %";
  const tuile = (valeur, nom) => '<div class="vi-tuile"><strong>' + e(valeur) + "</strong><span>" + e(nom) + "</span></div>";

  /** Du premier au dernier jour : un jour sans visite compte, à zéro. */
  function joursComplets(jours, b) {
    const parJour = new Map(jours.map((j) => [String(j.jour).slice(0, 10), j]));
    const liste = [];
    const d = new Date(b.depuis + "T00:00:00");
    const fin = new Date(b.jusqu + "T00:00:00");
    while (d <= fin && liste.length < 400) {
      const cle = iso(d);
      liste.push(parJour.get(cle) || { jour: cle, visiteurs: 0, visites: 0, duree_moyenne_s: 0 });
      d.setDate(d.getDate() + 1);
    }
    return liste;
  }
  function htmlBarres(jours) {
    const max = Math.max(1, ...jours.map((j) => Number(j.visiteurs) || 0));
    const court = (j) => new Date(j + "T00:00:00").toLocaleDateString("fr-FR", { day: "numeric", month: "short" });
    return '<div class="vi-barres" id="vi-barres">' + jours.map((j) =>
      '<div class="vi-barre" title="' + e(court(j.jour) + " : " + j.visiteurs + " / " + j.visites) + '">' +
        '<span style="height:' + Math.round((Number(j.visiteurs) || 0) / max * 100) + '%"></span></div>').join("") + "</div>" +
      '<div class="vi-barres-pied"><span>' + e(court(jours[0].jour)) + "</span><span>le plus haut : " + e(String(max)) +
        "</span><span>" + e(court(jours[jours.length - 1].jour)) + "</span></div>";
  }
  const htmlClassement = (lignes, sous) => lignes.map((l, i) =>
    '<div class="sd-ligne"><div class="sd-ligne-haut"><strong>' + (i + 1) + ". " + e(l.nom) + "</strong><span>" +
      e(Utils.fmtNombre(l.vues)) + (l.vues > 1 ? " vues" : " vue") + "</span></div>" +
      (sous && l.boutique ? '<div class="aide">' + e(l.boutique) + "</div>" : "") + "</div>").join("");

  async function afficher(vue) {
    UI.entete({ titre: "Visiteurs", sous: "Qui passe dans la boutique", retour: true });
    if (!Supabase.estSuper()) {
      vue.innerHTML = UI.vide("equipe", "Réservé au superadministrateur",
        "Seul le superadministrateur lit les statistiques des visiteurs.");
      return;
    }
    vue.innerHTML =
      '<div class="carte"><div class="st-filtres" id="vi-periodes">' +
        PERIODES.map((p) => '<button type="button" class="puce' + (p.cle === periode ? " active" : "") +
          '" data-periode="' + p.cle + '">' + e(p.nom) + "</button>").join("") +
      "</div></div>" +
      '<div id="vi-corps"><div class="chargement"><span class="chargement-rond"></span>Lecture des visites…</div></div>';
    for (const b of UI.$$("#vi-periodes [data-periode]", vue)) {
      b.onclick = () => { periode = b.dataset.periode; afficher(vue); };
    }
    const corps = UI.$("#vi-corps", vue);
    const b = bornes();
    let s;
    try {
      s = await Store.statistiquesVisiteurs(b);
    } catch (err) {
      corps.innerHTML = '<div class="carte"><p class="aide" style="margin:0">' + e(err.message) +
        " — la base est-elle à jour (supabase/visiteurs.sql) ?</p></div>";
      return;
    }
    if (!corps.isConnected) return;
    const t = s.total || {};
    const visites = Number(t.visites) || 0;
    if (!visites) {
      corps.innerHTML = '<div class="carte" id="vi-vide"><div class="carte-titre">Aucune visite sur cette période</div>' +
        '<p class="aide" style="margin:0">Le comptage commence le jour où la boutique passe à la version 4.6.0 : ' +
        "rien n'existe pour les jours d'avant. Les visites se comptent sans nom ni numéro.</p></div>";
      return;
    }
    const jours = joursComplets(s.jours || [], b);
    const pf = s.plateformes || {};
    const NOMS_PF = { web: "Le site", android: "L'application Android", ios: "L'application iPhone" };
    corps.innerHTML =
      '<div class="carte" id="vi-totaux">' +
        '<div class="vi-tuiles">' +
          tuile(Utils.fmtNombre(t.visiteurs), "visiteurs") +
          tuile(Utils.fmtNombre(visites), "visites") +
          tuile(duree(t.duree_moyenne_s), "temps moyen par visite") +
          tuile(String(t.ecrans_moyens || 0).replace(".", ","), "écrans par visite") +
        "</div>" +
        '<p class="aide" style="margin:10px 0 0">' + e(Utils.fmtNombre(t.nouveaux)) +
          (t.nouveaux > 1 ? " nouveaux visiteurs" : " nouveau visiteur") + " sur la période. Un visiteur est un appareil : le même client sur " +
          "son téléphone et sur son ordinateur compte deux fois.</p>" +
      "</div>" +
      '<div class="carte" id="vi-jours"><div class="carte-titre">Visiteurs par jour</div>' + htmlBarres(jours) + "</div>" +
      '<div class="carte" id="vi-parcours"><div class="carte-titre">Jusqu\'où ils vont</div>' +
        '<div class="sd-ligne" style="border-top:0"><div class="sd-ligne-haut"><strong>Visites</strong><span>' + e(Utils.fmtNombre(visites)) + "</span></div></div>" +
        '<div class="sd-ligne"><div class="sd-ligne-haut"><strong>… avec un article mis au panier</strong><span>' +
          e(Utils.fmtNombre(t.panier)) + " · " + e(pc(part(t.panier, visites))) + "</span></div></div>" +
        '<div class="sd-ligne"><div class="sd-ligne-haut"><strong>… avec une commande payée</strong><span>' +
          e(Utils.fmtNombre(t.commande)) + " · " + e(pc(part(t.commande, visites))) + "</span></div></div>" +
      "</div>" +
      '<div class="carte" id="vi-plateformes"><div class="carte-titre">D\'où ils viennent</div>' +
        Object.keys(NOMS_PF).filter((k) => pf[k]).map((k, i) =>
          '<div class="sd-ligne"' + (i ? "" : ' style="border-top:0"') + '><div class="sd-ligne-haut"><strong>' + e(NOMS_PF[k]) +
            "</strong><span>" + e(Utils.fmtNombre(pf[k])) + " · " + e(pc(part(pf[k], visites))) + "</span></div></div>").join("") +
      "</div>" +
      '<div class="carte" id="vi-produits"><div class="carte-titre">Les produits les plus consultés</div>' +
        ((s.produits || []).length ? htmlClassement(s.produits, true)
          : '<p class="aide" style="margin:0">Aucune fiche de produit ouverte sur la période.</p>') + "</div>" +
      '<div class="carte" id="vi-boutiques"><div class="carte-titre">Les boutiques les plus consultées</div>' +
        ((s.boutiques || []).length ? htmlClassement(s.boutiques, false)
          : '<p class="aide" style="margin:0">Aucune page de boutique ouverte sur la période.</p>') + "</div>";
  }

  return { afficher };
})();
