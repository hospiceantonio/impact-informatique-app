/* =========================================================
   Journal des versements — ce qui est entré, et ce qui a raté.

   La commande ne garde que son état ACTUEL : payée, ou non.
   Ce journal garde le CHEMIN — une ligne par tentative, jamais
   modifiée ensuite. C'est lui, et lui seul, qui peut répondre
   à « combien d'échecs cette semaine » et « chez quel
   opérateur ».

   DEUX CHIFFRES, ET ILS NE SE MÉLANGENT PAS :

     ENTRÉ     ce qui a réellement été encaissé. Seules les
               lignes « payée » y entrent. Additionner les
               tentatives ferait un chiffre d'affaires
               imaginaire — c'est exactement l'erreur qu'un
               journal doit empêcher ;
     TENTATIVES tout le reste : demandes envoyées, versements
               incomplets, conflits. Cela se compte, cela ne
               s'additionne pas.

   RIEN NE S'Y MODIFIE, et la base le refuse à tout le monde,
   l'enseigne comprise. Un journal qu'on peut retoucher ne
   prouve rien le jour où il faudrait qu'il prouve quelque
   chose.
   ========================================================= */
const VueVersements = (() => {

  const PERIODES = [
    { cle: "7j", nom: "7 jours" },
    { cle: "30j", nom: "30 jours" },
    { cle: "mois", nom: "Ce mois" },
    { cle: "tout", nom: "Tout" },
  ];

  const FILTRES = [
    { cle: "", nom: "Tout" },
    { cle: "payee", nom: "Encaissés" },
    { cle: "incomplete", nom: "Incomplets" },
    { cle: "conflit", nom: "Conflits" },
    { cle: "inconnue", nom: "Sans commande" },
  ];

  const AGREGATEURS = {
    feexpay: "FeexPay",
    kkiapay: "KkiaPay",
    main: "À la main",
  };

  let periode = "30j";
  let verdict = "";

  const jourISO = (d) => d.toISOString().slice(0, 10);

  /** Les deux bornes envoyées à la base, ou null pour « depuis toujours ». */
  function bornes() {
    const aujourdhui = new Date();
    if (periode === "tout") return { depuis: null, jusqu: null };
    if (periode === "mois") {
      return {
        depuis: jourISO(new Date(aujourdhui.getFullYear(), aujourdhui.getMonth(), 1)),
        jusqu: jourISO(aujourdhui),
      };
    }
    const jours = periode === "7j" ? 6 : 29;
    const debut = new Date(aujourdhui);
    debut.setDate(debut.getDate() - jours);
    return { depuis: jourISO(debut), jusqu: jourISO(aujourdhui) };
  }

  const nomAgregateur = (cle) => AGREGATEURS[cle] || (cle ? cle : "—");

  function htmlLigne(v, devise) {
    const etat = Store.VERDICTS[v.verdict] || Store.VERDICTS.inconnue;
    /* Lequel des deux montants décrit CETTE ligne — voir « montre » dans
       le store. Un versement arrivé pour une commande introuvable n'a
       pas d'attendu : afficher celui-ci donnerait « 0 FCFA » sur la
       ligne qui mérite le plus qu'on la regarde. */
    const montant = etat.montre === "recu" ? v.recu : v.attendu;
    return (
      '<div class="carte vs-ligne">' +
        '<div class="vs-haut">' +
          "<div>" +
            "<strong>" + Utils.echapper(v.numero || "sans commande") + "</strong>" +
            '<div class="aide">' + Utils.echapper(Utils.fmtDateHeure(v.creeLe)) + "</div>" +
          "</div>" +
          '<span class="badge ' + etat.classe + '">' + Utils.echapper(etat.mot) + "</span>" +
        "</div>" +
        '<div class="vs-milieu">' +
          '<span class="vs-canal">' + Utils.echapper(nomAgregateur(v.fournisseur)) +
            (v.reseau ? " · " + Utils.echapper(v.reseau) : "") + "</span>" +
          "<strong>" + Utils.echapper(Utils.fmtMontant(montant, devise)) + "</strong>" +
        "</div>" +
        /* Un versement incomplet : les deux montants côte à côte, sinon
           on lit « 12 000 » et on croit la commande réglée. */
        (v.verdict === "incomplete"
          ? '<div class="vs-manque">' + UI.icone("alerte", "ic-sm") +
              "<span>Reçu " + Utils.echapper(Utils.fmtMontant(v.recu, devise)) +
              " sur " + Utils.echapper(Utils.fmtMontant(v.attendu, devise)) +
              " attendus</span></div>"
          : "") +
        (v.detail && v.verdict !== "incomplete"
          ? '<div class="aide" style="margin:8px 0 0">' +
            Utils.echapper(v.detail) + "</div>"
          : "") +
        (v.transactionId
          ? '<div class="vs-ref">Transaction ' + Utils.echapper(v.transactionId) + "</div>"
          : "") +
      "</div>"
    );
  }

  /** Ce qui est entré, et ce qui a raté, sur la période. */
  function htmlResume(resume, devise) {
    const entre = resume.filter((r) => r.verdict === "payee");
    const total = entre.reduce((s, r) => s + r.total, 0);
    const encaisses = entre.reduce((s, r) => s + r.combien, 0);
    /* « Ouverte » n'est pas un échec : c'est une demande partie dont on
       n'a pas encore la réponse. La compter comme telle ferait paniquer
       pour rien un jour de forte affluence. */
    const rates = resume
      .filter((r) => r.verdict !== "payee" && r.verdict !== "ouverte")
      .reduce((s, r) => s + r.combien, 0);
    const demandes = resume
      .filter((r) => r.verdict === "ouverte")
      .reduce((s, r) => s + r.combien, 0);

    /* Par opérateur, et seulement ce qui est ENTRÉ : c'est la question
       qu'on se pose — « lequel me rapporte, lequel me pose problème ». */
    const canaux = new Map();
    for (const r of resume) {
      const cle = nomAgregateur(r.fournisseur) + (r.reseau ? " · " + r.reseau : "");
      if (!canaux.has(cle)) canaux.set(cle, { entre: 0, rates: 0 });
      const c = canaux.get(cle);
      if (r.verdict === "payee") c.entre += r.total;
      else if (r.verdict !== "ouverte") c.rates += r.combien;
    }
    const lignes = [...canaux.entries()].sort((a, b) => b[1].entre - a[1].entre);

    return (
      '<div class="carte carte-publier st-resume">' +
        '<div class="st-resume-grand">' +
          "<small>Entré sur la période</small>" +
          "<strong>" + Utils.echapper(Utils.fmtMontant(total, devise)) + "</strong>" +
        "</div>" +
        '<div class="st-resume-detail">' +
          "<div><small>Encaissements</small><span>" + encaisses + "</span></div>" +
          "<div><small>Échecs</small><span>" + rates + "</span></div>" +
          "<div><small>En attente</small><span>" + demandes + "</span></div>" +
        "</div>" +
      "</div>" +
      (lignes.length
        ? '<div class="titre-section">Par opérateur</div>' +
          lignes.map(([nom, c]) =>
            '<div class="carte vs-canal-ligne">' +
              "<div><strong>" + Utils.echapper(nom) + "</strong>" +
                (c.rates
                  ? '<div class="aide">' + c.rates + " échec" +
                    (c.rates > 1 ? "s" : "") + "</div>"
                  : '<div class="aide">aucun échec</div>') +
              "</div>" +
              '<div class="vs-canal-total">' +
                Utils.echapper(Utils.fmtMontant(c.entre, devise)) + "</div>" +
            "</div>").join("")
        : "")
    );
  }

  async function afficher(vue) {
    const devise = Store.lireReglages().devise;

    UI.entete({ titre: "Journal des versements",
      sous: "Ce qui est entré, et ce qui a raté", retour: true });

    vue.innerHTML =
      '<div class="carte">' +
        '<div class="st-filtres" id="vs-periodes">' +
          PERIODES.map((p) =>
            '<button type="button" class="puce' + (p.cle === periode ? " active" : "") +
              '" data-periode="' + p.cle + '">' + Utils.echapper(p.nom) + "</button>").join("") +
        "</div>" +
        '<div class="st-filtres" id="vs-verdicts" style="margin-top:10px">' +
          FILTRES.map((f) =>
            '<button type="button" class="puce' + (f.cle === verdict ? " active" : "") +
              '" data-verdict="' + f.cle + '">' + Utils.echapper(f.nom) + "</button>").join("") +
        "</div>" +
      "</div>" +
      '<div id="vs-corps"><div class="chargement"><span class="chargement-rond"></span>' +
        "Lecture du journal…</div></div>";

    for (const bouton of UI.$$("#vs-periodes [data-periode]", vue)) {
      bouton.onclick = () => { periode = bouton.dataset.periode; afficher(vue); };
    }
    for (const bouton of UI.$$("#vs-verdicts [data-verdict]", vue)) {
      bouton.onclick = () => { verdict = bouton.dataset.verdict; afficher(vue); };
    }

    const corps = UI.$("#vs-corps", vue);
    let lignes, resume;
    try {
      /* Le résumé ne suit PAS le filtre de verdict : « entré sur la
         période » doit rester vrai quand on regarde les seuls échecs. */
      [lignes, resume] = await Promise.all([
        Store.journalVersements({ ...bornes(), verdict }),
        Store.resumeVersements(bornes()),
      ]);
    } catch (err) {
      corps.innerHTML =
        '<div class="carte"><div class="carte-titre">Journal indisponible</div>' +
        '<p class="aide" style="margin:0">' + Utils.echapper(err.message) +
        "<br>Si le journal vient d'être mis en place, exécutez le fichier " +
        "supabase/journal-versements.sql.</p></div>";
      return;
    }

    if (!resume.length) {
      corps.innerHTML = UI.vide("energie", "Rien sur cette période",
        "Le journal ne remonte pas le passé : il commence le jour où il a été " +
        "posé. Chaque paiement tenté y écrira désormais une ligne.");
      return;
    }

    corps.innerHTML =
      htmlResume(resume, devise) +
      '<div class="titre-section">' +
        (lignes.length
          ? lignes.length + " ligne" + (lignes.length > 1 ? "s" : "") +
            (lignes.length >= 300 ? " (les 300 plus récentes)" : "")
          : "Aucune ligne") +
      "</div>" +
      (lignes.length
        ? lignes.map((v) => htmlLigne(v, devise)).join("")
        : '<div class="carte"><p class="aide" style="margin:0">Aucun versement de ' +
          "ce type sur la période. Le résumé ci-dessus, lui, compte tout.</p></div>");
  }

  return { afficher };
})();
