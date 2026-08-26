-- ============================================================
-- wedding-valeria-apolo · migración 002
-- Links personalizados por invitado, tracking de aperturas,
-- log de envíos y acceso vía RPC (sin lectura pública de PII).
--
-- Contexto: la migración 001 (schema.sql) dejaba `invitados` y
-- `rsvps` con SELECT público. Al agregar teléfonos y correos eso
-- deja de ser aceptable — cualquiera con la anon key podría
-- descargar la lista completa de contactos. Aquí se cierra todo
-- acceso directo y se expone solo lo mínimo vía funciones.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ------------------------------------------------------------
-- Helper: normaliza texto para búsquedas (sin tildes, minúsculas)
-- ------------------------------------------------------------
create or replace function public.norm(t text)
returns text
language sql
immutable
strict
as $$
  select lower(translate(t,
    'ÁÀÄÂÃáàäâãÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔÕóòöôõÚÙÜÛúùüûÑñÇç',
    'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuNnCc'));
$$;

-- ------------------------------------------------------------
-- invitados · nuevas columnas
-- ------------------------------------------------------------
alter table public.invitados
  add column if not exists token    text,
  add column if not exists telefono text,   -- E.164, ej. +50255551234
  add column if not exists email    text,
  add column if not exists notas    text;

create unique index if not exists idx_invitados_token
  on public.invitados (token) where token is not null;

create index if not exists idx_invitados_norm
  on public.invitados (public.norm(nombre));

-- ------------------------------------------------------------
-- rsvps · correo entra, licor y teléfono salen del formulario
-- ------------------------------------------------------------
alter table public.rsvps add column if not exists email text;
alter table public.rsvps drop column if exists licor;
alter table public.rsvps drop column if exists telefono;

-- ------------------------------------------------------------
-- aperturas · una fila por vez que alguien abre la invitación
-- ------------------------------------------------------------
create table if not exists public.aperturas (
  id          bigserial primary key,
  invitado_id text not null references public.invitados(id) on delete cascade,
  abierto_en  timestamptz not null default now(),
  origen      text not null default 'link',   -- link | buscador
  user_agent  text,
  referrer    text
);
create index if not exists idx_aperturas_invitado on public.aperturas (invitado_id);
create index if not exists idx_aperturas_fecha    on public.aperturas (abierto_en desc);

-- ------------------------------------------------------------
-- envios · log de cada WhatsApp mandado desde la consola local
-- ------------------------------------------------------------
create table if not exists public.envios (
  id          bigserial primary key,
  invitado_id text not null references public.invitados(id) on delete cascade,
  tipo        text not null,                     -- invitacion | recordatorio
  canal       text not null default 'whatsapp',
  enviado_en  timestamptz not null default now(),
  nota        text
);
create index if not exists idx_envios_invitado on public.envios (invitado_id);

-- ------------------------------------------------------------
-- config · clave admin hasheada (deja de vivir en el HTML)
-- ------------------------------------------------------------
create table if not exists public.config (
  clave text primary key,
  valor text not null
);

-- ------------------------------------------------------------
-- RLS: todo cerrado. Sin políticas ⇒ anon no toca nada directo.
-- El acceso legítimo pasa por las funciones SECURITY DEFINER.
-- ------------------------------------------------------------
alter table public.invitados enable row level security;
alter table public.rsvps     enable row level security;
alter table public.aperturas enable row level security;
alter table public.envios    enable row level security;
alter table public.config    enable row level security;

drop policy if exists "invitados lectura publica" on public.invitados;
drop policy if exists "rsvps lectura publica"     on public.rsvps;
drop policy if exists "rsvps insert publica"      on public.rsvps;
drop policy if exists "rsvps update publica"      on public.rsvps;

revoke all on public.invitados from anon, authenticated;
revoke all on public.rsvps     from anon, authenticated;
revoke all on public.aperturas from anon, authenticated;
revoke all on public.envios    from anon, authenticated;
revoke all on public.config    from anon, authenticated;
