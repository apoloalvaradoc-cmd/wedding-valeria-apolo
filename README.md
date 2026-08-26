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
Google Sheet  ──generar_lista_sql.mjs──►  invitados (143 · 262 cupos)
                                              │
                    token ─────────────────────┤
                      │                        │
   https://…/?i=<token>                        │
        ├─► abrir_invitacion()  →  aperturas   │
        └─► guardar_rsvp()      →  rsvps       │
                                               │
   consola.html ──wa.me──► WhatsApp ──► envios ┘
        (al titular Y al acompañante)
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
             token, telefono, telefono_alt, nombre_acompanante, email, notas
rsvps        invitado_id, nombre_titular, asistira, asistentes[jsonb],
             roster[jsonb], email, comentarios, actualizado_en
aperturas    invitado_id, abierto_en, origen (link|buscador), user_agent, referrer
envios       invitado_id, tipo (invitacion|recordatorio),
             destino (titular|acompanante), canal, enviado_en, nota
config       clave, valor          ← guarda admin_hash
```

`telefono` es el del titular y `telefono_alt` el del acompañante: la invitación
se manda a los dos, y `envios.destino` registra a cuál ya se le escribió.

`asistentes` guarda quién viene de verdad; `roster` guarda el estado completo
de los checkboxes, para que al reabrir el link el formulario aparezca tal como
lo dejaron.

---

## 4. La lista viene del Google Sheet

El Sheet es la fuente de verdad. Para reconstruir la tabla `invitados` a
partir de él:

```bash
curl -sL "https://docs.google.com/spreadsheets/d/1kwuopuj9nY3wlrEXie9k7cKkVkp37T2Lmzi4nIi3i78/export?format=csv" -o invitados.csv
```

Primero el reporte, que no toca nada:

```bash
node generar_lista_sql.mjs invitados.csv --reporte
```

Dice cuántas invitaciones y cupos salen, quién queda sin teléfono, qué números
no se entienden, a quién le dedujo los cupos y qué nombres están repetidos.
Si se ve bien, genera el SQL y pégalo en el SQL Editor de Supabase:

```bash
node generar_lista_sql.mjs invitados.csv > lista.sql
```

Lo que hace el script con los datos del Sheet:

- Salta la fila **"INVITADOS PAPÁ"**, que es un bloque colectivo de 56 cupos,
  no una persona.
- En la columna Acompañante distingue nombres reales de marcadores genéricos
  (`No`, `Acompañante`, `Sra.`, `Hijos`, `amigas`). Los genéricos quedan como
  cupo en blanco para que el invitado escriba el nombre en el RSVP.
- Separa varios acompañantes por coma o por " y ".
- Normaliza a `+502` los números de 8 dígitos, y descarta lo que no sea un
  teléfono (en el Sheet hay un correo y un guión en esa columna).
- Nunca deja menos cupos que nombres ya listados.

> **Esto regenera todos los tokens**, o sea que invalida los links ya enviados.
> Solo es seguro mientras no se haya mandado nada.

Para corregir un número suelto sin rehacer la lista, edítalo directamente en la
consola o usa `importar_telefonos.mjs`, que solo escribe teléfonos sobre la
lista existente.

---

## 5. Enviar por WhatsApp

Abre `consola.html` (funciona igual en la computadora que en el teléfono) y
entra con la clave.

- **Plantillas**: invitación, recordatorio para quien no abrió, recordatorio
  para quien abrió sin confirmar, y recordatorio final. Editables — se guardan
  en el navegador. Marcadores: `{nombre}`, `{primer_nombre}`, `{cupos}`, `{link}`.
- **Dos destinos por invitación**: cada fila tiene la columna del titular y la
  del acompañante, cada una con su número editable y su botón. El link es el
  mismo para los dos — la invitación es una sola — pero el saludo usa el nombre
  de quien recibe el mensaje.
- **Enviar**: abre WhatsApp con el número y el mensaje ya escritos. Tú das
  Enter. El envío queda registrado al volver, anotando a cuál de los dos fue.
- **Cola**: va por número, no por invitación. Un invitado con dos teléfonos
  aparece dos veces hasta que ambos reciban esa plantilla.
- **Filtros**: sin enviar · enviados que no abrieron · abrieron sin confirmar ·
  falta confirmar · confirmados · no asistirán · sin ningún teléfono ·
  **falta un destino** (recibió en un número pero no en el otro).

Hoy son **143 invitaciones y 166 números**. El envío es asistido a propósito:
166 mensajes seguidos desde un número personal es exactamente el patrón que
WhatsApp marca como spam — conviene mandar en tandas de 30 o 40 por día.

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
| `005_doble_destino_envio.sql` | segundo teléfono y `envios.destino` |

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
- [ ] Conseguir teléfono para los 3 que no tienen ninguno: **Abuelito Runy**,
      **Marco Morales** y **Yali Botas** (esta última dejó un correo en la
      columna del celular).
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
