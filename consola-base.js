/* ============================================================
   Consola · Valeria & Apolo · base compartida

   La consola son tres pantallas (listado, mensajes, mesas) y todas
   necesitan lo mismo: la clave, la conexión a Supabase, el menú y
   media docena de ayudas. Antes todo eso vivía dentro de
   consola.html; al abrir una segunda pantalla habría quedado
   duplicado, así que aquí queda una sola copia.

   No usa la llave de servicio de Supabase. Todo pasa por RPCs que
   validan la clave de administración contra un hash bcrypt guardado
   en la base, así que estas páginas se pueden abrir desde el
   teléfono sin exponer nada.
============================================================ */

const CONFIG = {
  supabaseUrl: "https://psmaynxnphbfbtayzaeb.supabase.co",
  supabaseKey: "sb_publishable_vl2iawt4czQVfk53ACvxBg_TvkpUfI-",
  // La dirección que reciben los invitados. Va fija a propósito: antes se
  // deducía de dónde estuviera abierta la consola, así que abrirla desde
  // GitHub Pages o desde localhost mandaba links con ese dominio. El sitio
  // público es este y no cambia según por dónde entres a administrar.
  sitioPublico: 'https://valeria-y-apolo.vercel.app/',
  paisPorDefecto: "502",   // Guatemala
};

const $  = s => document.querySelector(s);
const $$ = s => document.querySelectorAll(s);

/* Misma llave de guardado que el panel de la invitación (index.html): así
   la clave se escribe una sola vez por dispositivo y sirve en todas las
   páginas. La segunda lectura es para adoptar la del panel si esta página
   nunca se abrió. */
const CLAVE_GUARDADA = 'va_clave';
let clave = localStorage.getItem(CLAVE_GUARDADA)
         || localStorage.getItem('va_admin_clave')
         || null;

const SECCIONES = [
  { k: 'listado',  href: 'consola.html',  label: 'Listado'  },
  { k: 'mensajes', href: 'mensajes.html', label: 'Mensajes' },
  { k: 'mesas',    href: 'mesas.html',    label: 'Mesas'    },
];

