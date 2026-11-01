#!/usr/bin/env node
/**
 * Carga el plano del salón (LayoutValeriaApolo.pdf) y la lista de las
 * mesas 1–7 que mandaron los novios el 1-nov-2026.
 *
 * Es de una sola vez: borra las mesas que haya, crea las 30 del plano con
 * su forma y su lugar, completa las confirmaciones que la lista da por
 * hechas y sienta a cada invitación. Lo que la lista trae y no sabemos a
 * qué invitación corresponde queda como lugar apartado, con el nombre tal
 * como venía, para resolverlo después desde mesas.html.
 *
 * Igual que importar_telefonos.mjs, no usa la llave de servicio: todo pasa
 * por los RPC de administración (requiere la migración 016).
 *
 * Uso:
 *   node cargar_mesas_plano.mjs            → solo muestra lo que haría
 *   node cargar_mesas_plano.mjs --aplicar  → lo hace
 *
 * La clave se toma de VA_CLAVE o se pide por consola.
 */

import { createInterface } from 'node:readline/promises';
import { stdin, stdout, env, argv } from 'node:process';

const SUPABASE_URL = 'https://elytdndedfxiqfqdnwzx.supabase.co';
const SUPABASE_KEY = 'sb_publishable_JyZovP1ejwyqf51pT_ArAg_kfOtBvAp';
const APLICAR = argv.includes('--aplicar');

// [número, forma, x, y] · posición en fracción del salón, medida sobre el PDF.
// Numeradas por filas, de la tarima hacia el fondo y de izquierda a derecha.
const PLANO = [
  [1, 'redonda', 0.1308, 0.2839], [2, 'redonda', 0.8709, 0.2839],
  [3, 'redonda', 0.2302, 0.3391], [4, 'rect_v', 0.3125, 0.3321],
  [5, 'rect_v', 0.6889, 0.3188],  [6, 'redonda', 0.7713, 0.3305],
  [7, 'rect_h', 0.1308, 0.3989],  [8, 'rect_h', 0.8706, 0.3856],
  [9, 'redonda', 0.2302, 0.4630], [10, 'rect_v', 0.3125, 0.4602],
  [11, 'rect_v', 0.6889, 0.4469], [12, 'redonda', 0.7713, 0.4544],
  [13, 'redonda', 0.1038, 0.5138], [14, 'redonda', 0.8706, 0.4975],
  [15, 'rect_v', 0.1782, 0.5884], [16, 'redonda', 0.2655, 0.5906],
  [17, 'rect_h', 0.3695, 0.5866], [18, 'rect_h', 0.6341, 0.5866],
  [19, 'redonda', 0.7257, 0.5866], [20, 'rect_v', 0.8130, 0.5884],
  [21, 'rect_h', 0.0921, 0.6293], [22, 'redonda', 0.9060, 0.6180],
  [23, 'redonda', 0.1745, 0.7110], [24, 'rect_h', 0.2655, 0.7110],
  [25, 'redonda', 0.3695, 0.7070], [26, 'redonda', 0.6341, 0.7070],
  [27, 'rect_h', 0.7359, 0.7110], [28, 'redonda', 0.8353, 0.7070],
  [29, 'rect_h', 0.3730, 0.8262], [30, 'rect_h', 0.6419, 0.8262],
];

const NOMBRES = { 1: 'Magistrados' };

// Confirmaciones que la lista de los novios da por hechas y la base no.
// cupos: a cuánto hay que subirlos · agregar: quién falta en la lista de
// asistentes · asistentes: la lista completa, cuando hay que rehacerla.
const AJUSTES = [
  { id: 'INV037', cupos: 2, agregar: 'Esposo de Claudia Paredes' },
  { id: 'INV052', cupos: 2, agregar: 'Esposo de Manuel Castellanos' },
  { id: 'INV021', cupos: 2, agregar: 'Hija de Luis Rubio' },
  { id: 'INV049', cupos: 2, agregar: 'Hija de Dina Ochoa' },
  { id: 'INV099',           agregar: 'Pareja de Carlos Pineda' },
  { id: 'INV030',           agregar: 'Pareja de Oskar Castillo' },
  // Había dicho que no; en la lista de los novios sí va, con Beatriz.
  { id: 'INV026', asistentes: ['Sr. Gustavo Alejos', 'Beatriz'] },
];

const MESAS = {
  1: { invitaciones: ['INV034', 'INV185', 'INV035', 'INV037', 'INV039'],
       apartados: ['Pepe Girón'] },
  2: { invitaciones: ['INV043', 'INV017', 'INV018', 'INV026'],
       apartados: ['Mauricio Orozco', 'Esposa de Mauricio Orozco'] },
  3: { invitaciones: ['INV040', 'INV041', 'INV052', 'INV021', 'INV023'] },
  4: { invitaciones: ['INV045'],
       apartados: ['Eva Reinos', 'Esposo de Eva Reinos',
                   'Miguel Catalán', 'Esposa de Miguel Catalán',
                   'Marco Tulio Páez', 'Esposa de Marco Tulio Páez',
                   'José Argueta', 'Esposa de José Argueta'] },
  5: { invitaciones: ['INV049', 'INV048', 'INV051', 'INV050', 'INV199'] },
  6: { invitaciones: ['INV019', 'INV187', 'INV022', 'INV194', 'INV195'] },
  7: { invitaciones: ['INV099', 'INV031', 'INV030', 'INV025', 'INV020'] },
};

