#!/usr/bin/env node
/**
 * Convierte el Google Sheet de invitados en el SQL que reconstruye la
 * tabla `invitados`. Imprime el SQL en stdout — no toca la base.
 *
 * Uso:
 *   # bajar el Sheet como CSV
 *   curl -sL "https://docs.google.com/spreadsheets/d/<ID>/export?format=csv" -o invitados.csv
 *
 *   # revisar qué saldría
 *   node generar_lista_sql.mjs invitados.csv --reporte
 *
 *   # generar el SQL
 *   node generar_lista_sql.mjs invitados.csv > lista.sql
 *
 * Después se pega `lista.sql` en el SQL Editor de Supabase.
 *
 * OJO: el SQL borra y recrea la tabla `invitados`, lo que regenera todos
 * los tokens. Solo es seguro mientras no se haya enviado ninguna
 * invitación. Si ya circularon links, no lo corras.
 */

import { readFileSync } from 'node:fs';

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

/* ---------------- Acompañantes ---------------- */
/* El Sheet mezcla nombres reales con marcadores genéricos. "No" significa
   que va solo; "Acompañante", "Sra." o "Hijos" significan que tiene cupo
   pero todavía no sabemos el nombre — esos van como espacio en blanco
   para que el invitado lo llene en el RSVP. */
const SIN_NOMBRE = new Set([
  'no', 'no ', '-', '--', 'n/a', 'na', 'ninguno', 'ninguna', 'nadie',
  'acompanante', 'acompanantes', 'sra', 'sra.', 'sr', 'sr.', 'senora', 'senor',
  'hijo', 'hija', 'hijos', 'hijas', 'esposo', 'esposa', 'novio', 'novia',
  'pareja', 'familia', 'invitado', 'invitados', 'x',
  'amigo', 'amiga', 'amigos', 'amigas',
]);

function partirAcompanantes(celda) {
  if (!celda) return [];
  const limpio = celda.replace(/^amigos\s*-\s*/i, '').trim();
  if (!limpio) return [];
  if (SIN_NOMBRE.has(norm(limpio).replace(/\.$/, ''))) return [];
  return limpio
    .split(/\s*,\s*|\s+y\s+|\s*&\s*/i)
    .map(x => x.replace(/\s+/g, ' ').trim())
    .filter(x => x && !SIN_NOMBRE.has(norm(x).replace(/\.$/, '')));
}

/* ---------------- Teléfono ---------------- */
function normalizarTel(raw) {
  if (!raw) return null;
  const limpio = String(raw).trim();
  // Correos y guiones sueltos aparecen en la columna de celular.
  if (/@/.test(limpio)) return null;
  let d = limpio.replace(/\D/g, '');
  if (!d) return null;
  if (d.startsWith('00')) d = d.slice(2);
  d = d.replace(/^0+/, '');
  if (d.length === 8) d = PAIS + d;
  if (d.length < 10 || d.length > 15) return null;
  return '+' + d;
}

/* ---------------- Tipo ---------------- */
function tipoDe(relacion) {
  const r = norm(relacion);
  if (!r) return 'otro';
  if (r.includes('familia')) return 'familia';
  if (r.includes('damita') || r.includes('caballero')) return 'cortejo';
  if (r.includes('amigos mama')) return 'amigos_mama';
  if (r.includes('amigos papa')) return 'amigos_papa';
  if (r.includes('amigo')) return 'amigo';
  return 'otro';
}

/* ---------------- Main ---------------- */
const archivo = process.argv[2];
const soloReporte = process.argv.includes('--reporte');
if (!archivo) {
  console.error('Uso: node generar_lista_sql.mjs <archivo.csv> [--reporte]');
  process.exitCode = 1;
}

const filas = parseCSV(readFileSync(archivo, 'utf8'));

// Encabezados: primera fila que tenga "Nombre".
let iCab = filas.findIndex(f => f.some(c => /^nombre$/i.test((c || '').trim())));
if (iCab < 0) throw new Error('No encontré la fila de encabezados');
const cab = filas[iCab].map(c => norm(c));
const col = (re) => cab.findIndex(c => re.test(c));

const C = {
  nombre:   col(/^nombre$/),
  acomp:    col(/^acompanante$/),
  relacion: col(/^relacion$/),
  tel:      col(/^numero celular$/),
  telAlt:   col(/^celular acompanante$/),
  cupos:    col(/asistentes/),
};
if (Object.values(C).some(i => i < 0)) {
  throw new Error('Faltan columnas. Encontradas: ' + JSON.stringify(cab));
}

const invitados = [];
const avisos = { sinTel: [], telMalo: [], sinCupos: [], cuposAjustados: [], omitidos: [] };
let n = 0;

