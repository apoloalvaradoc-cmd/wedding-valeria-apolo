/* ============================================================
   EXPORTAR A EXCEL

   Genera un .xlsx de verdad, no un CSV renombrado: Excel abre los CSV con
   avisos de formato y rompe las tildes, y eso no sirve para algo que se le
   entrega a la finca.

   Un .xlsx es un ZIP con varios XML dentro, así que aquí abajo hay un
   escritor de ZIP mínimo (sin compresión) y las piezas del libro. Sin
   librerías externas: la invitación es un solo archivo y no depende de
   ninguna CDN.
============================================================ */

/* ---------- ZIP (método "store", sin comprimir) ---------- */
const TABLA_CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(bytes) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) c = TABLA_CRC[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

function armarZip(archivos) {
  const enc = new TextEncoder();
  const partes = [], central = [];
  let offset = 0;

  const u16 = n => [n & 0xFF, (n >>> 8) & 0xFF];
  const u32 = n => [n & 0xFF, (n >>> 8) & 0xFF, (n >>> 16) & 0xFF, (n >>> 24) & 0xFF];

  for (const a of archivos) {
    const nombre = enc.encode(a.nombre);
    const datos = typeof a.datos === 'string' ? enc.encode(a.datos) : a.datos;
    const crc = crc32(datos);

    const cabecera = [
      ...u32(0x04034b50), ...u16(20), ...u16(0), ...u16(0),
      ...u16(0), ...u16(0),                       // hora y fecha: irrelevantes aquí
      ...u32(crc), ...u32(datos.length), ...u32(datos.length),
      ...u16(nombre.length), ...u16(0),
    ];
    partes.push(new Uint8Array(cabecera), nombre, datos);

    central.push(new Uint8Array([
      ...u32(0x02014b50), ...u16(20), ...u16(20), ...u16(0), ...u16(0),
      ...u16(0), ...u16(0),
      ...u32(crc), ...u32(datos.length), ...u32(datos.length),
      ...u16(nombre.length), ...u16(0), ...u16(0), ...u16(0), ...u16(0),
      ...u32(0), ...u32(offset),
    ]), nombre);

    offset += cabecera.length + nombre.length + datos.length;
  }

  const inicioCentral = offset;
  let largoCentral = 0;
  central.forEach(p => largoCentral += p.length);

  const fin = new Uint8Array([
    ...u32(0x06054b50), ...u16(0), ...u16(0),
    ...u16(archivos.length), ...u16(archivos.length),
    ...u32(largoCentral), ...u32(inicioCentral), ...u16(0),
  ]);

  return new Blob([...partes, ...central, fin], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  });
}

