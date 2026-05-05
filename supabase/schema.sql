-- ============================================================
-- wedding-valeria-apolo · Supabase schema backup
-- Project: psmaynxnphbfbtayzaeb (Postgres 17)
-- Generated: 2026-05-04
--
-- USO:
--   1. En Supabase Dashboard del proyecto reactivado / nuevo:
--      SQL Editor → New query → pegar este archivo → Run
--   2. Después actualizar `CONFIG.supabaseUrl` y `CONFIG.supabaseKey`
--      en index.html si el proyecto cambió de ref/key
--
-- NOTA: este backup solo contiene el ESQUEMA (DDL). Las tablas
-- se crean vacías. Al momento del backup ambas tablas tenían 0
-- filas — no había PII que respaldar.
-- ============================================================

-- ----------- TABLA: invitados (lista de invitados) ----------
CREATE TABLE IF NOT EXISTS public.invitados (
  id            text PRIMARY KEY,
  nombre        text NOT NULL,
  acompanantes  text[] NOT NULL DEFAULT '{}'::text[],
  cupos         integer NOT NULL DEFAULT 1,
  grupo         text,
  mesa          integer,
  tipo          text,
  codigo        text,
  creado_en     timestamptz NOT NULL DEFAULT now()
);

-- ----------- TABLA: rsvps (respuestas) ----------------------
CREATE TABLE IF NOT EXISTS public.rsvps (
  invitado_id    text PRIMARY KEY REFERENCES public.invitados(id),
  nombre_titular text NOT NULL,
  telefono       text,
  asistira       boolean,
  asistentes     jsonb NOT NULL DEFAULT '[]'::jsonb,
  roster         jsonb,
  licor          text[] NOT NULL DEFAULT '{}'::text[],
  comentarios    text,
  actualizado_en timestamptz NOT NULL DEFAULT now()
);

-- ----------- ÍNDICES ----------------------------------------
CREATE INDEX IF NOT EXISTS idx_invitados_nombre_lower
  ON public.invitados USING btree (lower(nombre));

CREATE INDEX IF NOT EXISTS idx_rsvps_asistira
  ON public.rsvps USING btree (asistira);

-- ----------- ROW LEVEL SECURITY ------------------------------
ALTER TABLE public.invitados ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rsvps     ENABLE ROW LEVEL SECURITY;

-- Lectura pública de invitados (necesaria para el buscador del RSVP)
DROP POLICY IF EXISTS "invitados lectura publica" ON public.invitados;
CREATE POLICY "invitados lectura publica"
  ON public.invitados
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- Lectura pública de rsvps (para que admin/dashboard vea respuestas)
DROP POLICY IF EXISTS "rsvps lectura publica" ON public.rsvps;
CREATE POLICY "rsvps lectura publica"
  ON public.rsvps
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- Inserción pública (cualquier invitado puede confirmar por primera vez)
DROP POLICY IF EXISTS "rsvps insert publica" ON public.rsvps;
CREATE POLICY "rsvps insert publica"
  ON public.rsvps
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- Update público (re-confirmaciones / cambios desde mismo dispositivo)
DROP POLICY IF EXISTS "rsvps update publica" ON public.rsvps;
CREATE POLICY "rsvps update publica"
  ON public.rsvps
  FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);