/* ---------- Supabase RPC ---------- */
async function rpc(fn, args = {}) {
  const r = await fetch(`${CONFIG.supabaseUrl}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      apikey: CONFIG.supabaseKey,
      Authorization: 'Bearer ' + CONFIG.supabaseKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(args),
  });
  const t = await r.text();
  let d = null;
  try { d = t ? JSON.parse(t) : null; } catch { d = t; }
  if (!r.ok) {
    const e = new Error((d && d.message) || `RPC ${fn} ${r.status}`);
    e.code = d && d.code;
    throw e;
  }
  return d;
}

/* ---------- Ayudas ---------- */
function fecha(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('es-GT', { dateStyle: 'short', timeStyle: 'short' });
}

function escapeHtml(s) {
  return String(s ?? '').replace(/[&<>"']/g, m => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[m]));
}

const hoyLargo = () =>
  new Date().toLocaleDateString('es-GT', { day: '2-digit', month: 'long', year: 'numeric' });

/* ---------- Teléfono ---------- */
// Devuelve solo dígitos en formato internacional, o null si no se puede.
function normalizarTel(raw) {
  if (!raw) return null;
  let d = String(raw).replace(/\D/g, '');
  if (!d) return null;
  d = d.replace(/^0+/, '');
  if (d.length === 8) d = CONFIG.paisPorDefecto + d;          // 5555-5555 → +502
  if (d.startsWith('00')) d = d.slice(2);
  return d.length >= 10 && d.length <= 15 ? d : null;
}
function mostrarTel(raw) {
  const d = normalizarTel(raw);
  if (!d) return raw || '';
  if (d.startsWith(CONFIG.paisPorDefecto) && d.length === 11) {
    return `+${CONFIG.paisPorDefecto} ${d.slice(3, 7)} ${d.slice(7)}`;
  }
  return '+' + d;
}

/* ---------- Personas de una invitación ----------
   Espejo de mesas_personas() en la base: quién hay realmente que sentar
   o contar. Si ya confirmó valen los nombres que apuntó; si todavía no,
   se usan sus cupos para poder ir armando el salón desde antes. */
function personasDe(inv) {
  const asis = Array.isArray(inv.asistentes) ? inv.asistentes : [];
  if (inv.asistira === false) return [];
  if (inv.asistira === true) {
    const lista = asis.map((a, i) => ({
      idx: i,
      nombre: (a && a.nombre || '').trim() || `Invitado ${i + 1}`,
      restriccion: (a && a.restriccion || '').trim(),
      confirmado: true,
    }));
    return lista.length ? lista : [{ idx: 0, nombre: inv.nombre, restriccion: '', confirmado: true }];
  }
  // Todavía sin respuesta: se usan los nombres que ya conocemos y, para el
  // resto de cupos, marcadores. Así la mesa ya reserva el lugar.
  const acomps = Array.isArray(inv.acompanantes) ? inv.acompanantes : [];
  const out = [];
  for (let i = 0; i < (inv.cupos || 0); i++) {
    let nombre;
    if (i === 0) nombre = inv.nombre;
    else if (i === 1 && inv.nombre_acompanante) nombre = inv.nombre_acompanante;
    else nombre = acomps[i - 1] || `Acompañante ${i}`;
    out.push({ idx: i, nombre, restriccion: '', confirmado: false });
  }
  return out;
}

/* ---------- Arranque común ----------
   Cada página llama a esto una vez. Se encarga del login, del encabezado
   con el menú y de pedir los datos; la página solo pone su contenido y
   sus propios botones.

   op = { seccion, acciones: [{id, label, filled}], cargar() }  */
function arrancarConsola(op) {
  const seccion = SECCIONES.find(s => s.k === op.seccion) || SECCIONES[0];

  // --- Pantalla de clave ---
  const login = document.createElement('div');
  login.id = 'login-view';
  login.innerHTML = `
    <div class="wrap">
      <div class="card login">
        <h2>Consola</h2>
        <p class="hint">Valeria &amp; Apolo · 07.11.2026</p>
        <label for="pass">Clave de administración</label>
        <input type="password" id="pass" autocomplete="current-password" placeholder="••••••••">
        <div id="login-err" class="err hidden"></div>
        <button class="filled" id="btn-login" style="margin-top:0.8rem;width:100%">Entrar</button>
      </div>
    </div>`;
  document.body.insertBefore(login, document.body.firstChild);

  // --- Encabezado con el menú ---
  const app = $('#app');
  const header = document.createElement('header');
  header.innerHTML = `
    <div class="cab-izq">
      <h1>Consola</h1>
      <nav class="menu">
        ${SECCIONES.map(s => `
          <a class="menu-link ${s.k === seccion.k ? 'activo' : ''}" href="${s.href}">${s.label}</a>
        `).join('')}
      </nav>
    </div>
    <div class="row">
      ${(op.acciones || []).map(a =>
        `<button class="small ${a.filled ? 'filled' : ''}" id="${a.id}">${a.label}</button>`).join('')}
      <button class="small" id="btn-logout">Salir</button>
    </div>`;
  app.insertBefore(header, app.firstChild);

  // --- Eventos ---
  const entrar = async () => {
    const err = $('#login-err');
    const btn = $('#btn-login');
    err.classList.add('hidden');
    btn.disabled = true; btn.textContent = 'Verificando...';
    try {
      clave = $('#pass').value;
      await op.cargar();
      localStorage.setItem(CLAVE_GUARDADA, clave);
      localStorage.setItem('va_admin_clave', clave);   // que el panel tampoco la pida
      login.classList.add('hidden');
      app.classList.remove('hidden');
    } catch (e) {
      clave = null;
      err.textContent = e.code === '28000' ? 'Clave incorrecta.' : ('No pudimos conectar: ' + e.message);
      err.classList.remove('hidden');
    } finally {
      btn.disabled = false; btn.textContent = 'Entrar';
    }
  };
  $('#btn-login').addEventListener('click', entrar);
  $('#pass').addEventListener('keydown', e => { if (e.key === 'Enter') entrar(); });
  $('#btn-logout').addEventListener('click', () => {
    localStorage.removeItem(CLAVE_GUARDADA);
    localStorage.removeItem('va_admin_clave');
    location.reload();
  });

  // --- Si la clave ya estaba guardada, se entra directo ---
  if (clave) {
    login.classList.add('hidden');
    app.classList.remove('hidden');
    op.cargar().catch(e => {
      /* Solo se olvida la clave si de verdad es incorrecta (28000). Antes se
         borraba ante cualquier fallo, así que un bache de señal en el
         teléfono obligaba a escribirla de nuevo. */
      if (e && e.code === '28000') {
        localStorage.removeItem(CLAVE_GUARDADA);
        localStorage.removeItem('va_admin_clave');
        clave = null;
        login.classList.remove('hidden');
        app.classList.add('hidden');
      } else {
        alert('No pudimos cargar los datos: ' + e.message);
      }
    });
  }
}
