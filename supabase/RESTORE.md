# Restore · wedding-valeria-apolo

Backup hecho el **2026-05-04** antes de pausar el proyecto Supabase
(plan free no permite estar inactivo indefinidamente sin pausarse).

## Estado al momento del backup
- `invitados`: **0 filas**
- `rsvps`: **0 filas**

No había datos PII que respaldar — la invitación aún no se había
distribuido. Solo se respaldó el esquema (DDL).

## Cómo restaurar

### Opción A — Reactivar el mismo proyecto (recomendado)
1. Login a Supabase Dashboard
2. Buscar el proyecto pausado `wedding-valeria-apolo` (id `psmaynxnphbfbtayzaeb`)
3. Click "Restore project" / "Resume"
4. El esquema se reactiva tal cual estaba — no hace falta correr nada
5. Verificar que `index.html` siga apuntando al mismo URL/key (no debería haber cambiado)

### Opción B — Crear un proyecto nuevo
1. Crear nuevo proyecto en Supabase Dashboard
2. SQL Editor → New query → pegar el contenido completo de `schema.sql` → Run
3. Project Settings → API: copiar el nuevo `URL` y `anon key`
4. Editar `index.html` → buscar `CONFIG.supabaseUrl` y `CONFIG.supabaseKey` y reemplazar
5. Commit + push (deploy automático vía GitHub Pages)

## Cargar la lista de invitados (cuando llegue el momento)
La lista se carga vía SQL `INSERT` o pegando un CSV en el Table Editor de Supabase.
Hay un script `parse_guests.mjs` en la raíz del repo que ayuda a transformar
una lista de invitados en `INSERT INTO invitados ...`.
