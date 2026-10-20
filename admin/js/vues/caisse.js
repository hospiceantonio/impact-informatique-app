/* =========================================================
   La caisse des livreurs — le reste payé à la livraison (3.59.0)

   Le client paie l'acompte en ligne, et le reste au livreur. En
   remettant le colis, le livreur déclare ce qu'il a encaissé
   (« remettre_course »). Cet écran le rassemble, livreur par
   livreur :

     À RENDRE      ce qu'il a encaissé et n'a pas encore remis à la
                   boutique. « Argent reçu du livreur » le marque, et
                   le livreur en est prévenu ;
     CONTESTÉS     le client dit ne pas avoir payé ce qui est déclaré ;
     SANS DÉCLARATION
                   un colis remis depuis une application d'avant, alors
                   qu'un reste était dû : à vérifier avec le livreur ;
     RENDU         les 60 derniers jours.

   QUI LA VOIT. L'administrateur d'une boutique : l'argent de SES
   colis, quel que soit le livreur — un livreur de BIZZOO compris, en
   livraison groupée. BIZZOO (le superadministrateur, un compte de
   l'enseigne qui suit les commandes ou les finances) : tout. Un
   modérateur, non : c'est de l'argent. La base en décide
   (« tient_la_caisse ») ; l'écran ne fait que montrer.
   ========================================================= */
