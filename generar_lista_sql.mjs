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
 *   # ACTUALIZAR — lo normal una vez que ya salieron invitaciones.
 *   # Conserva el token (y por lo tanto el link) de quien ya existe,
 *   # agrega los nuevos y solo escribe los campos que cambiaron.
 *   VA_CLAVE='...' node generar_lista_sql.mjs invitados.csv --actualizar > update.sql
 *
 *   # RECONSTRUIR desde cero — solo antes de mandar nada.
 *   node generar_lista_sql.mjs invitados.csv > lista.sql
 *
 * El SQL se pega en el SQL Editor de Supabase.
 *
 * OJO: sin --actualizar el SQL borra y recrea la tabla `invitados`, lo que
 * regenera todos los tokens e invalida los links ya enviados.
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
const actualizar  = process.argv.includes('--actualizar');
if (!archivo) {
  console.error('Uso: node generar_lista_sql.mjs <archivo.csv> [--reporte|--actualizar]');
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

/* ============================================================
   MODO ACTUALIZAR  ·  node generar_lista_sql.mjs lista.csv --actualizar

   Una vez que empezaron a salir invitaciones ya no se puede rehacer la
   tabla desde cero: eso regenera los tokens e invalida los links que la
   gente ya recibió. Este modo compara el Sheet contra lo que hay en la
   base y emite:
     · UPDATE para quien ya existe — refresca datos, NO toca su token
     · INSERT para los nuevos, con id y token nuevos
     · un aviso de quién está en la base pero ya no en el Sheet
       (no se borra solo: puede ser un cambio de nombre, no una baja)

   Empareja por nombre normalizado. Necesita la clave en VA_CLAVE.
============================================================ */
if (actualizar) {
  const SUPABASE_URL = 'https://psmaynxnphbfbtayzaeb.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_vl2iawt4czQVfk53ACvxBg_TvkpUfI-';
  const clave = process.env.VA_CLAVE;
  if (!clave) throw new Error('Falta la variable de entorno VA_CLAVE');

  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/admin_lista_envio`, {
    method: 'POST',
    headers: { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_clave: clave }),
  });
  if (!r.ok) throw new Error('No pude leer la base: ' + (await r.text()));
  const enBase = await r.json();

  /* Emparejar por nombre a secas falla en dos casos reales:
       · le agregan un tratamiento ("Virgilio Casado" → "Sr. Virgilio Casado")
       · dos personas distintas se ven iguales sin tildes
         (Mario Calderon y Mario Calderón son primos, no un duplicado)
     Por eso se empareja primero por teléfono, que sí es único, y lo que
     quede se empareja por nombre sin tratamiento, consumiendo candidatos
     de uno en uno para no colapsar los homónimos. */
  const TRATAMIENTOS = /^(sr|sra|srta|don|dona|dr|dra|lic|licda|ing|arq|padre)\.?\s+/i;
  const claveNombre = (s) => norm(s).replace(TRATAMIENTOS, '').trim();
  const soloDigitos = (t) => (t || '').replace(/\D/g, '');

  const porTel = new Map();
  const porNombreLista = new Map();
  enBase.forEach(g => {
    [g.telefono, g.telefono_alt].forEach(t => {
      const d = soloDigitos(t);
      if (d) porTel.set(d, g);
    });
    const k = claveNombre(g.nombre);
    if (!porNombreLista.has(k)) porNombreLista.set(k, []);
    porNombreLista.get(k).push(g);
  });

  const usados = new Set();
  const buscarEnBase = (g) => {
    const d = soloDigitos(g.telefono);
    const porNumero = d && porTel.get(d);
    if (porNumero && !usados.has(porNumero.id)) { usados.add(porNumero.id); return porNumero; }
    const cand = (porNombreLista.get(claveNombre(g.nombre)) || []).find(x => !usados.has(x.id));
    if (cand) { usados.add(cand.id); return cand; }
    return null;
  };

  // Los ids nuevos siguen después del mayor que ya exista.
  let maxN = 0;
  enBase.forEach(g => { const m = /^INV(\d+)$/.exec(g.id); if (m) maxN = Math.max(maxN, +m[1]); });

  const q = (s) => s == null ? 'null' : `'${String(s).replace(/'/g, "''")}'`;
  const arr = (a) => a.length ? `ARRAY[${a.map(q).join(',')}]::text[]` : `'{}'::text[]`;

  const updates = [], inserts = [];
  const vistos = new Set();
  let nActualizados = 0;

  for (const g of invitados) {
    const ya = buscarEnBase(g);
    if (ya) {
      vistos.add(ya.id);
      // Solo se escribe lo que de verdad cambió: así el SQL queda corto y
      // se ve de un vistazo qué se está tocando.
      const sets = [];
      const mismosNombres = (a, b) =>
        (a || []).length === (b || []).length && (a || []).every((x, k) => x === (b || [])[k]);

      if (g.nombre !== ya.nombre) sets.push(`nombre=${q(g.nombre)}`);
      if (!mismosNombres(g.acompanantes, ya.acompanantes)) sets.push(`acompanantes=${arr(g.acompanantes)}`);
      if (g.cupos !== ya.cupos) sets.push(`cupos=${g.cupos}`);
      if ((g.grupo || null) !== (ya.grupo || null)) sets.push(`grupo=${q(g.grupo)}`);
      if ((g.tipo || null) !== (ya.tipo || null)) sets.push(`tipo=${q(g.tipo)}`);
      // Un teléfono vacío en el Sheet no borra el que ya esté en la base:
      // pudo haberse corregido a mano desde la consola.
      if (g.telefono && g.telefono !== ya.telefono) sets.push(`telefono=${q(g.telefono)}`);
      if (g.telefono_alt && g.telefono_alt !== ya.telefono_alt) sets.push(`telefono_alt=${q(g.telefono_alt)}`);
      if (g.nombre_acompanante && g.nombre_acompanante !== ya.nombre_acompanante)
        sets.push(`nombre_acompanante=${q(g.nombre_acompanante)}`);

      if (sets.length) {
        nActualizados++;
        updates.push(`update public.invitados set ${sets.join(', ')} where id=${q(ya.id)};  -- ${g.nombre}`);
      }
    } else {
      const id = 'INV' + String(++maxN).padStart(3, '0');
      inserts.push(
        `(${q(id)},${q(g.nombre)},${arr(g.acompanantes)},${g.cupos},${q(g.grupo)},` +
        `${q(g.tipo)},${q('VA' + String(maxN).padStart(3, '0'))},${q(g.telefono)},${q(g.telefono_alt)},${q(g.nombre_acompanante)},` +
        `substr(md5(${q(id)} || gen_random_uuid()::text), 1, 12))`);
    }
  }

  const huerfanos = enBase.filter(g => !vistos.has(g.id));
  console.error(`\n── MODO ACTUALIZAR ──`);
  console.error(`En la base: ${enBase.length} · en el Sheet: ${invitados.length}`);
  console.error(`Emparejados: ${vistos.size} (conservan su token y su link)`);
console.error(`Con cambios:  ${nActualizados}`);
  console.error(`Se agregan:    ${inserts.length}`);
  rep('En la base pero ya no en el Sheet — se dejan intactos, revísalos a mano', huerfanos.map(g => g.nombre));

  const out = [];
  out.push('-- Actualización incremental desde el Google Sheet.');
  out.push(`-- ${nActualizados} actualizados (token intacto) · ${inserts.length} nuevos.`);
  out.push('-- No borra nada: los links ya enviados siguen sirviendo.');
  out.push('');
  out.push('begin;');
  out.push('');
  if (updates.length) { out.push('-- Refresco de datos, sin tocar id ni token'); out.push(...updates); out.push(''); }
  if (inserts.length) {
    out.push('-- Invitados nuevos');
    out.push('insert into public.invitados');
    out.push('  (id, nombre, acompanantes, cupos, grupo, tipo, codigo, telefono, telefono_alt, nombre_acompanante, token)');
    out.push('values');
    out.push(inserts.join(',\n') + ';');
    out.push('');
  }
  out.push('commit;');
  console.log(out.join('\n'));
}

/* ---------------- SQL (reconstrucción completa) ---------------- */
if (!soloReporte && !actualizar) {
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
