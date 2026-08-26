# Valeria & Apolo · Invitación con envío, tracking y RSVP

Dos páginas estáticas, sin build y sin dependencias:

| Archivo | Qué es | Quién la abre |
|---|---|---|
| `index.html` | La invitación. Con `?i=TOKEN` saluda por nombre, registra la apertura y precarga el RSVP. | Los invitados |
| `consola.html` | Consola de envío por WhatsApp y seguimiento. Pide clave. | Ustedes dos |

Backend: Supabase (`psmaynxnphbfbtayzaeb`), PostgreSQL 17.

---

## 1. Cómo funciona el circuito

```
Google Sheet (celulares)
        │  importar_telefonos.mjs
        ▼
   invitados  ──token──►  https://…/?i=ecba5a6c3352
        │                          │
        │                          ├─► abrir_invitacion()  →  tabla aperturas
        │                          └─► guardar_rsvp()      →  tabla rsvps
        │
        └──►  consola.html  ──wa.me──►  WhatsApp  →  tabla envios
```

Cada invitado tiene un **token** de 12 caracteres. Su link es
`https://apoloalvaradoc-cmd.github.io/wedding-valeria-apolo/?i=<token>`.
Abrirlo registra una fila en `aperturas` — eso es lo que alimenta todo el
seguimiento. Quien pierda su link puede buscarse por nombre; esa apertura
queda marcada con `origen = 'buscador'`.

---

## 2. Seguridad

**Ninguna tabla es legible con la anon key.** RLS activo y sin políticas, así
que `GET /rest/v1/invitados` responde `permission denied`. Todo el acceso
legítimo pasa por funciones `SECURITY DEFINER`:

| Función | Quién la llama | Qué devuelve |
|---|---|---|
| `abrir_invitacion(token)` | invitación | datos del invitado, **sin** teléfono ni correo |
| `buscar_invitado(q)` | invitación | máximo 8 resultados, mínimo 3 letras |
| `cargar_invitado(id)` | invitación | igual, y registra la apertura |
| `guardar_rsvp(token, …)` | invitación | valida token y que no se excedan los cupos |
| `admin_datos(clave)` | panel admin | todo, incluye PII |
| `admin_lista_envio(clave)` | consola | todo + teléfono + token |
| `admin_registrar_envio(clave, …)` | consola | marca un envío |
| `admin_set_telefono(clave, …)` | consola | corrige un número |

La clave de administración **ya no vive en el HTML**. Se compara contra un
hash bcrypt guardado en la tabla `config`, con medio segundo de espera en cada
intento fallido. Para cambiarla:

```sql
insert into public.config (clave, valor)
values ('admin_hash', extensions.crypt('TU_NUEVA_CLAVE', extensions.gen_salt('bf', 10)))
on conflict (clave) do update set valor = excluded.valor;
```

Los tres links salientes (Maps, Waze, Spotify) llevan `rel="noreferrer"` para
que el token no se filtre al navegar fuera.

---

## 3. Tablas

```
invitados    id, nombre, acompanantes[], cupos, grupo, mesa, tipo, codigo,
             token, telefono, email, notas
rsvps        invitado_id, nombre_titular, asistira, asistentes[jsonb],
             roster[jsonb], email, comentarios, actualizado_en
aperturas    invitado_id, abierto_en, origen (link|buscador), user_agent, referrer
envios       invitado_id, tipo (invitacion|recordatorio), canal, enviado_en, nota
config       clave, valor          ← guarda admin_hash
```

`asistentes` guarda quién viene de verdad; `roster` guarda el estado completo
de los checkboxes, para que al reabrir el link el formulario aparezca tal como
lo dejaron.

---

## 4. Cargar los teléfonos

Los 131 invitados ya están en la base. Lo único que falta son los celulares.

```bash
node importar_telefonos.mjs invitados.csv
```

Corre en simulación: reporta cuántos hará match, cuáles no aparecen en la
base, qué números no se entienden y quiénes quedan sin teléfono. Si el
reporte se ve bien:

```bash
node importar_telefonos.mjs invitados.csv --aplicar
```

El script busca solo las columnas de **nombre** y **celular** (tolera que se
llamen `Celular`, `Teléfono`, `WhatsApp`, `Móvil`), ignora las filas de título,
normaliza a `+502` los números de 8 dígitos, y compara nombres sin importar
tildes ni mayúsculas. Nombres repetidos los deja fuera en vez de adivinar.

