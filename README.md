# Valeria & Apolo · Invitación interactiva

Invitación web con RSVP en vivo contra Supabase. Archivo único:
`invitacion-valeria-apolo.html` — sin build, sin dependencias.

---

## 1. Arquitectura

- **Frontend**: `invitacion-valeria-apolo.html` (HTML/CSS/JS vanilla, un solo archivo).
- **Backend**: Supabase (PostgreSQL + REST + RLS) — proyecto `wedding-valeria-apolo`.
  - URL: `https://psmaynxnphbfbtayzaeb.supabase.co`
  - Anon key ya embebida en `CONFIG.supabaseKey` del HTML.
- **Persistencia**: las respuestas viven en la tabla `rsvps` de Supabase.
  Cualquier dispositivo ve las mismas respuestas.

### Tablas

**`invitados`** — fuente de verdad de la lista:
```
id           text primary key
nombre       text  -- titular (con el que se busca en el RSVP)
acompanantes text[] -- nombres precargados
cupos        int
grupo        text
mesa         int
tipo         text  -- familia | amigo | trabajo | otro
codigo       text
creado_en    timestamptz
```

**`rsvps`** — una fila por invitado (upsert por `invitado_id`):
```
invitado_id    text pk fk → invitados.id
nombre_titular text
telefono       text
asistira       boolean
asistentes     jsonb   -- [{ nombre, restriccion }, ...]
roster         jsonb   -- estado completo de checkboxes (por si se reabre)
licor          text[]
comentarios    text
actualizado_en timestamptz
```

### RLS (Row Level Security)

- `invitados`: SELECT público (el buscador necesita consultarla).
- `rsvps`: SELECT/INSERT/UPDATE público (con anon key). Upsert por PK evita duplicados.

Si quieres endurecer la seguridad (ej. exigir código de invitación), ver sección 7.

---

## 2. Secciones de la invitación

1. **Portada** · sobre burgundy con pétalos cayendo, apertura cinematográfica.
2. **Hero** · nombres, fecha, foto y timeline del día.
3. **Cuenta regresiva** · tiles con animación flip 3D.
4. **Nuestra historia** · timeline narrativo.
5. **Fechas importantes** (el "siempre un 7").
6. **Galería**.
7. **Itinerario** · 6 momentos (ceremonia, cóctel, cena, primer baile, fiesta, cierre).
8. **Ubicación** · Google Maps + Waze.
9. **RSVP** · búsqueda por nombre → checkboxes precargados con los acompañantes asignados.
10. **Adultos**, **Dress code**, **Regalos**.
11. **Playlist** · botón directo a la playlist colaborativa de Spotify.

### Panel admin

- **Acceso**: doble clic en los "· · ·" del footer, o `#admin` en la URL.
- **Contraseña**: `CONFIG.adminPassword` (actualmente `valeria07` — **cámbiala**).
- **Tabs**: Dashboard · Invitados · Licor.
- **Filtros**: estado · tipo · mesa.
- **Export**: CSV de invitados con toda la data del RSVP.

---

## 3. Configuración

Edita `CONFIG` al inicio del `<script>`:

```js
const CONFIG = {
  brideName: "Valeria",
  groomName: "Apolo",
  weddingDateISO: "2026-11-07T16:00:00-06:00",
  adminPassword: "valeria07",          // ← CÁMBIALA antes de publicar
  bankAccount: "1591672",
  spotifyPlaylistUrl: "https://open.spotify.com/playlist/TU_ID",
  supabaseUrl: "https://psmaynxnphbfbtayzaeb.supabase.co",
  supabaseKey: "sb_publishable_vl2iawt4czQVfk53ACvxBg_TvkpUfI-",
};
```

---

## 4. Cargar invitados desde Google Sheets

La tabla `invitados` tiene 5 filas de ejemplo. Para cargar la lista real desde
tu Sheet:

### 4.1 · Compartir el Sheet

Abre el Sheet → botón **Share** (arriba a la derecha) → cambia a
**"Cualquier persona con el enlace · Lector"**. Sin esto, todo intento de leerlo
devuelve `401 Unauthorized`.

### 4.2 · Estructura esperada de columnas

Las columnas del Sheet deben llamarse (en fila 1, en este orden):

