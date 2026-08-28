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
| `admin_datos(clave)` | panel admin | todo, incluye PII y tokens |
| `admin_guardar_rsvp(clave, …)` | panel admin | registra una confirmación a mano |
| `admin_borrar_rsvp(clave, …)` | panel admin | devuelve a pendiente |
| `admin_actualizar_invitado(clave, …)` | panel admin | nombre, teléfonos y mesa |
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

### Vista previa en WhatsApp

`wa.me` solo acepta texto: no se puede adjuntar una foto al mensaje pre-escrito.
Lo que sí funciona son las etiquetas Open Graph del `<head>` de `index.html`,
que WhatsApp lee del link para armar la tarjeta con `og-preview.jpg` (1200×630,
recorte de la foto del lago). La URL de la imagen debe ser **absoluta** — el
robot de WhatsApp no resuelve rutas relativas ni ejecuta JavaScript, que es
además la razón por la que no genera aperturas falsas.

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

### Actualizar sin romper los links ya enviados

Una vez que empezaron a salir invitaciones, hay que usar el modo incremental:

```bash
VA_CLAVE='tu-clave' node generar_lista_sql.mjs invitados.csv --actualizar > update.sql
```

Compara el Sheet contra la base y emite solo lo necesario: `UPDATE` de los
campos que de verdad cambiaron —sin tocar id ni token, así el link de cada
quien sigue sirviendo— e `INSERT` de los nuevos. No borra a nadie: si alguien
está en la base y ya no en el Sheet, lo reporta para revisarlo a mano.

Empareja **primero por teléfono** y solo después por nombre sin tratamiento
(`Sr.`, `Sra.`, `Dr.`…). Hacerlo solo por nombre fallaba en dos casos reales:
cuando le agregan el tratamiento a alguien que ya estaba, y cuando dos personas
distintas se ven iguales al quitarles las tildes (Mario Calderon y Mario
Calderón son dos primos, no un duplicado).

Para corregir un número suelto sin rehacer la lista, edítalo directamente en la
consola o usa `importar_telefonos.mjs`, que solo escribe teléfonos sobre la
lista existente.

---

## 5. Enviar por WhatsApp

Abre `consola.html` (funciona igual en la computadora que en el teléfono) y
entra con la clave.

- **Plantillas**: invitación, recordatorio para quien no abrió, recordatorio
  para quien abrió sin confirmar, y recordatorio final. Editables — se guardan
  en el navegador. Marcadores: `{nombre}` (nombre y apellido, el que usan las
  plantillas), `{primer_nombre}`, `{cupos}`, `{link}`.
- **Dos destinos por invitación**: cada fila tiene la columna del titular y la
  del acompañante, cada una con su número editable y su botón. El link es el
  mismo para los dos — la invitación es una sola — pero el saludo usa el nombre
  de quien recibe el mensaje.
- **Enviar**: los botones son enlaces reales a `wa.me`, no ventanas emergentes
  — en el celular abren la app de WhatsApp directo, con el número y el mensaje
  ya escritos. Tú das Enter. El envío queda registrado al tocar el botón,
  anotando a cuál de los dos números fue.
- **Cola**: va por número, no por invitación. Un invitado con dos teléfonos
  aparece dos veces hasta que ambos reciban esa plantilla.
- **Filtros**: sin enviar · enviados que no abrieron · abrieron sin confirmar ·
  falta confirmar · confirmados · no asistirán · sin ningún teléfono ·
  **falta un destino** (recibió en un número pero no en el otro).

Hoy son **143 invitaciones y 166 números**. El envío es asistido a propósito:
166 mensajes seguidos desde un número personal es exactamente el patrón que
WhatsApp marca como spam — conviene mandar en tandas de 30 o 40 por día.

---

## 6. Panel de los novios

Doble clic en los `· · ·` del footer, o `#admin` en la URL. Misma clave que
la consola. **Se escribe una sola vez por dispositivo y sirve en las dos
páginas**: entrar en la consola desbloquea el panel y al revés. Queda guardada
en el navegador hasta que se toque "Salir", que la borra de ambas. **El panel es para ver y administrar; los botones de envío en tanda
están en `consola.html`** — hay un enlace directo en el encabezado del panel.
Cuatro pestañas:

- **Resumen** — invitaciones, enviadas, abrieron, confirmadas, no asistirán,
  pendientes y personas. Tasa de respuesta y avance por grupo, para ver dónde
  falta empujar.
- **Invitaciones** — buscador, filtros (confirmados · sin responder · abrieron
  sin confirmar · no abrieron · no asistirán · por tipo · por mesa) y la tabla
  completa. **Toca cualquier fila** para abrir su ficha.
> El formulario va en tres pasos: 1) marcar quiénes asisten, 2) correo y
> mensaje (ambos opcionales), 3) la decisión sí/no pegada al botón. El sí/no
> estaba arriba y elegirlo parecía cerrar el trámite: la gente se salía sin
> enviar. El botón dice qué va a pasar al tocarlo ("Confirmar 2 asistentes",
> "Enviar: no podremos asistir") y se ve apagado mientras falte el paso 3.

- **Confirmados** — la lista cabeza por cabeza: cada persona que asiste, con su
  restricción, de qué invitación viene y su mesa. Es la lista de invitados
  confirmados que se entrega el día del evento. Abajo van las restricciones
  juntas y los mensajes que dejaron los invitados.
- **Aperturas** — quién abrió y cuándo, cuántas veces, y si llegó por su link o
  por el buscador. Separa "abrieron sin confirmar" (los que más conviene
  recordar) de "nunca la abrieron".

### Registrar una confirmación a mano

Muchos van a contestar por WhatsApp en vez de llenar el formulario. En la ficha
de cada invitado (pestaña Invitaciones → tocar la fila) puedes marcar si asiste,
elegir quiénes vienen, corregir el nombre del titular y del acompañante, ambos
teléfonos, anotar restricciones, asignar mesa y dejar una nota. Queda guardado igual que una respuesta normal, pero marcado como
*registrado a mano* para poder distinguirlo.

Desde ahí también se copia el **link personalizado** de esa persona, se le puede
**mandar la invitación por WhatsApp** con un botón por cada uno de sus dos
números, y se puede devolver una respuesta a "pendiente" si se registró por
error.

### Exports

Salen en **.xlsx de verdad**, no CSV renombrado: Excel abre los CSV con avisos
de formato y rompe las tildes, y estos archivos se le entregan a la finca. El
generador está escrito a mano en el propio HTML (un .xlsx es un ZIP con XML
adentro), así que no depende de ninguna librería ni CDN.

Vienen con la paleta de la invitación: cabecera vino con letra crema, filas
alternadas en blanco y crema, bordes rosa, título y fecha arriba, encabezado
congelado, autofiltro puesto y las restricciones alimenticias resaltadas.

- **Invitaciones (Excel)** — una fila por invitación con todo: teléfonos,
  estado, quiénes vienen, restricciones, envíos, aperturas.
- **Lista de confirmados (Excel)** — una fila por persona confirmada, numerada.
- Desde la consola, **Excel** exporta el control de envíos con el link
  personal de cada quien.

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
| `006_admin_gestion_confirmaciones.sql` | registrar confirmaciones a mano, mesas |
| `007_admin_editar_invitado.sql` | editar nombre y teléfonos desde la ficha |

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
