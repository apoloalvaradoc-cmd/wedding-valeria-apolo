import { readFileSync } from 'fs';

const raw = readFileSync('C:/Users/50255/AppData/Local/Temp/invitados.csv', 'utf8');

// Simple CSV row parser respecting double quotes
function parseCSV(text) {
  const rows = [];
  let row = [], cell = '', inQ = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQ) {
      if (c === '"' && text[i+1] === '"') { cell += '"'; i++; }
      else if (c === '"') inQ = false;
      else cell += c;
    } else {
      if (c === '"') inQ = true;
      else if (c === ',') { row.push(cell); cell = ''; }
      else if (c === '\n') { row.push(cell); rows.push(row); row = []; cell = ''; }
      else if (c === '\r') {}
      else cell += c;
    }
  }
  if (cell.length || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

const all = parseCSV(raw);
// Header is row index 1, data starts at index 2; columns: _, Nombre, Acompañante, Relación, Celular, _, Cupos
const tipoOf = (rel) => {
  const r = (rel || '').toLowerCase().trim();
  if (r.includes('familia')) return 'familia';
  if (r.includes('damita') || r.includes('caballero')) return 'cortejo';
  if (r.includes('amigos pap')) return 'amigos_papa';
  if (r.includes('amigos mam')) return 'amigos_mama';
  if (r.includes('amigos')) return 'amigo';
  return 'otro';
};

// Split companions string into clean array of names. Drop generic descriptors.
const isDescriptor = (s) => {
  const x = s.toLowerCase().trim();
  if (!x) return true;
  if (['no', 'no ', '-', 'n/a'].includes(x)) return true;
  // Pure relationship words → leave as empty editable slot, not as preset
  if (/^(esposo|esposa|novio|novia|hijo|hija|hijos|hermano|hermana|pareja|acompañante)$/i.test(x)) return true;
  return false;
};
const splitCompanions = (s) => {
  if (!s) return [];
  const cleaned = s.replace(/^amigos\s*-\s*/i, '').trim();
  if (isDescriptor(cleaned)) return [];
  // Split by commas, ' y ', ' & '
  return cleaned.split(/\s*,\s*|\s+y\s+|\s+&\s+/)
    .map(x => x.trim())
    .filter(x => x && !isDescriptor(x));
};

const guests = [];
let n = 0;
for (let i = 2; i < all.length; i++) {
  const r = all[i];
  if (!r || r.length < 7) continue;
  const nombre = (r[1] || '').trim();
  if (!nombre) continue;
  // Skip placeholder "INVITADOS PAPÁ" — collective slot, no name
  if (/^invitados\s+pap[áa]/i.test(nombre)) continue;
  const acomStr = (r[2] || '').trim();
  const relacion = (r[3] || '').trim();
  const celular = (r[4] || '').trim();
  const cuposStr = (r[6] || '').trim();
  const cupos = parseInt(cuposStr, 10);
  if (!cupos || cupos < 1 || cupos > 30) continue; // skip total rows like 314
  n++;
  const id = 'INV' + String(n).padStart(3, '0');
  const codigo = 'VA' + String(n).padStart(3, '0');
  const acomp = splitCompanions(acomStr);
  guests.push({
    id, nombre, acompanantes: acomp, cupos, grupo: relacion,
    mesa: null, tipo: tipoOf(relacion), codigo, celular,
  });
}

const sqlEsc = (s) => s == null ? 'null' : `'${String(s).replace(/'/g, "''")}'`;
const sqlArr = (arr) => `ARRAY[${arr.map(sqlEsc).join(',')}]::text[]`;

console.log('-- Generated from Google Sheets · ' + guests.length + ' guests');
console.log('delete from public.invitados;');
console.log('insert into public.invitados (id, nombre, acompanantes, cupos, grupo, mesa, tipo, codigo) values');
console.log(guests.map(g =>
  `(${sqlEsc(g.id)}, ${sqlEsc(g.nombre)}, ${sqlArr(g.acompanantes)}, ${g.cupos}, ${sqlEsc(g.grupo)}, ${g.mesa ?? 'null'}, ${sqlEsc(g.tipo)}, ${sqlEsc(g.codigo)})`
).join(',\n') + ';');

console.error(`Parsed ${guests.length} guests, ${guests.reduce((a,g)=>a+g.cupos,0)} total cupos`);