const VueCaisse = (() => {
  const e = Utils.echapper;
  const MODES = { especes: "espèces", mobile_money: "Mobile Money", aucun: "rien encaissé" };
  const m = (n, devise) => Utils.fmtMontant(Number(n) || 0, devise || "FCFA");

  function htmlLigne(l, avecBoutique) {
    const ecart = l.declare && l.montant !== l.du;
    return (
      '<div class="cs-ligne">' +
        "<div>" +
          "<strong>" + e(l.numero || l.commandeId) + "</strong>" +
          (avecBoutique ? " · " + e(l.nomBoutique) : "") +
          "<small>" + e(Utils.fmtDateHeure(l.encaisseLe)) +
            (l.declare && MODES[l.mode] ? " · " + e(MODES[l.mode]) : "") + "</small>" +
          (ecart
            ? '<small class="cs-ecart">Dû : ' + e(m(l.du, l.devise)) + " — « " + e(l.motif) + " »</small>"
            : "") +
          (l.contesteLe
            ? '<small class="cs-conteste">Contesté par le client : « ' + e(l.contesteMotif) + " »</small>"
            : "") +
          (l.remisLe
            ? "<small>Rendu le " + e(Utils.fmtDateHeure(l.remisLe)) +
                (l.remisPar ? " — reçu par " + e(l.remisPar) : "") + "</small>"
            : "") +
        "</div>" +
        "<strong>" + e(l.declare ? m(l.montant, l.devise) : m(l.du, l.devise)) + "</strong>" +
      "</div>"
    );
  }

  function parLivreur(lignes) {
    const groupes = new Map();
    for (const l of lignes) {
      const cle = l.livreurId || "?";
      if (!groupes.has(cle)) groupes.set(cle, { nom: l.livreurNom, tel: l.livreurTel, lignes: [] });
      groupes.get(cle).lignes.push(l);
    }
    return [...groupes.values()];
  }

  async function afficher(vue) {
    UI.entete({ titre: "Caisse des livreurs", sous: "Le reste payé à la livraison", retour: true });
    if (!Supabase.tientLaCaisse()) {
      vue.innerHTML = UI.vide("promo", "Réservé à l'administrateur",
        "La caisse des livreurs est tenue par l'administrateur de la boutique et par BIZZOO.");
      return;
    }
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Lecture de la caisse…</div>';

    let lignes;
    try {
      lignes = await Store.caisseLivreurs();
    } catch (err) {
      vue.innerHTML = '<div class="carte"><div class="carte-titre">Caisse indisponible</div>' +
        '<p class="aide" style="margin:0">' + e(err.message) +
        "<br>Si elle vient d'être mise en place, exécutez le fichier supabase/reste-livraison.sql.</p></div>";
      return;
    }
    if (!lignes.length) {
      vue.innerHTML = UI.vide("promo", "Rien dans la caisse",
        "Quand un livreur remet un colis et encaisse le reste, cela apparaît ici, " +
        "jusqu'à ce qu'il vous rende l'argent.");
      return;
    }
    const boutiques = new Set(lignes.map((l) => l.boutiqueId));
    const avecBoutique = boutiques.size > 1;

    const aRendre = lignes.filter((l) => l.declare && l.montant > 0 && !l.remisLe);
    const contestes = lignes.filter((l) => l.contesteLe);
    const sansDeclaration = lignes.filter((l) => !l.declare);
    const rendus = lignes.filter((l) => l.declare && l.remisLe);
    const totalARendre = aRendre.reduce((t, l) => t + l.montant, 0);
    const devise = (lignes[0] || {}).devise;

    vue.innerHTML =
      '<div class="titre-section" id="cs-a-rendre">À rendre par les livreurs : ' + e(m(totalARendre, devise)) + "</div>" +
      (aRendre.length
        ? parLivreur(aRendre).map((g) => {
            const total = g.lignes.reduce((t, l) => t + l.montant, 0);
            return (
              '<div class="carte cs-livreur">' +
                '<div class="cs-tete">' +
                  "<div><strong>" + e(g.nom || "Livreur") + "</strong>" +
                    (g.tel ? '<div><a href="tel:' + e(g.tel) + '">' + e(g.tel) + "</a></div>" : "") +
                  "</div>" +
                  '<div class="cs-total">' + e(m(total, devise)) + "</div>" +
                "</div>" +
                g.lignes.map((l) => htmlLigne(l, avecBoutique)).join("") +
                '<button type="button" class="btn cs-rendre" data-ids="' +
                  e(g.lignes.map((l) => l.id).join(",")) + '" data-total="' + e(m(total, devise)) +
                  '" data-nom="' + e(g.nom || "ce livreur") + '">' +
                  UI.icone("check") + "Argent reçu du livreur</button>" +
              "</div>"
            );
          }).join("")
        : '<div class="carte"><p class="aide" style="margin:0">Aucun livreur ne vous doit d\'argent.</p></div>') +

      (contestes.length
        ? '<div class="titre-section" id="cs-contestes">Contestés par le client (' + contestes.length + ")</div>" +
          '<div class="carte">' + contestes.map((l) =>
            htmlLigne(l, avecBoutique).replace("<strong>" + e(l.numero || l.commandeId) + "</strong>",
              "<strong>" + e(l.numero || l.commandeId) + "</strong> · " + e(l.livreurNom))).join("") + "</div>"
        : "") +

      (sansDeclaration.length
        ? '<div class="titre-section" id="cs-sans-declaration">Remis sans déclaration (' + sansDeclaration.length + ")</div>" +
          '<div class="carte"><p class="aide" style="margin:0 0 6px">Ces colis ont été remis depuis une ' +
            "ancienne version de l'application : le livreur n'a pas dit ce qu'il a encaissé. " +
            "Vérifiez avec lui.</p>" +
            sansDeclaration.map((l) =>
              htmlLigne(l, avecBoutique).replace("<strong>" + e(l.numero || l.commandeId) + "</strong>",
                "<strong>" + e(l.numero || l.commandeId) + "</strong> · " + e(l.livreurNom))).join("") +
          "</div>"
        : "") +

      (rendus.length
        ? '<details class="carte" id="cs-rendus"><summary class="carte-titre">Déjà rendu (' + rendus.length +
            ", 60 derniers jours)</summary>" +
            rendus.map((l) => htmlLigne(l, avecBoutique).replace(
              "<strong>" + e(l.numero || l.commandeId) + "</strong>",
              "<strong>" + e(l.numero || l.commandeId) + "</strong> · " + e(l.livreurNom))).join("") +
          "</details>"
        : "");

    for (const b of UI.$$(".cs-rendre", vue)) {
      b.onclick = async () => {
        const ok = await UI.confirmer({
          titre: "Argent reçu du livreur",
          texte: b.dataset.nom + " vous a remis " + b.dataset.total + " ? Il en sera prévenu.",
          bouton: "Oui, je l'ai reçu" });
        if (!ok) return;
        b.disabled = true;
        try {
          const ids = b.dataset.ids.split(",").map(Number).filter((n) => n > 0);
          await Store.marquerRemis(ids);
          UI.toast("C'est noté : " + b.dataset.total + " reçus de " + b.dataset.nom + ".");
          afficher(vue);
        } catch (err) {
          UI.toast(err.message, "err");
          b.disabled = false;
        }
      };
    }
  }

  return { afficher };
})();
