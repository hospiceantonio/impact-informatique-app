/* =========================================================
   Faire livrer — une commande prise sur WhatsApp (3.68.0)

   Certains clients commandent et paient sur WhatsApp au lieu de valider
   leur panier. La commande se passait alors hors de l'application, et
   le point ne la voyait pas.

   Ici, le superadministrateur, ou un administrateur ou modérateur de
   BIZZOO à qui il a accordé le droit « Faire livrer » :
     1. choisit les produits que le client a commandés ;
     2. touche « Faire livrer » ;
     3. donne le nom, le téléphone, l'adresse et la position du client,
        le montant payé et la référence de la transaction ;
     4. valide.

   LA BASE FAIT LE RESTE (« faire_livrer ») : prix, stock, frais de
   livraison, paiement au journal, boutiques prévenues, course proposée
   aux livreurs — comme pour toute commande. Le client a tout payé : le
   livreur ne prend rien chez lui. L'écran ne calcule rien lui-même : le
   total affiché vient de la base (« devis_faire_livrer »).
   ========================================================= */
const VueFaireLivrer = (() => {
  const e = (s) => Utils.echapper(s);
  const m = (n, d) => Utils.fmtMontant(n, d || "FCFA");

  /* Ce qui est en cours de saisie survit au passage d'une étape à l'autre
     — et à une sortie par erreur : on ne retape pas le panier. */
  const etat = {
    etape: "produits",
    panier: [],          // [{ produitId, quantite }]
    recherche: "",
    client: { nom: "", tel: "", adresse: "", note: "" },
    destination: null,
    paiement: { montant: "", reseau: "MTN", transaction: "" },
  };
  let produits = [];
  let auKm = false;
  let carte = null;

  const quantite = (id) => (etat.panier.find((a) => a.produitId === id) || {}).quantite || 0;
  const produit = (id) => produits.find((p) => p.id === id) || null;
  const nomBoutique = (id) => (Store.lireBoutique(id) || {}).nomBoutique || "";
  const nbArticles = () => etat.panier.reduce((s, a) => s + a.quantite, 0);
  const sousTotal = () => etat.panier.reduce((s, a) => s + ((produit(a.produitId) || {}).prix || 0) * a.quantite, 0);

  function changer(id, delta) {
    const a = etat.panier.find((x) => x.produitId === id);
    if (a) {
      a.quantite = Math.max(0, Math.min(99, a.quantite + delta));
      if (!a.quantite) etat.panier = etat.panier.filter((x) => x !== a);
    } else if (delta > 0) {
      etat.panier.push({ produitId: id, quantite: 1 });
    }
  }

  /* Les coordonnées cachées dans un lien de carte — Google Maps, OSM —
     ou tapées telles quelles : « 6.3702,2.4289 ». La même règle que
     l'application des clients. */
  function positionDuLien(texte) {
    const t = String(texte || "");
    const trouve = t.match(/(-?\d{1,3}\.\d{3,})[,\s/@]+(-?\d{1,3}\.\d{3,})/);
    if (!trouve) return null;
    const p = { latitude: Number(trouve[1]), longitude: Number(trouve[2]) };
    return Math.abs(p.latitude) <= 90 && Math.abs(p.longitude) <= 180 ? p : null;
  }

  async function afficher(vue) {
    UI.entete({ titre: "Faire livrer", sous: "Une commande prise sur WhatsApp", retour: true });
    if (!Supabase.peutFaireLivrer()) {
      vue.innerHTML = UI.vide("alerte", "Droit « Faire livrer » nécessaire",
        "« Faire livrer » est un droit que le superadministrateur accorde à un administrateur " +
        "ou un modérateur de BIZZOO. Demandez-le-lui si vous en avez besoin.");
      return;
    }
    vue.innerHTML = '<div class="chargement"><span class="chargement-rond"></span>Lecture du catalogue…</div>';
    try {
      const [liste, paiement] = await Promise.all([
        Store.listerProduits({ toutesBoutiques: true }),
        Store.lirePaiement().catch(() => ({})),
      ]);
      /* Un produit masqué ne se commande plus : la base le refuserait. */
      produits = (liste || []).filter((p) => !p.masque);
      const l = paiement && paiement.livraison;
      auKm = !!(l && l.latitude !== null && l.longitude !== null);
    } catch (err) {
      vue.innerHTML = '<div class="carte"><div class="carte-titre">Catalogue indisponible</div>' +
        '<p class="aide" style="margin:0">' + e(err.message) + "</p></div>";
      return;
    }
    if (etat.etape === "client" && etat.panier.length) afficherClient(vue);
    else afficherProduits(vue);
  }

  /* ---------- Étape 1 : les produits ---------- */

  function ligneProduit(p) {
    const q = quantite(p.id);
    const epuise = !p.surCommande && p.stock <= 0;
    return (
      '<div class="fl-produit' + (q ? " fl-choisi" : "") + '" data-id="' + e(p.id) + '">' +
        UI.vignetteProduit(p) +
        '<div class="fl-produit-texte"><strong>' + e(p.nom) + "</strong>" +
          '<span class="aide">' + e(nomBoutique(p.boutiqueId) || "—") + " · " + e(m(p.prix)) +
            (epuise ? " · épuisé" : p.surCommande ? " · sur commande" : " · stock " + e(String(p.stock))) +
          "</span></div>" +
        (q
          ? '<div class="fl-quantite"><button type="button" class="btn-ic fl-moins" aria-label="Retirer un">−</button>' +
              "<strong>" + q + "</strong>" +
              '<button type="button" class="btn-ic fl-plus" aria-label="Ajouter un">+</button></div>'
          : '<button type="button" class="btn btn-clair btn-petit fl-ajouter"' + (epuise ? " disabled" : "") + ">" +
              UI.icone("plus", "ic-sm") + "Ajouter</button>") +
      "</div>"
    );
  }

  function filtres() {
    const q = etat.recherche.trim().toLowerCase();
    const choisis = produits.filter((p) => quantite(p.id));
    const autres = produits.filter((p) => !quantite(p.id) && (!q ||
      (p.nom + " " + p.code + " " + p.reference + " " + nomBoutique(p.boutiqueId)).toLowerCase().includes(q)));
    return choisis.concat(autres.slice(0, 60));
  }

  function afficherProduits(vue) {
    etat.etape = "produits";
    vue.innerHTML =
      '<div class="carte fl-intro" id="fl-intro">' +
        '<div class="carte-titre">' + UI.icone("whatsapp", "ic-sm") + " Une commande prise sur WhatsApp</div>" +
        '<p class="aide" style="margin:0">Le client a commandé et payé sur WhatsApp ? Choisissez ses produits, ' +
          "puis « Faire livrer ». La commande entre dans BIZZOO comme toutes les autres — le point la verra — " +
          "et la course part aux livreurs. Le client a déjà payé : le livreur ne lui demande rien.</p>" +
      "</div>" +
      '<div class="champ"><input id="fl-recherche" type="search" autocomplete="off" ' +
        'placeholder="Chercher un produit, un code, une boutique" value="' + e(etat.recherche) + '"></div>' +
      '<div class="carte fl-liste" id="fl-liste"></div>' +
      '<div class="fl-barre" id="fl-barre"></div>';
    const liste = UI.$("#fl-liste", vue);
    const barre = UI.$("#fl-barre", vue);
    const peindre = () => {
      const lot = filtres();
      liste.innerHTML = lot.length ? lot.map(ligneProduit).join("")
        : '<p class="aide" style="margin:0">Aucun produit ne correspond.</p>';
      const n = nbArticles();
      barre.innerHTML = n
        ? '<div class="fl-barre-texte"><strong>' + n + " article" + (n > 1 ? "s" : "") + "</strong>" +
            '<span class="aide">' + e(m(sousTotal())) + " hors livraison</span></div>" +
          '<button type="button" class="btn" id="fl-suivant">' + UI.icone("voiture") + "Faire livrer</button>"
        : '<p class="aide" style="margin:0">Choisissez les produits que le client a commandés.</p>';
      const suivant = UI.$("#fl-suivant", barre);
      if (suivant) suivant.onclick = () => afficherClient(vue);
    };
    liste.onclick = (ev) => {
      const ligne = ev.target.closest(".fl-produit");
      if (!ligne) return;
      if (ev.target.closest(".fl-ajouter") || ev.target.closest(".fl-plus")) changer(ligne.dataset.id, 1);
      else if (ev.target.closest(".fl-moins")) changer(ligne.dataset.id, -1);
      else return;
      peindre();
    };
    UI.$("#fl-recherche", vue).oninput = (ev) => { etat.recherche = ev.target.value; peindre(); };
    peindre();
  }

  /* ---------- Étape 2 : le client, la position, le paiement ---------- */

  function afficherClient(vue) {
    etat.etape = "client";
    if (carte) { carte.detruire(); carte = null; }
    const c = etat.client;
    const pay = etat.paiement;
    vue.innerHTML =
      '<div class="carte" id="fl-recap">' +
        '<div class="carte-titre">' + UI.icone("boite", "ic-sm") + " Ce que le client a commandé</div>" +
        etat.panier.map((a) => {
          const p = produit(a.produitId) || { nom: a.produitId, prix: 0 };
          return '<div class="fl-recap-ligne"><span>' + a.quantite + " × " + e(p.nom) +
            ' <small class="aide">' + e(nomBoutique(p.boutiqueId)) + "</small></span>" +
            "<strong>" + e(m(p.prix * a.quantite)) + "</strong></div>";
        }).join("") +
        '<button type="button" class="btn btn-clair btn-petit" id="fl-modifier" style="margin-top:8px">' +
          UI.icone("crayon", "ic-sm") + "Modifier les produits</button>" +
      "</div>" +

      '<div class="carte" id="fl-client">' +
        '<div class="carte-titre">' + UI.icone("personne", "ic-sm") + " Le client</div>" +
        UI.champTexte({ id: "fl-nom", label: "Nom", valeur: c.nom, obligatoire: true }) +
        UI.champTexte({ id: "fl-tel", label: "Téléphone", valeur: c.tel, obligatoire: true, type: "tel",
          placeholder: "01 00 00 00 00",
          aide: "S'il a un compte BIZZOO à ce numéro, la commande apparaîtra dans son application." }) +
        UI.champTexte({ id: "fl-adresse", label: "Adresse de livraison", valeur: c.adresse, obligatoire: true,
          placeholder: "Quartier, rue, repère" }) +
        UI.champTexte({ id: "fl-note", label: "Note pour le livreur (facultatif)", valeur: c.note }) +
      "</div>" +

      (auKm
        ? '<div class="carte" id="fl-position">' +
            '<div class="carte-titre">' + UI.icone("carte", "ic-sm") + " Où livrer</div>" +
            '<p class="aide" style="margin:0 0 8px">Les frais se comptent selon la distance : la position du ' +
              "client est obligatoire. Collez le lien de localisation qu'il vous a envoyé sur WhatsApp, ou " +
              "touchez la carte.</p>" +
            UI.champTexte({ id: "fl-lien", label: "Lien de carte ou coordonnées",
              placeholder: "https://maps.google.com/… ou 6.3702, 2.4289" }) +
            '<button type="button" class="btn btn-clair btn-petit" id="fl-sur-carte">' + UI.icone("carte", "ic-sm") +
              "Choisir sur la carte</button>" +
            '<div class="km-carte" id="fl-carte" hidden></div>' +
            '<div class="aide" id="fl-position-etat" style="margin-top:8px"></div>' +
          "</div>"
        : "") +

      '<div class="carte" id="fl-devis"><p class="aide" style="margin:0">Calcul du total…</p></div>' +

      '<div class="carte" id="fl-paiement">' +
        '<div class="carte-titre">' + UI.icone("promo", "ic-sm") + " Ce que le client a payé</div>" +
        UI.champMontant({ id: "fl-montant", label: "Montant payé", obligatoire: true,
          valeur: Number(String(pay.montant || "").replace(/\D/g, "")) || "" }) +
        '<div class="champ"><label for="fl-reseau">Réseau</label>' +
          '<select id="fl-reseau">' +
            ["MTN", "MOOV", "CELTIIS"].map((r) => '<option value="' + r + '"' + (pay.reseau === r ? " selected" : "") + ">" +
              (r === "MOOV" ? "Moov" : r === "CELTIIS" ? "Celtiis" : r) + "</option>").join("") +
          "</select></div>" +
        UI.champTexte({ id: "fl-transaction", label: "Référence de la transaction", valeur: pay.transaction,
          obligatoire: true, placeholder: "Lue sur le reçu de paiement du client",
          aide: "Une référence ne sert qu'une fois : BIZZOO refuse un reçu déjà utilisé." }) +
        '<button type="button" class="btn" id="fl-valider" style="margin-top:6px">' + UI.icone("voiture") +
          "Valider et faire livrer</button>" +
        '<div id="fl-erreur"></div>' +
      "</div>";

    const garder = () => {
      etat.client = {
        nom: UI.$("#fl-nom", vue).value, tel: UI.$("#fl-tel", vue).value,
        adresse: UI.$("#fl-adresse", vue).value, note: UI.$("#fl-note", vue).value,
      };
      etat.paiement = {
        montant: UI.$("#fl-montant", vue).value, reseau: UI.$("#fl-reseau", vue).value,
        transaction: UI.$("#fl-transaction", vue).value,
      };
    };
    for (const champ of UI.$$("input, select", vue)) champ.addEventListener("change", garder);
    UI.$("#fl-modifier", vue).onclick = () => { garder(); afficherProduits(vue); };

    /* Le total, demandé à la base, à chaque changement de position. */
    let dernier = 0;
    let devis = null;
    const majDevis = async () => {
      const n = ++dernier;
      const zone = UI.$("#fl-devis", vue);
      try {
        const d = await Store.devisFaireLivrer(etat.panier, etat.destination);
        if (n !== dernier || !zone.isConnected) return;
        devis = d;
        const l = d.livraison;
        zone.innerHTML =
          '<div class="carte-titre">' + UI.icone("check", "ic-sm") + " Le total</div>" +
          '<div class="fl-recap-ligne"><span>Articles</span><strong>' + e(m(d.sousTotal, d.devise)) + "</strong></div>" +
          '<div class="fl-recap-ligne"><span>Livraison' +
            (l ? " " + (l.vehicule === "tricycle" ? "en tricycle" : "à moto") + " · " +
                 e(String(l.distance_km).replace(".", ",")) + " km" : "") + "</span><strong>" +
            (d.frais == null ? "selon la position" : e(m(d.frais, d.devise))) + "</strong></div>" +
          '<div class="fl-recap-ligne fl-total"><span>Total à avoir reçu</span><strong id="fl-total">' +
            (d.total == null ? "—" : e(m(d.total, d.devise))) + "</strong></div>" +
          (d.positionRequise
            ? '<p class="aide" style="margin:6px 0 0">Indiquez la position du client pour connaître les frais.</p>'
            : '<p class="aide" style="margin:6px 0 0">Calculé par BIZZOO, comme pour une commande passée dans ' +
              "l'application. Le client a tout payé : rien n'est à encaisser à la livraison.</p>");
        const montant = UI.$("#fl-montant", vue);
        if (d.total != null && montant && !String(etat.paiement.montant || "").trim()) {
          montant.value = Utils.fmtNombre(d.total);
        }
      } catch (err) {
        if (n === dernier && zone.isConnected) {
          zone.innerHTML = '<p class="aide" style="margin:0;color:var(--rouge)">' + e(err.message) + "</p>";
        }
      }
    };

    if (auKm) {
      const etatPos = UI.$("#fl-position-etat", vue);
      const dire = () => {
        etatPos.innerHTML = etat.destination
          ? UI.icone("check", "ic-sm") + " Position : " + e(etat.destination.latitude.toFixed(5)) + ", " +
            e(etat.destination.longitude.toFixed(5))
          : "Aucune position pour l'instant.";
      };
      const poser = (p, recentrer) => {
        etat.destination = { latitude: p.latitude, longitude: p.longitude };
        if (carte) carte.placer(etat.destination, recentrer);
        dire();
        majDevis();
      };
      const ouvrirCarte = async () => {
        const zone = UI.$("#fl-carte", vue);
        zone.hidden = false;
        if (carte) return;
        try {
          carte = await Carte.monter(zone, { position: etat.destination, deplace: (p) => poser(p, false) });
        } catch (_) {
          zone.innerHTML = '<p class="aide" style="padding:12px">La carte ne s\'affiche pas sans connexion : ' +
            "collez le lien de localisation du client.</p>";
        }
      };
      UI.$("#fl-sur-carte", vue).onclick = ouvrirCarte;
      UI.$("#fl-lien", vue).addEventListener("change", async (ev) => {
        const p = positionDuLien(ev.target.value);
        if (!p) { UI.toast("Ce lien ne contient pas de position", "err"); return; }
        await ouvrirCarte();
        poser(p, true);
        ev.target.value = "";
      });
      dire();
      if (etat.destination) ouvrirCarte();
    }
    majDevis();

    const bouton = UI.$("#fl-valider", vue);
    bouton.onclick = async () => {
      garder();
      const erreur = UI.$("#fl-erreur", vue);
      erreur.innerHTML = "";
      const montant = Number(String(etat.paiement.montant).replace(/\s|fcfa/gi, "")) || 0;
      const dit = (texte) => {
        erreur.innerHTML = '<p class="aide" style="color:var(--rouge);margin:10px 0 0">' + e(texte) + "</p>";
      };
      if (!etat.client.nom.trim() || !etat.client.tel.trim() || !etat.client.adresse.trim()) {
        dit("Le nom, le téléphone et l'adresse du client sont nécessaires.");
        return;
      }
      if (auKm && !etat.destination) { dit("Indiquez la position du client : collez son lien de carte, ou touchez la carte."); return; }
      if (!etat.paiement.transaction.trim()) { dit("Saisissez la référence de la transaction du client."); return; }
      if (!montant) { dit("Indiquez le montant que le client a payé."); return; }
      if (devis && devis.total != null && montant < devis.total) {
        dit("Le client a payé " + m(montant, devis.devise) + ", mais la commande coûte " +
          m(devis.total, devis.devise) + ". Vérifiez le montant ou les articles.");
        return;
      }
      const ok = await UI.confirmer({
        titre: "Faire livrer cette commande ?",
        texte: nbArticles() + " article" + (nbArticles() > 1 ? "s" : "") + " pour " + etat.client.nom.trim() +
          ", payés " + m(montant) + " (référence " + etat.paiement.transaction.trim() + "). " +
          "La commande sera enregistrée comme payée et la course partira aux livreurs.",
        bouton: "Faire livrer" });
      if (!ok) return;
      bouton.disabled = true;
      bouton.textContent = "Enregistrement…";
      try {
        const r = await Store.faireLivrer({
          panier: etat.panier, nom: etat.client.nom.trim(), tel: etat.client.tel.trim(),
          adresse: etat.client.adresse.trim(), note: etat.client.note.trim(),
          destination: etat.destination, transaction: etat.paiement.transaction.trim(),
          montant, reseau: etat.paiement.reseau,
        });
        UI.toast("Commande " + ((r && r.numero) || "") + " enregistrée : la course part aux livreurs" +
          (r && r.client_relie ? ", et le client la voit dans son application." : "."), "ok");
        /* La saisie suivante repart de zéro. */
        etat.panier = []; etat.recherche = ""; etat.destination = null; etat.etape = "produits";
        etat.client = { nom: "", tel: "", adresse: "", note: "" };
        etat.paiement = { montant: "", reseau: "MTN", transaction: "" };
        /* Ouvrir la commande, si ce compte voit les commandes ; sinon une
           nouvelle saisie. */
        if (Supabase.peutVoirCommandes()) location.hash = "#/commandes/" + encodeURIComponent((r && r.id) || "");
        else afficherProduits(vue);
      } catch (err) {
        dit(err.message);
        bouton.disabled = false;
        bouton.innerHTML = UI.icone("voiture") + "Valider et faire livrer";
      }
    };
  }

  return { afficher };
})();