async function rpc(fn, args = {}) {
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
  const d = t ? JSON.parse(t) : null;
  if (!r.ok) throw new Error(`${fn}: ${(d && d.message) || r.status}`);
  return d;
}

async function pedirClave() {
  if (env.VA_CLAVE) return env.VA_CLAVE;
  const rl = createInterface({ input: stdin, output: stdout });
  const c = await rl.question('Clave de administración: ');
  rl.close();
  return c.trim();
}

const clave = await pedirClave();
const datos = await rpc('admin_mesas_datos', { p_clave: clave });
if (!('apartados' in datos)) {
  throw new Error('Falta la migración 016 en la base.');
}
const porId = new Map(datos.invitados.map(i => [i.id, i]));

for (const [n, m] of Object.entries(MESAS)) {
  for (const id of m.invitaciones) {
    if (!porId.has(id)) throw new Error(`Mesa ${n}: no existe ${id}`);
  }
}

console.log(`Mesas actuales: ${datos.mesas.length} · se borran y se crean ${PLANO.length}.`);
for (const a of AJUSTES) {
  const inv = porId.get(a.id);
  console.log(`  ${a.id} ${inv.nombre}: ${a.cupos ? `cupos ${inv.cupos}→${a.cupos}, ` : ''}`
    + (a.asistentes ? `van ${a.asistentes.join(' y ')}` : `se agrega "${a.agregar}"`));
}
for (const [n, m] of Object.entries(MESAS)) {
  const nombres = m.invitaciones.map(id => porId.get(id).nombre);
  console.log(`  Mesa ${n}: ${nombres.join(' · ')}${m.apartados ? ' · apartados: ' + m.apartados.join(', ') : ''}`);
}
if (!APLICAR) {
  console.log('\nNada escrito. Corre con --aplicar para hacerlo.');
  process.exit(0);
}

// 1 · Salón limpio y las 30 mesas del plano.
for (const m of datos.mesas) await rpc('admin_mesa_borrar', { p_clave: clave, p_id: m.id });
for (const [id, forma, x, y] of PLANO) {
  const m = await rpc('admin_mesa_guardar', {
    p_clave: clave, p_capacidad: 10, p_forma: forma, p_pos_x: x, p_pos_y: y,
    p_nombre: NOMBRES[id] || null,
  });
  if (m.id !== id) throw new Error(`Se esperaba la mesa ${id} y se creó la ${m.id}`);
}

// 2 · Confirmaciones. Se conservan los asistentes que ya estaban, con sus
//     restricciones; solo se agrega a quien falta.
for (const a of AJUSTES) {
  const inv = porId.get(a.id);
  if (a.cupos && inv.cupos < a.cupos) {
    await rpc('admin_set_cupos', { p_clave: clave, p_invitado_id: a.id, p_cupos: a.cupos });
  }
  let lista;
  if (a.asistentes) {
    lista = a.asistentes.map(nombre => ({ nombre, restriccion: '' }));
  } else {
    lista = inv.asistira === true && inv.asistentes.length
      ? [...inv.asistentes]
      : [{ nombre: inv.nombre, restriccion: '' }];
    if (!lista.some(p => p.nombre === a.agregar)) lista.push({ nombre: a.agregar, restriccion: '' });
  }
  await rpc('admin_guardar_rsvp', {
    p_clave: clave, p_invitado_id: a.id, p_asistira: true, p_asistentes: lista,
  });
}

// 3 · Sentar y apartar.
for (const [n, m] of Object.entries(MESAS)) {
  for (const id of m.invitaciones) {
    const r = await rpc('admin_sentar_grupo', { p_clave: clave, p_invitado_id: id, p_mesa_id: +n });
    if (r.faltaron) console.warn(`  ! Mesa ${n}: a ${id} le faltaron ${r.faltaron} lugares`);
  }
  for (const nombre of m.apartados || []) {
    await rpc('admin_apartar', { p_clave: clave, p_mesa_id: +n, p_nombre: nombre });
  }
}

// 4 · Comprobación.
const fin = await rpc('admin_mesas_datos', { p_clave: clave });
for (const n of Object.keys(MESAS)) {
  const s = fin.asientos.filter(a => a.mesa_id === +n).length;
  const p = fin.apartados.filter(a => a.mesa_id === +n).length;
  console.log(`Mesa ${n}: ${s} sentados + ${p} apartados = ${s + p}`);
}
console.log(`Total: ${fin.mesas.length} mesas, ${fin.asientos.length} sentados, ${fin.apartados.length} apartados.`);
