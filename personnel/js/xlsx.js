/* =========================================================
   Xlsx — fabrique un vrai classeur Excel (.xlsx), dans le
   navigateur, sans bibliothèque.

   Un .xlsx est une archive zip de quelques fichiers XML. On
   les écrit, on les range dans une archive « stockée » (sans
   compression : c'est permis, et c'est trois fois moins de
   code), et on propose le fichier au téléchargement.

   Ce que le classeur porte : plusieurs feuilles, une ligne de
   titres en gras et figée, le filtre automatique, des largeurs
   de colonnes, et des nombres QUI RESTENT DES NOMBRES (montants
   au format « 1 000 FCFA ») : on peut les additionner et les
   trier dans Excel.

   Usage :
     Xlsx.telecharger("bizzoo.xlsx", [
       { nom: "Feuille", colonnes: [{ titre, largeur, type }], lignes: [[…], …] } ]);
   type : "texte" (défaut), "nombre", "fcfa", "heures".
   ========================================================= */
const Xlsx = (() => {

  const echapper = (t) => String(t)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
    // Les caractères de contrôle sont interdits en XML : Excel refuserait le fichier.
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "");

  function colonne(n) {
    let s = "";
    for (n += 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + ((n - 1) % 26)) + s;
    return s;
  }

  /* Styles : 0 normal · 1 titre · 2 nombre · 3 FCFA · 4 heures (1 décimale) */
  const STYLE = { texte: 0, nombre: 2, fcfa: 3, heures: 4 };
  const STYLES = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="2"><numFmt numFmtId="164" formatCode="#,##0&quot; FCFA&quot;"/><numFmt numFmtId="165" formatCode="0.0&quot; h&quot;"/></numFmts>
<fonts count="2"><font><sz val="10"/><name val="Arial"/></font><font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF091A51"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="5">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="top"/></xf>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="top"/></xf>
<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="top"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>`;

  function feuilleXml(f) {
    const cols = f.colonnes;
    const ligneXml = (valeurs, r, titre) => {
      const cellules = valeurs.map((v, i) => {
        const ref = colonne(i) + r;
        if (titre) return `<c r="${ref}" s="1" t="inlineStr"><is><t xml:space="preserve">${echapper(v)}</t></is></c>`;
        if (v === null || v === undefined || v === "") return "";
        const type = (cols[i] && cols[i].type) || "texte";
        if (type !== "texte" && typeof v === "number" && Number.isFinite(v)) {
          return `<c r="${ref}" s="${STYLE[type]}"><v>${v}</v></c>`;
        }
        return `<c r="${ref}" s="0" t="inlineStr"><is><t xml:space="preserve">${echapper(v)}</t></is></c>`;
      }).join("");
      return `<row r="${r}"${titre ? ' ht="30" customHeight="1"' : ""}>${cellules}</row>`;
    };
    const derniere = colonne(Math.max(0, cols.length - 1)) + (f.lignes.length + 1);
    return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
<sheetFormatPr defaultRowHeight="15"/>
<cols>${cols.map((c, i) => `<col min="${i + 1}" max="${i + 1}" width="${c.largeur || 16}" customWidth="1"/>`).join("")}</cols>
<sheetData>${ligneXml(cols.map((c) => c.titre), 1, true)}${f.lignes.map((l, i) => ligneXml(l, i + 2, false)).join("")}</sheetData>
${f.lignes.length ? `<autoFilter ref="A1:${derniere}"/>` : ""}
</worksheet>`;
  }

  /** Le nom d'une feuille : 31 caractères, sans []:*?/\ */
  const nomFeuille = (n) => String(n).replace(/[\[\]:*?\/\\]/g, " ").slice(0, 31) || "Feuille";

  function fichiers(feuilles) {
    const f = {};
    f["[Content_Types].xml"] = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
${feuilles.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join("\n")}
</Types>`;
    f["_rels/.rels"] = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>`;
    f["xl/workbook.xml"] = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets>${feuilles.map((s, i) => `<sheet name="${echapper(nomFeuille(s.nom))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join("")}</sheets>
${feuilles.some((s) => s.lignes.length) ? `<definedNames>${feuilles.map((s, i) => s.lignes.length
  ? `<definedName name="_xlnm._FilterDatabase" localSheetId="${i}" hidden="1">'${echapper(nomFeuille(s.nom)).replace(/'/g, "''")}'!$A$1:$${colonne(s.colonnes.length - 1)}$${s.lignes.length + 1}</definedName>` : "").join("")}</definedNames>` : ""}
</workbook>`;
    f["xl/_rels/workbook.xml.rels"] = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
${feuilles.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join("\n")}
<Relationship Id="rId${feuilles.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>`;
    f["xl/styles.xml"] = STYLES;
    feuilles.forEach((s, i) => { f[`xl/worksheets/sheet${i + 1}.xml`] = feuilleXml(s); });
    return f;
  }

  /* ---------- L'archive zip, « stockée » ---------- */

  const TABLE_CRC = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();
  function crc32(octets) {
    let c = 0xFFFFFFFF;
    for (let i = 0; i < octets.length; i++) c = TABLE_CRC[(c ^ octets[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  }

  function zip(entrees) {
    const enc = new TextEncoder();
    const morceaux = [];
    const central = [];
    let decalage = 0;
    const maintenant = new Date();
    const heure = (maintenant.getHours() << 11) | (maintenant.getMinutes() << 5) | (maintenant.getSeconds() >> 1);
    const jour = ((maintenant.getFullYear() - 1980) << 9) | ((maintenant.getMonth() + 1) << 5) | maintenant.getDate();
    for (const [nom, contenu] of Object.entries(entrees)) {
      const n = enc.encode(nom);
      const donnees = enc.encode(contenu);
      const crc = crc32(donnees);
      const local = new DataView(new ArrayBuffer(30));
      local.setUint32(0, 0x04034b50, true);
      local.setUint16(4, 20, true);
      local.setUint16(6, 0x0800, true);          // noms en UTF-8
      local.setUint16(8, 0, true);               // stocké
      local.setUint16(10, heure, true);
      local.setUint16(12, jour, true);
      local.setUint32(14, crc, true);
      local.setUint32(18, donnees.length, true);
      local.setUint32(22, donnees.length, true);
      local.setUint16(26, n.length, true);
      local.setUint16(28, 0, true);
      morceaux.push(new Uint8Array(local.buffer), n, donnees);
      const c = new DataView(new ArrayBuffer(46));
      c.setUint32(0, 0x02014b50, true);
      c.setUint16(4, 20, true);
      c.setUint16(6, 20, true);
      c.setUint16(8, 0x0800, true);
      c.setUint16(10, 0, true);
      c.setUint16(12, heure, true);
      c.setUint16(14, jour, true);
      c.setUint32(16, crc, true);
      c.setUint32(20, donnees.length, true);
      c.setUint32(24, donnees.length, true);
      c.setUint16(28, n.length, true);
      c.setUint32(42, decalage, true);
      central.push(new Uint8Array(c.buffer), n);
      decalage += 30 + n.length + donnees.length;
    }
    const tailleCentral = central.reduce((s, x) => s + x.length, 0);
    const fin = new DataView(new ArrayBuffer(22));
    fin.setUint32(0, 0x06054b50, true);
    fin.setUint16(8, Object.keys(entrees).length, true);
    fin.setUint16(10, Object.keys(entrees).length, true);
    fin.setUint32(12, tailleCentral, true);
    fin.setUint32(16, decalage, true);
    return new Blob([...morceaux, ...central, new Uint8Array(fin.buffer)],
      { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
  }

  const classeur = (feuilles) => zip(fichiers(feuilles));

  function telecharger(nom, feuilles) {
    const url = URL.createObjectURL(classeur(feuilles));
    const a = document.createElement("a");
    a.href = url;
    a.download = nom;
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
  }

  return { classeur, telecharger, fichiers };
})();
