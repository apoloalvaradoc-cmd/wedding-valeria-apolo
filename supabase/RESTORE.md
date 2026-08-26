# Restore · wedding-valeria-apolo

## Estado actual (26-ago-2026)

Proyecto **activo**. El plan free permite 2 proyectos activos por usuario; para
reactivar este se pausó `agendaflow-beauty`.

- `invitados`: **131 filas**, todas con token generado. Teléfonos pendientes de
  cargar desde el Sheet (ver README, sección 4).
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
   `migrations/003_rpcs.sql` → `migrations/004_rpcs_consola_envio.sql`
2. Sembrar la clave de administración:
   ```sql
   insert into public.config (clave, valor)
   values ('admin_hash', extensions.crypt('TU_CLAVE', extensions.gen_salt('bf', 10)))
   on conflict (clave) do update set valor = excluded.valor;
   ```
3. Cargar los invitados (CSV en el Table Editor, o INSERT).
4. Generar tokens:
   ```sql
   update public.invitados
   set token = substr(md5(id || gen_random_uuid()::text), 1, 12)
   where token is null;
   ```
5. Actualizar `CONFIG.supabaseUrl` y `CONFIG.supabaseKey` en `index.html`
   **y** en `consola.html`, más `SUPABASE_URL`/`SUPABASE_KEY` en
   `importar_telefonos.mjs`.
6. Commit + push a `main`.

> **Ojo:** regenerar tokens invalida todos los links ya enviados. Si la
> invitación ya circuló, respalda `invitados` con sus tokens antes de tocar nada.

## Respaldo de datos antes de pausar

```sql
select * from public.invitados;
select * from public.rsvps;
select * from public.aperturas;
select * from public.envios;
```

O desde la consola: botón **CSV**.
