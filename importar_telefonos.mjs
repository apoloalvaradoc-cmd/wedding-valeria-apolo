#!/usr/bin/env node
/**
 * Importa los celulares del Google Sheet a la tabla `invitados`.
 *
 * Los 131 invitados ya están cargados en Supabase — lo único que falta
 * son los teléfonos, que el parse_guests.mjs original leía pero nunca
 * insertaba (la tabla no tenía la columna).
 *
 * Este script NO usa la llave de servicio: escribe por el RPC
 * admin_set_telefono, que valida la clave de administración contra el
 * hash guardado en la base.
 *
 * Uso:
 *   1. Exporta el Sheet como CSV (Archivo → Descargar → .csv).
 *   2. Revisa qué haría, sin escribir nada:
 *        node importar_telefonos.mjs invitados.csv
 *   3. Si el reporte se ve bien, aplícalo:
 *        node importar_telefonos.mjs invitados.csv --aplicar
 *
 * La clave se pide por consola, o se toma de la variable de entorno
 * VA_CLAVE si prefieres no escribirla cada vez.
 */

import { readFileSync } from 'node:fs';
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';

const SUPABASE_URL = 'https://psmaynxnphbfbtayzaeb.supabase.co';
const SUPABASE_KEY = 'sb_publishable_vl2iawt4czQVfk53ACvxBg_TvkpUfI-';
const PAIS = '502'; // Guatemala

/* ---------------- CSV ---------------- */
function parseCSV(text) {
  const rows = [];
  let row = [], cell = '', inQ = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQ) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') inQ = false;
      else cell += c;
    } else {
      if (c === '"') inQ = true;
      else if (c === ',') { row.push(cell); cell = ''; }
      else if (c === '\n') { row.push(cell); rows.push(row); row = []; cell = ''; }
      else if (c === '\r') { /* ignora */ }
      else cell += c;
    }
  }
  if (cell.length || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

const norm = (s) => (s || '')
  .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  .toLowerCase().replace(/\s+/g, ' ').trim();

/* Busca la fila de encabezados: la primera que tenga algo parecido a
   "nombre" y algo parecido a "celular"/"teléfono". El Sheet original
   tenía una fila de título antes de los encabezados. */
function ubicarEncabezados(rows) {
  const esNombre = (h) => /^nombre/.test(norm(h));
  const esTel = (h) => /(celular|telefono|whatsapp|movil|tel)/.test(norm(h));
  for (let i = 0; i < Math.min(rows.length, 12); i++) {
    const iNombre = rows[i].findIndex(esNombre);
    const iTel = rows[i].findIndex(esTel);
    if (iNombre >= 0 && iTel >= 0) return { fila: i, iNombre, iTel };
  }
  return null;
}

/* ---------------- Teléfono ---------------- */
function normalizarTel(raw) {
  if (!raw) return null;
  let d = String(raw).replace(/\D/g, '');
  if (!d) return null;
  if (d.startsWith('00')) d = d.slice(2);
  d = d.replace(/^0+/, '');
  if (d.length === 8) d = PAIS + d;              // 5555 5555 → +502
  if (d.length < 10 || d.length > 15) return null;
  return '+' + d;
}

/* ---------------- Supabase ---------------- */
async function rpc(fn, args) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_KEY,
      Authorization: 'Bearer ' + SUPABASE_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(args),
  });
  const t = await r.text();
  let d = null;
  try { d = t ? JSON.parse(t) : null; } catch { d = t; }
  if (!r.ok) throw new Error((d && d.message) || `RPC ${fn} → ${r.status}`);
  return d;
}

/* ---------------- Main ---------------- */
const archivo = process.argv[2];
const aplicar = process.argv.includes('--aplicar');

if (!archivo) {
  console.error('Uso: node importar_telefonos.mjs <archivo.csv> [--aplicar]');
  process.exitCode = 1;
}

// Solo abrimos readline si de verdad hay que preguntar: dejarlo abierto
// hace que Node aborte al salir en Windows.
let clave = process.env.VA_CLAVE;
if (!clave) {
  const rl = createInterface({ input: stdin, output: stdout });
  clave = await rl.question('Clave de administración: ');
  rl.close();
}

let invitados;
try {
  invitados = await rpc('admin_lista_envio', { p_clave: clave });
} catch (e) {
  console.error('\nNo se pudo leer la lista:', e.message);
  throw e;
}
console.log(`\nInvitados en la base: ${invitados.length}`);

const porNombre = new Map();
for (const g of invitados) {
  const k = norm(g.nombre);
  // Un nombre repetido es ambiguo: lo marcamos para no adivinar.
  if (porNombre.has(k)) porNombre.set(k, 'AMBIGUO');
  else porNombre.set(k, g);
}

const filas = parseCSV(readFileSync(archivo, 'utf8'));
const cab = ubicarEncabezados(filas);
if (!cab) {
  console.error('\nNo encontré columnas de nombre y celular en el CSV.');
  console.error('Encabezados de la primera fila:', filas[0]);
  throw new Error('CSV sin columnas reconocibles');
}
console.log(`Encabezados en la fila ${cab.fila + 1}: nombre=col ${cab.iNombre + 1}, celular=col ${cab.iTel + 1}\n`);

const aEscribir = [];
const sinMatch = [], telMalo = [], ambiguos = [], sinTel = [];

for (let i = cab.fila + 1; i < filas.length; i++) {
  const nombre = (filas[i][cab.iNombre] || '').trim();
  if (!nombre) continue;
  const telRaw = (filas[i][cab.iTel] || '').trim();
  const g = porNombre.get(norm(nombre));

  if (!g)              { sinMatch.push(nombre); continue; }
  if (g === 'AMBIGUO') { ambiguos.push(nombre); continue; }
  if (!telRaw)         { sinTel.push(nombre); continue; }

  const tel = normalizarTel(telRaw);
  if (!tel) { telMalo.push(`${nombre} → "${telRaw}"`); continue; }

  aEscribir.push({ id: g.id, nombre: g.nombre, tel });
}

const reporte = (titulo, arr) => {
  if (!arr.length) return;
  console.log(`\n${titulo} (${arr.length}):`);
  arr.slice(0, 25).forEach(x => console.log('   · ' + x));
  if (arr.length > 25) console.log(`   ... y ${arr.length - 25} más`);
};

console.log(`Listos para escribir: ${aEscribir.length}`);
reporte('En el CSV pero no en la base (revisa la escritura)', sinMatch);
reporte('Nombre repetido en la base, no puedo decidir', ambiguos);
reporte('Teléfono no interpretable', telMalo);
reporte('Sin teléfono en el CSV', sinTel);

const enBaseSinCSV = invitados.filter(g => !aEscribir.some(x => x.id === g.id)).map(g => g.nombre);
reporte('En la base pero sin teléfono nuevo', enBaseSinCSV);

if (aplicar) {
  console.log('\nEscribiendo...');
  let ok = 0, fallos = 0;
  for (const x of aEscribir) {
    try {
      await rpc('admin_set_telefono', { p_clave: clave, p_invitado_id: x.id, p_telefono: x.tel });
      ok++;
      if (ok % 20 === 0) console.log(`   ${ok}/${aEscribir.length}`);
    } catch (e) {
      fallos++;
      console.error(`   falló ${x.nombre}: ${e.message}`);
    }
  }
  console.log(`\nListo: ${ok} teléfonos guardados${fallos ? `, ${fallos} fallaron` : ''}.`);
} else {
  console.log('\n─────────────────────────────────────────────');
  console.log('Simulación. Nada se escribió.');
  console.log('Si el reporte se ve bien, repite con --aplicar');
}
