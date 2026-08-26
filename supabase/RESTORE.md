# Restore · wedding-valeria-apolo

## Estado actual (26-ago-2026)

Proyecto **activo**. El plan free permite 2 proyectos activos por usuario; para
reactivar este se pausó `agendaflow-beauty`.

- `invitados`: **143 filas · 262 cupos**, reconstruidas desde el Google Sheet
  el 26-ago-2026. Todas con token. 140 tienen al menos un teléfono; sin ninguno
  quedan Abuelito Runy, Marco Morales y Yali Botas.
- `rsvps`, `aperturas`, `envios`: vacías — aún no se distribuye la invitación.
- `config`: contiene `admin_hash`.

> El RESTORE.md anterior decía "0 filas" en `invitados`. Era incorrecto: la
> lista sí estaba cargada.

## Cómo restaurar

### Opción A — Reactivar el mismo proyecto
1. Supabase Dashboard → proyecto `wedding-valeria-apolo` (`psmaynxnphbfbtayzaeb`).
2. "Restore project". Si falla por límite de proyectos activos, pausa otro primero.
3. El esquema y los datos vuelven tal cual. No hace falta correr nada.

### Opción B — Proyecto nuevo desde cero
1. SQL Editor → correr **en orden**:
   `schema.sql` → `migrations/002_links_tracking.sql` →
   `migrations/003_rpcs.sql` → `migrations/004_rpcs_consola_envio.sql` →
   `migrations/005_doble_destino_envio.sql`
2. Sembrar la clave de administración:
   ```sql
   insert into public.config (clave, valor)
   values ('admin_hash', extensions.crypt('TU_CLAVE', extensions.gen_salt('bf', 10)))
   on conflict (clave) do update set valor = excluded.valor;
   ```
3. Regenerar la lista desde el Sheet — genera el INSERT y los tokens de una vez:
   ```bash
   curl -sL "https://docs.google.com/spreadsheets/d/1kwuopuj9nY3wlrEXie9k7cKkVkp37T2Lmzi4nIi3i78/export?format=csv" -o invitados.csv
   node generar_lista_sql.mjs invitados.csv > lista.sql
   ```
4. Pegar `lista.sql` en el SQL Editor.
5. Actualizar `CONFIG.supabaseUrl` y `CONFIG.supabaseKey` en `index.html`
   **y** en `consola.html`, más `SUPABASE_URL`/`SUPABASE_KEY` en
   `importar_telefonos.mjs`.
6. Commit + push a `main`.

> **Ojo:** `generar_lista_sql.mjs` borra y recrea `invitados`, lo que regenera
> todos los tokens e invalida los links ya enviados. Si la invitación ya
> circuló, respalda `invitados` con sus tokens y no lo corras.

## Respaldo de datos antes de pausar

```sql
select * from public.invitados;
select * from public.rsvps;
select * from public.aperturas;
select * from public.envios;
```

O desde la consola: botón **CSV**.