/* ---------- Estilos, con la paleta de la invitación ---------- */
const XLSX_ESTILOS = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="5">
<font><sz val="11"/><color rgb="FF2B1F22"/><name val="Calibri"/></font>
<font><b/><sz val="20"/><color rgb="FFF1F0EA"/><name val="Calibri"/></font>
<font><sz val="11"/><color rgb="FF580410"/><name val="Calibri"/></font>
<font><b/><sz val="11"/><color rgb="FFF1F0EA"/><name val="Calibri"/></font>
<font><sz val="9"/><color rgb="FF8A7A7D"/><name val="Calibri"/></font>
</fonts>
<fills count="6">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF580410"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFF1F0EA"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFFFFFFF"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFF7E4E6"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="2">
<border><left/><right/><top/><bottom/><diagonal/></border>
<border>
<left style="thin"><color rgb="FFD9A7AC"/></left>
<right style="thin"><color rgb="FFD9A7AC"/></right>
<top style="thin"><color rgb="FFD9A7AC"/></top>
<bottom style="thin"><color rgb="FFD9A7AC"/></bottom>
<diagonal/></border>
</borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="10">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
<xf numFmtId="0" fontId="2" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
<xf numFmtId="0" fontId="3" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
<xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
<xf numFmtId="0" fontId="2" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
<dxfs count="0"/>
<tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>
</styleSheet>`;

const xmlEsc = (s) => String(s ?? '')
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');

const letraColumna = (n) => {
  let s = '';
  while (n >= 0) { s = String.fromCharCode(65 + (n % 26)) + s; n = Math.floor(n / 26) - 1; }
  return s;
};

/* hoja = { nombre, titulo, subtitulo, columnas:[{titulo, ancho, centrado}], filas:[[...]], resaltar(fila, i) } */
function hojaXml(hoja) {
  const cols = hoja.columnas;
  const ultima = letraColumna(cols.length - 1);
  const celda = (ref, estilo, valor) => {
    if (valor === null || valor === undefined || valor === '') return `<c r="${ref}" s="${estilo}"/>`;
    if (typeof valor === 'number' && isFinite(valor)) return `<c r="${ref}" s="${estilo}"><v>${valor}</v></c>`;
    return `<c r="${ref}" s="${estilo}" t="inlineStr"><is><t xml:space="preserve">${xmlEsc(valor)}</t></is></c>`;
  };

  const filas = [];
  // 1 · título   2 · subtítulo   3 · encabezados   4+ · datos
  filas.push(`<row r="1" ht="34" customHeight="1">` +
    cols.map((_, i) => celda(letraColumna(i) + '1', 1, i === 0 ? hoja.titulo : '')).join('') + `</row>`);
  filas.push(`<row r="2" ht="20" customHeight="1">` +
    cols.map((_, i) => celda(letraColumna(i) + '2', 2, i === 0 ? hoja.subtitulo : '')).join('') + `</row>`);
  filas.push(`<row r="3" ht="26" customHeight="1">` +
    cols.map((c, i) => celda(letraColumna(i) + '3', 3, c.titulo)).join('') + `</row>`);

  hoja.filas.forEach((fila, n) => {
    const par = n % 2 === 1;
    const r = n + 4;
    filas.push(`<row r="${r}">` + cols.map((c, i) => {
      let estilo = c.centrado ? (par ? 7 : 6) : (par ? 5 : 4);
      if (hoja.resaltar && hoja.resaltar(fila, i)) estilo = 8;
      return celda(letraColumna(i) + r, estilo, fila[i]);
    }).join('') + `</row>`);
  });

  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetPr><tabColor rgb="FF580410"/></sheetPr>
<sheetViews><sheetView showGridLines="0" workbookViewId="0">
<pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/>
</sheetView></sheetViews>
<sheetFormatPr defaultRowHeight="15"/>
<cols>${cols.map((c, i) => `<col min="${i+1}" max="${i+1}" width="${c.ancho || 18}" customWidth="1"/>`).join('')}</cols>
<sheetData>${filas.join('')}</sheetData>
<autoFilter ref="A3:${ultima}3"/>
<mergeCells count="2"><mergeCell ref="A1:${ultima}1"/><mergeCell ref="A2:${ultima}2"/></mergeCells>
<pageMargins left="0.4" right="0.4" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>
</worksheet>`;
}

function descargarExcel(nombreArchivo, hoja) {
  const nombreHoja = xmlEsc((hoja.nombre || 'Hoja1').slice(0, 31));
  const archivos = [
    { nombre: '[Content_Types].xml', datos: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>` },
    { nombre: '_rels/.rels', datos: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>` },
    { nombre: 'xl/workbook.xml', datos: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="${nombreHoja}" sheetId="1" r:id="rId1"/></sheets>
</workbook>` },
    { nombre: 'xl/_rels/workbook.xml.rels', datos: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>` },
    { nombre: 'xl/styles.xml', datos: XLSX_ESTILOS },
    { nombre: 'xl/worksheets/sheet1.xml', datos: hojaXml(hoja) },
  ];

  const url = URL.createObjectURL(armarZip(archivos));
  const a = document.createElement('a');
  a.href = url; a.download = nombreArchivo; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
