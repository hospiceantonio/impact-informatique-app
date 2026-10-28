/* =========================================================
   Localiser un livreur — la carte, en grand.

   #/livreurs          : tous les livreurs ;
   #/livreurs/<id>     : la carte centrée sur ce livreur (le bouton
                         « Voir sa position » du suivi des commandes).

   La position vient du téléphone du livreur pendant ses courses
   (BIZZOO Admin, même application fermée). Pour chaque course en
   cours, le point du client quand il l'a donné, et la distance qui
   les sépare : à vol d'oiseau, multipliée par le coefficient de
   route de la livraison au kilomètre — d'où « environ ». C'est la
   base (rh_localiser_livreurs) qui décide qui voit cette carte.
   Un livreur en route sans position depuis le seuil du suivi est
   « muet » : en orange, avec un bouton pour l'appeler.

   Leaflet est embarqué (vendor/leaflet) ; seules les tuiles viennent
   d'OpenStreetMap. La carte se relit toutes les 10 secondes.
   ========================================================= */
const VueLocaliser = (() => {
  const { h } = UI;
  const CENTRE = [6.3654, 2.4183];        // Cotonou
  const RELIRE = 10000;
  const ANCIENNE = 5 * 60 * 1000;         // au-delà, la position « date »
  const ETATS = { nouvelle: "Commande à récupérer", vue: "Commande à récupérer", preparee: "Colis prêt à récupérer",
    en_livraison: "En route vers le client" };

  let chargement = null;
  function chargerLeaflet() {
    if (window.L && window.L.map) return Promise.resolve(window.L);
    if (chargement) return chargement;
    chargement = new Promise((ok, ko) => {
      if (!document.querySelector("link[data-leaflet]")) {
        document.head.append(h("link", { rel: "stylesheet", href: "vendor/leaflet/leaflet.css", "data-leaflet": "" }));
      }
      const script = h("script", { src: "vendor/leaflet/leaflet.js" });
      script.onload = () => ok(window.L);
      script.onerror = () => { chargement = null; ko(new Error("La carte n'a pas pu se charger.")); };
      document.head.append(script);
    });
    return chargement;
  }

  /** Pour le HTML des épingles et des bulles de Leaflet. */
  const echapper = (t) => String(t ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" })[c]);
  const initiales = (nom) => String(nom || "?").split(/\s+/).filter(Boolean).slice(0, 2).map((m) => m[0].toUpperCase()).join("");
  const ilYa = (iso) => {
    if (!iso) return "jamais";
    const s = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
    if (s < 60) return "il y a " + s + " s";
    if (s < 3600) return "il y a " + Math.round(s / 60) + " min";
    if (s < 86400) return "il y a " + Math.round(s / 3600) + " h";
    return "le " + UI.dateHeure(iso);
  };
  const km = (d) => (d === null || d === undefined ? null : "environ " + String(d).replace(".", ",") + " km");
  const ancienne = (p) => !p || Date.now() - new Date(p.le).getTime() > ANCIENNE;

  async function afficher(zone, morceaux) {
    UI.vider(zone, UI.chargement());
    const choisi = morceaux[0] || null;
    let L;
    try {
      L = await chargerLeaflet();
    } catch (err) {
      return UI.vider(zone, UI.erreur(err));
    }
    if (!zone.isConnected) return;
    zone.classList.add("vue-carte");

    const cadre = h("div", { class: "localiser" });
    const fond = h("div", { class: "localiser-carte" });
    const liste = h("div", { class: "localiser-liste" });
    const seulsEnCourse = h("input", { type: "checkbox", checked: !choisi });
    const pleinEcran = h("button", { class: "btn btn-petit btn-second", type: "button" }, "Plein écran");
    const etat = h("p", { class: "tres-petit doux" });
    cadre.append(fond, h("div", { class: "localiser-panneau" },
      h("div", { class: "ligne" }, h("label", { class: "case etire" }, seulsEnCourse, "En course seulement"), pleinEcran),
      etat, liste));
    UI.vider(zone, cadre);

    const carte = L.map(fond, { zoomControl: true }).setView(CENTRE, 12);
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19, attribution: "© les contributeurs d'OpenStreetMap",
    }).addTo(carte);
    const calque = L.layerGroup().addTo(carte);

    pleinEcran.addEventListener("click", () => {
      if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
      else if (cadre.requestFullscreen) cadre.requestFullscreen().catch(() => UI.echec("Le plein écran n'est pas permis ici."));
    });
    const auChangement = () => {
      pleinEcran.textContent = document.fullscreenElement ? "Quitter le plein écran" : "Plein écran";
      setTimeout(() => carte.invalidateSize(), 150);
    };
    document.addEventListener("fullscreenchange", auChangement);

    let selection = choisi;
    let premiereFois = true;
    let donnees = null;

    const dessiner = () => {
      if (!donnees) return;
      calque.clearLayers();
      const visibles = donnees.livreurs.filter((l) => l.id === selection || !seulsEnCourse.checked || l.en_course);
      const points = [];
      for (const l of visibles) {
        const p = l.position;
        const actif = l.id === selection;
        if (p) {
          const icone = L.divIcon({ className: "", iconSize: [34, 34], iconAnchor: [17, 17],
            html: '<div class="pin-livreur' + (l.en_course ? " en-course" : "") + (ancienne(p) ? " ancien" : "") + (l.muet ? " muet" : "") +
                  (actif ? " choisi" : "") + '">' + echapper(initiales(l.nom)) + "</div>" });
          L.marker([p.latitude, p.longitude], { icon: icone, zIndexOffset: actif ? 1000 : 0 })
            .addTo(calque).bindPopup(() => fiche(l)).on("click", () => { selection = l.id; dessinerListe(); });
          if (actif || !selection) points.push([p.latitude, p.longitude]);
        }
        for (const c of l.courses) {
          if (!c.destination) continue;
          const d = [c.destination.latitude, c.destination.longitude];
          L.marker(d, { icon: L.divIcon({ className: "", iconSize: [22, 22], iconAnchor: [11, 11], html: '<div class="pin-client"></div>' }) })
            .addTo(calque).bindPopup("<b>" + echapper(c.numero || "") + "</b><br>" + echapper(c.client || "") + "<br>" + echapper(c.adresse || ""));
          if (p) {
            L.polyline([[p.latitude, p.longitude], d], { color: actif ? "#C2410C" : "#2F55D4", weight: actif ? 4 : 2, dashArray: "6 6", opacity: 0.8 })
              .addTo(calque);
          }
          if (actif || !selection) points.push(d);
        }
      }
      if (premiereFois && points.length) {
        carte.fitBounds(points, { padding: [40, 40], maxZoom: 16 });
        premiereFois = false;
      }
      dessinerListe();
    };

    function fiche(l) {
      const p = l.position;
      const div = h("div", { class: "petit" },
        h("div", { class: "gras" }, l.nom),
        h("div", { class: "doux" }, [l.vehicule === "tricycle" ? "Tricycle" : "Moto", l.boutique || "Livreur BIZZOO"].join(" · ")),
        l.tel ? h("div", {}, h("a", { href: "tel:" + l.tel }, l.tel)) : null,
        l.muet ? h("div", { style: { color: "var(--orange-fonce)", fontWeight: "600" } }, "En route, sans position depuis plus de " + donnees.seuil_muet_min + " min") : null,
        h("div", { class: "doux" }, "Position " + (p ? ilYa(p.le) : "inconnue")),
        l.courses.map((c) => h("div", { style: { marginTop: "6px" } },
          h("a", { href: "#/suivi/commande/" + encodeURIComponent(c.commande) }, c.numero), " · ", c.client || "",
          h("div", { class: "doux" }, ETATS[c.etat] || c.etat),
          h("div", {}, c.destination ? (km(c.distance_km) ? km(c.distance_km) + " du client" : "Distance inconnue")
            : "Point du client inconnu : " + (c.adresse || "—")))));
      return div;
    }

    function dessinerListe() {
      if (!donnees) return;
      const tous = donnees.livreurs;
      const visibles = tous.filter((l) => l.id === selection || !seulsEnCourse.checked || l.en_course);
      etat.textContent = tous.filter((l) => l.en_course).length + " livreur(s) en course sur " + tous.length +
        " · relu " + new Date().toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
      UI.vider(liste, visibles.length ? visibles.map((l) => {
        const p = l.position;
        const course = l.courses[0];
        const vieux = l.en_course && ancienne(p);
        /* LE LIVREUR MUET : en route vers un client, et son téléphone ne
           dit plus rien depuis le seuil du suivi. On l'appelle. */
        const appel = l.muet && l.tel ? h("a", { class: "btn btn-orange btn-petit", href: "tel:" + l.tel, style: { margin: "0 0 8px 40px" } },
          "Appeler " + l.nom) : null;
        return [h("button", { type: "button", class: "localiser-element" + (l.id === selection ? " actif" : ""),
          onclick: () => {
            selection = l.id === selection ? null : l.id;
            dessiner();
            if (selection && p) carte.setView([p.latitude, p.longitude], Math.max(carte.getZoom(), 15));
          } },
          h("div", { class: "pin-livreur petit-pin" + (l.en_course ? " en-course" : "") + (vieux ? " ancien" : "") + (l.muet ? " muet" : "") }, initiales(l.nom)),
          h("div", { class: "etire" },
            h("div", { class: "gras" }, l.nom),
            h("div", { class: "tres-petit doux" }, p ? "Position " + ilYa(p.le) : "Aucune position"),
            course ? h("div", { class: "tres-petit" }, course.numero + " · " + (ETATS[course.etat] || course.etat) +
              (course.destination ? (km(course.distance_km) ? " · " + km(course.distance_km) + " du client" : "") : " · point du client inconnu")) : null,
            l.en_course && !l.suivi_actif ? h("div", { class: "tres-petit", style: { color: "var(--orange-fonce)" } },
              "Suivi pas encore démarré : le livreur doit ouvrir ses courses dans BIZZOO Admin.") : null,
            l.muet ? h("div", { class: "tres-petit gras", style: { color: "var(--orange-fonce)" } },
              "Livreur muet : en route, sans position depuis plus de " + donnees.seuil_muet_min + " min. Appelez-le.") : null,
            vieux && l.suivi_actif && !l.muet ? h("div", { class: "tres-petit", style: { color: "var(--orange-fonce)" } },
              "Pas de nouvelle position depuis plus de 5 min (réseau, GPS ou téléphone éteint).") : null)), appel];
      }) : UI.vide(seulsEnCourse.checked ? "Aucun livreur en course pour l'instant." : "Aucun livreur."));
    }

    seulsEnCourse.addEventListener("change", dessiner);

    async function relire() {
      try {
        donnees = await Supabase.rpc("rh_localiser_livreurs");
      } catch (err) {
        if (err && err.deconnecte) throw err;
        etat.textContent = "Relecture impossible : " + err.message;
        return;
      }
      if (!cadre.isConnected) return;
      if (selection && premiereFois) {
        const l = donnees.livreurs.find((x) => x.id === selection);
        if (l) App.titre("Position de " + l.nom);
        else UI.echec("Ce livreur n'est plus actif.");
      }
      dessiner();
    }

    await relire();
    setTimeout(() => carte.invalidateSize(), 100);
    const minuterie = setInterval(() => {
      if (!cadre.isConnected) {
        clearInterval(minuterie);
        document.removeEventListener("fullscreenchange", auChangement);
        return;
      }
      relire().catch(() => {});
    }, RELIRE);
  }

  return { titre: "Localiser un livreur", afficher };
})();