for (let i = iCab + 1; i < filas.length; i++) {
  const f = filas[i];
  const nombre = (f[C.nombre] || '').replace(/\s+/g, ' ').trim();
  if (!nombre) continue;

  // Bloque colectivo sin persona concreta — no es una invitación.
  if (/^invitados\s+pap/i.test(nombre)) { avisos.omitidos.push(`${nombre} (bloque colectivo)`); continue; }

  const acompanantes = partirAcompanantes(f[C.acomp]);
  const relacion = (f[C.relacion] || '').trim();

  let cupos = parseInt(f[C.cupos], 10);
  if (!cupos || cupos < 1) {
    cupos = 1 + acompanantes.length;
    avisos.sinCupos.push(`${nombre} → ${cupos}`);
  }
  // Nunca menos cupos que nombres ya listados.
  if (cupos < 1 + acompanantes.length) {
    avisos.cuposAjustados.push(`${nombre}: ${cupos} → ${1 + acompanantes.length}`);
    cupos = 1 + acompanantes.length;
  }

  const telRaw = (f[C.tel] || '').trim();
  const tel = normalizarTel(telRaw);
  if (!telRaw) avisos.sinTel.push(nombre);
  else if (!tel) avisos.telMalo.push(`${nombre} → "${telRaw}"`);

  const telAlt = normalizarTel(f[C.telAlt]);

  n++;
  invitados.push({
    id: 'INV' + String(n).padStart(3, '0'),
    codigo: 'VA' + String(n).padStart(3, '0'),
    nombre,
    acompanantes,
    cupos,
    grupo: relacion || null,
    tipo: tipoDe(relacion),
    telefono: tel,
    telefono_alt: telAlt,
    nombre_acompanante: acompanantes[0] || null,
  });
}

/* ---------------- Reporte ---------------- */
const rep = (t, a) => {
  if (!a.length) return;
  console.error(`\n${t} (${a.length}):`);
  a.slice(0, 30).forEach(x => console.error('   · ' + x));
  if (a.length > 30) console.error(`   ... y ${a.length - 30} más`);
};

console.error(`Invitaciones: ${invitados.length}`);
console.error(`Cupos totales: ${invitados.reduce((a, g) => a + g.cupos, 0)}`);
console.error(`Con teléfono del titular: ${invitados.filter(g => g.telefono).length}`);
console.error(`Con teléfono de acompañante: ${invitados.filter(g => g.telefono_alt).length}`);
console.error(`Sin ningún teléfono: ${invitados.filter(g => !g.telefono && !g.telefono_alt).length}`);
const porTipo = {};
invitados.forEach(g => porTipo[g.tipo] = (porTipo[g.tipo] || 0) + 1);
console.error('Por tipo: ' + JSON.stringify(porTipo));
rep('Omitidos', avisos.omitidos);
rep('Sin teléfono en el Sheet', avisos.sinTel);
rep('Teléfono no interpretable', avisos.telMalo);
rep('Sin cupos en el Sheet (deducidos)', avisos.sinCupos);
rep('Cupos subidos para que quepan los nombres listados', avisos.cuposAjustados);

const dup = {};
invitados.forEach(g => { const k = norm(g.nombre); dup[k] = (dup[k] || 0) + 1; });
rep('Nombres repetidos (el buscador mostrará ambos)',
    Object.entries(dup).filter(([, v]) => v > 1).map(([k, v]) => `${k} ×${v}`));

if (soloReporte) process.exitCode = 0;

/* ---------------- SQL ---------------- */
if (!soloReporte) {
  const q = (s) => s == null ? 'null' : `'${String(s).replace(/'/g, "''")}'`;
  const arr = (a) => a.length ? `ARRAY[${a.map(q).join(',')}]::text[]` : `'{}'::text[]`;

  const out = [];
  out.push('-- Lista de invitados reconstruida desde el Google Sheet');
  out.push(`-- ${invitados.length} invitaciones · ${invitados.reduce((a, g) => a + g.cupos, 0)} cupos`);
  out.push('-- OJO: regenera todos los tokens. No correr si ya se enviaron links.');
  out.push('');
  out.push('begin;');
  out.push('');
  out.push('delete from public.aperturas;');
  out.push('delete from public.envios;');
  out.push('delete from public.rsvps;');
  out.push('delete from public.invitados;');
  out.push('');
  out.push('insert into public.invitados');
  out.push('  (id, nombre, acompanantes, cupos, grupo, tipo, codigo, telefono, telefono_alt, nombre_acompanante)');
  out.push('values');
  out.push(invitados.map(g =>
    `(${q(g.id)},${q(g.nombre)},${arr(g.acompanantes)},${g.cupos},${q(g.grupo)},` +
    `${q(g.tipo)},${q(g.codigo)},${q(g.telefono)},${q(g.telefono_alt)},${q(g.nombre_acompanante)})`
  ).join(',\n') + ';');
  out.push('');
  out.push('-- Token nuevo para cada quien: es lo que hace único su link.');
  out.push('update public.invitados set token = substr(md5(id || gen_random_uuid()::text), 1, 12);');
  out.push('');
  out.push('commit;');
  console.log(out.join('\n'));
}