También puedes escribir números sueltos a mano desde la consola, en la columna
Teléfono.

---

## 5. Enviar por WhatsApp

Abre `consola.html` (funciona igual en la computadora que en el teléfono) y
entra con la clave.

- **Plantillas**: invitación, recordatorio para quien no abrió, recordatorio
  para quien abrió sin confirmar, y recordatorio final. Editables — se guardan
  en el navegador. Marcadores: `{nombre}`, `{primer_nombre}`, `{cupos}`, `{link}`.
- **Enviar**: abre WhatsApp con el número y el mensaje ya escritos. Tú das
  Enter. El envío queda registrado al volver.
- **Cola**: el botón de abajo salta al siguiente pendiente que tenga teléfono
  válido y que no haya recibido ya esa plantilla.
- **Filtros**: sin enviar · enviados que no abrieron · abrieron sin confirmar ·
  falta confirmar · confirmados · no asistirán · sin teléfono.

El envío es asistido a propósito. 131 mensajes seguidos desde un número
personal es exactamente el patrón que WhatsApp marca como spam — conviene
mandar en tandas de 30 o 40 por día.

---

## 6. Ver quién confirmó

Dos caminos, mismos datos:

- **`consola.html`** — la tabla de siempre, con aperturas y envíos.
- **Panel dentro de la invitación** — doble clic en los `· · ·` del footer, o
  `#admin` en la URL. Tres pestañas: Dashboard, Invitados, Seguimiento
  (no abrieron · abrieron sin confirmar · restricciones alimenticias).
  Exporta CSV con todo.

---

## 7. Migraciones

`supabase/migrations/` en orden:

| Archivo | Qué hace |
|---|---|
| `schema.sql` | esquema original (001) |
| `002_links_tracking.sql` | tokens, teléfono, email, aperturas, envios, config, cierre de RLS |
| `003_rpcs.sql` | funciones de la invitación |
| `004_rpcs_consola_envio.sql` | funciones de la consola |

Al restaurar en un proyecto nuevo hay que correrlas en orden y después
sembrar `admin_hash` y generar los tokens — está anotado al final del 004.

---

## 8. Despliegue

GitHub Pages sirve la rama `main`:
<https://apoloalvaradoc-cmd.github.io/wedding-valeria-apolo/>

Push a `main` y listo. La anon key en el HTML es pública por diseño; lo que
protege los datos es RLS y las funciones, no el secreto de la key.

---

## 9. Antes de mandar la primera invitación

- [ ] Cambiar la clave de administración (sección 2).
- [ ] Cargar los teléfonos (sección 4) y revisar los que queden marcados.
- [ ] Pegar el link real de la playlist en `CONFIG.spotifyPlaylistUrl`.
- [ ] Mandarte el link a ti mismo y confirmar de prueba, punta a punta.
- [ ] Borrar esa confirmación de prueba antes de arrancar en serio.
- [ ] Probar en iPhone y Android.

---

## 10. Ojo con esto

- **Supabase free se pausa** tras ~7 días sin tráfico, y el plan solo permite
  2 proyectos activos por usuario. Mientras la invitación circule hay tráfico
  de sobra; después de la boda, exporta el CSV antes de que se duerma.
- **La apertura se atribuye al dueño del link.** Si alguien reenvía su link a
  un familiar, esa apertura cuenta como suya.
- **El preview de WhatsApp no cuenta como apertura** — no ejecuta JavaScript.

---

## 11. Debug rápido

```bash
# Las tablas deben estar cerradas: esto tiene que fallar
curl -s "https://psmaynxnphbfbtayzaeb.supabase.co/rest/v1/invitados?select=*" \
  -H "apikey: sb_publishable_vl2iawt4czQVfk53ACvxBg_TvkpUfI-"

# El buscador sí debe responder
curl -s -X POST "https://psmaynxnphbfbtayzaeb.supabase.co/rest/v1/rpc/buscar_invitado" \
  -H "apikey: sb_publishable_vl2iawt4czQVfk53ACvxBg_TvkpUfI-" \
  -H "Content-Type: application/json" -d '{"q":"varg"}'
```
