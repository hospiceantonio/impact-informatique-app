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

   MOMOPAY (3.59.0) : PLUS D'ESPÈCES. Le reste se paie désormais par
   MoMoPay, sur le compte de BIZZOO ; le livreur saisit le numéro de la
   transaction. Ces paiements sont « À VÉRIFIER » : BIZZOO les retrouve
   dans son compte MoMoPay et touche « Vérifié ». La boutique les voit,
   mais seul BIZZOO peut les vérifier — l'argent est chez lui. Le
   livreur, lui, n'a rien à rendre.

   QUI LA VOIT. L'administrateur d'une boutique : l'argent de SES
   colis, quel que soit le livreur — un livreur de BIZZOO compris, en
   livraison groupée. BIZZOO (le superadministrateur, un compte de
   l'enseigne qui suit les commandes ou les finances) : tout. Un
   modérateur, non : c'est de l'argent. La base en décide
   (« tient_la_caisse ») ; l'écran ne fait que montrer.
   ========================================================= */
const VueCaisse = (() => {
  const e = Utils.echapper;
  const MODES = { especes: "espèces", mobile_money: "MoMoPay", aucun: "rien encaissé" };
  /* Vérifier un paiement MoMoPay : BIZZOO seul, comme en base. */
  const verifieMomopay = () => Supabase.estSuper() ||
    (Supabase.estCompteEnseigne() && Supabase.tientLaCaisse());
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
          (l.mode === "mobile_money" && l.motif
            ? "<small>" + e(l.motif) + "</small>"
            : "") +
          (ecart
            ? '<small class="cs-ecart">Dû : ' + e(m(l.du, l.devise)) + " — « " + e(l.motif) + " »</small>"
            : "") +
          (l.contesteLe
            ? '<small class="cs-conteste">Contesté par le client : « ' + e(l.contesteMotif) + " »</small>"
            : "") +
          (l.remisLe
            ? "<small>" + (l.mode === "mobile_money" ? "Vérifié le " : "Rendu le ") +
                e(Utils.fmtDateHeure(l.remisLe)) +
                (l.remisPar ? (l.mode === "mobile_money" ? " par " : " — reçu par ") + e(l.remisPar) : "") +
                "</small>"
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
        "Quand un client paie le reste par MoMoPay à la livraison, le paiement apparaît ici, " +
        "jusqu'à ce que BIZZOO le retrouve dans son compte MoMoPay.");
      return;
    }
    const boutiques = new Set(lignes.map((l) => l.boutiqueId));
    const avecBoutique = boutiques.size > 1;

    const aRendre = lignes.filter((l) => l.declare && l.montant > 0 && !l.remisLe && l.mode !== "mobile_money");
    const aVerifier = lignes.filter((l) => l.declare && l.montant > 0 && !l.remisLe && l.mode === "mobile_money");
    const totalAVerifier = aVerifier.reduce((t, l) => t + l.montant, 0);
    const contestes = lignes.filter((l) => l.contesteLe);
    const sansDeclaration = lignes.filter((l) => !l.declare);
    const rendus = lignes.filter((l) => l.declare && l.remisLe);
    const totalARendre = aRendre.reduce((t, l) => t + l.montant, 0);
    const devise = (lignes[0] || {}).devise;

    vue.innerHTML =
      /* MOMOPAY À VÉRIFIER, en tête : c'est désormais le seul chemin du
         reste. */
      '<div class="titre-section" id="cs-a-verifier">MoMoPay à vérifier : ' + e(m(totalAVerifier, devise)) + "</div>" +
      (aVerifier.length
        ? '<div class="carte">' +
            '<p class="aide" style="margin:0 0 6px">Retrouvez chaque transaction dans le compte ' +
              "MoMoPay de BIZZOO" + (verifieMomopay() ? ", puis touchez « Vérifié »." : " : BIZZOO les vérifie.") +
              "</p>" +
            aVerifier.map((l) =>
              htmlLigne(l, avecBoutique).replace("<strong>" + e(l.numero || l.commandeId) + "</strong>",
                "<strong>" + e(l.numero || l.commandeId) + "</strong> · " + e(l.livreurNom)) +
              (verifieMomopay()
                ? '<button type="button" class="btn btn-clair cs-verifier" data-ids="' + e(String(l.id)) +
                    '" data-total="' + e(m(l.montant, l.devise)) + '" data-trans="' + e(l.motif) + '">' +
                    UI.icone("check") + "Vérifié sur le compte MoMoPay</button>"
                : "")).join("") +
          "</div>"
        : '<div class="carte"><p class="aide" style="margin:0">Aucun paiement MoMoPay à vérifier.</p></div>') +
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
        ? '<details class="carte" id="cs-rendus"><summary class="carte-titre">Déjà rendu ou vérifié (' + rendus.length +
            ", 60 derniers jours)</summary>" +
            rendus.map((l) => htmlLigne(l, avecBoutique).replace(
              "<strong>" + e(l.numero || l.commandeId) + "</strong>",
              "<strong>" + e(l.numero || l.commandeId) + "</strong> · " + e(l.livreurNom))).join("") +
          "</details>"
        : "");

    for (const b of UI.$$(".cs-verifier", vue)) {
      b.onclick = async () => {
        const ok = await UI.confirmer({
          titre: "Paiement MoMoPay vérifié",
          texte: "Vous avez retrouvé " + b.dataset.total + " dans le compte MoMoPay de BIZZOO (" +
            b.dataset.trans + ") ?",
          bouton: "Oui, il y est" });
        if (!ok) return;
        b.disabled = true;
        try {
          await Store.marquerRemis([Number(b.dataset.ids)]);
          UI.toast("Paiement vérifié.");
          afficher(vue);
        } catch (err) {
          UI.toast(err.message, "err");
          b.disabled = false;
        }
      };
    }

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