```
id | nombre | acompanantes | cupos | grupo | mesa | tipo | codigo
```

- `acompanantes`: separados por `|` (pipe). Ej: `María Pérez|Luis Pérez`
- `cupos`: número (total = titular + acompañantes, o más si hay libres)
- `tipo`: `familia` / `amigo` / `trabajo` / `otro`

### 4.3 · Importar

**Opción A — UI de Supabase (más simple)**

1. Ve a <https://supabase.com/dashboard/project/psmaynxnphbfbtayzaeb/editor>.
2. Tabla `invitados` → **Insert** → **Import data from CSV**.
3. Exporta tu Sheet como CSV (Archivo → Descargar → .csv) y arrástralo.
4. Mapea las columnas y confirma.

**Opción B — SQL directo**

Ve al **SQL Editor** y corre:

```sql
-- primero borra los 5 de ejemplo
delete from invitados where id like 'INV%';

-- luego inserta los tuyos
insert into invitados (id, nombre, acompanantes, cupos, grupo, mesa, tipo, codigo)
values
  ('G001', 'Nombre Apellido', ARRAY['Acompañante 1']::text[], 2, 'Familia novia', 1, 'familia', 'VA001'),
  ('G002', 'Otro Invitado',    ARRAY[]::text[],                1, 'Amigos novio',  3, 'amigo',   'VA002');
```

**Opción C — Avísame cuando el Sheet esté público**, lo leo y ejecuto el
INSERT por ti.

---

## 5. Despliegue

Es un archivo HTML estático — cualquier host sirve.

- **Netlify Drop** (30 s): <https://app.netlify.com/drop> → arrastra la carpeta.
- **Vercel**: `npm i -g vercel && vercel` en la carpeta.
- **GitHub Pages**: rename a `index.html`, push a repo, Settings → Pages.
- **Dominio custom**: cualquiera de los 3 lo soporta.

La anon key está diseñada para ir en el frontend — es pública por definición.
Lo que protege los datos es RLS, no el secreto de la key.

---

## 6. Checklist antes de publicar

- [ ] Cambiar `CONFIG.adminPassword`.
- [ ] Importar invitados reales (sección 4).
- [ ] Pegar el link real de playlist en `CONFIG.spotifyPlaylistUrl`.
- [ ] Revisar venue y dirección en la sección `location`.
- [ ] Reemplazar textos de "Nuestra historia" con la historia real.
- [ ] Subir fotos finales y actualizar los `src` del hero/gallery.
- [ ] Probar flujo en iPhone + Android + desktop.

---

## 7. Endurecer seguridad (opcional)

La configuración actual es apropiada para bodas (bajo riesgo). Si quieres más
control:

### Exigir código de invitación

Cambia la política de SELECT en `invitados` para solo permitir
búsqueda si `codigo` coincide:

```sql
drop policy "invitados lectura publica" on invitados;
create policy "invitados por codigo" on invitados
  for select to anon
  using (codigo = current_setting('request.headers', true)::json->>'x-invite-code');
```

Y en el frontend añade `headers: { 'x-invite-code': codigoPorQueryParam }`.

### Restringir escrituras por rate

Supabase Edge Functions con rate limiting, o usa un JWT temporal firmado
con el código. Avísame si lo necesitas.

---

## 8. Archivos del proyecto

```
invitaciones boda/
├── invitacion-valeria-apolo.html   ← la app completa (texto, estilos, JS, Supabase)
├── README.md                        ← este documento
└── WhatsApp Image *.jpeg            ← fotos (hero + gallery)
```

---

## 9. Debug rápido

```bash
# ¿la lista se está leyendo?
curl -s "https://psmaynxnphbfbtayzaeb.supabase.co/rest/v1/invitados?select=id,nombre" \
  -H "apikey: sb_publishable_vl2iawt4czQVfk53ACvxBg_TvkpUfI-"

# ¿cuántos RSVPs hay?
curl -s "https://psmaynxnphbfbtayzaeb.supabase.co/rest/v1/rsvps?select=count" \
  -H "apikey: sb_publishable_vl2iawt4czQVfk53ACvxBg_TvkpUfI-" \
  -H "Prefer: count=exact" -I
```

O desde el dashboard de Supabase: **Table Editor** → `rsvps` → ves todo en vivo.
