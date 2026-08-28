-- ============================================================
-- migración 010 · endurecer contra un bromista con la anon key
--
-- Auditoría del 28-ago-2026. El hueco real: cargar_invitado(id) recibía
-- ids secuenciales (INV001…) y devolvía el token, así que enumerando se
-- bajaban los 181 tokens y con uno se podía confirmar por otro.
-- ============================================================

-- 1) El buscador (camino sin token) deja de exponer el token. Ver y
--    precargar sí; para GUARDAR hace falta el token del link personal.
create or replace function public.invitado_json_sin_token(v public.invitados)
returns jsonb language sql stable
set search_path = public
as $fn$
  select jsonb_build_object(
    'id', v.id, 'nombre', v.nombre,
    'acompanantes', to_jsonb(coalesce(v.acompanantes,'{}'::text[])),
    'cupos', v.cupos, 'grupo', v.grupo, 'mesa', v.mesa, 'tipo', v.tipo,
    'rsvp', (select jsonb_build_object(
        'asistira', r.asistira, 'asistentes', r.asistentes, 'roster', r.roster,
        'email', r.email, 'comentarios', r.comentarios, 'actualizado_en', r.actualizado_en)
      from public.rsvps r where r.invitado_id = v.id)
  );
$fn$;
revoke all on function public.invitado_json_sin_token(public.invitados) from public, anon, authenticated;

-- 2) Aperturas: un índice único (invitado + minuto) frena el spam del
--    contador. El chequeo "¿hay una reciente?" no sirve contra inserciones
--    en paralelo; solo un índice que la base haga cumplir por fila lo logra.
alter table public.aperturas add column if not exists bloque_min bigint;

create or replace function public.aperturas_set_bloque()
returns trigger language plpgsql set search_path = public as $fn$
begin
  new.bloque_min := floor(extract(epoch from coalesce(new.abierto_en, now())) / 60)::bigint;
  return new;
end;
$fn$;
drop trigger if exists trg_aperturas_bloque on public.aperturas;
create trigger trg_aperturas_bloque before insert on public.aperturas
  for each row execute function public.aperturas_set_bloque();

update public.aperturas set bloque_min = floor(extract(epoch from abierto_en)/60)::bigint where bloque_min is null;
delete from public.aperturas a using public.aperturas b
  where a.invitado_id = b.invitado_id and a.bloque_min = b.bloque_min and a.id > b.id;
create unique index if not exists idx_aperturas_una_por_bloque
  on public.aperturas (invitado_id, bloque_min);

-- cargar_invitado: sin token + apertura idempotente por minuto.
create or replace function public.cargar_invitado(p_id text, p_user_agent text default null)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare v public.invitados;
begin
  select * into v from public.invitados where id = p_id;
  if not found then return null; end if;
  insert into public.aperturas (invitado_id, origen, user_agent)
  values (v.id, 'buscador', left(p_user_agent,400))
  on conflict (invitado_id, bloque_min) do nothing;
  return public.invitado_json_sin_token(v);
end;
$fn$;
revoke all on function public.cargar_invitado(text, text) from public;
grant execute on function public.cargar_invitado(text, text) to anon, authenticated;

-- abrir_invitacion: igual, apertura idempotente por minuto.
create or replace function public.abrir_invitacion(
  p_token text, p_user_agent text default null,
  p_referrer text default null, p_registrar boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $fn$
declare v public.invitados;
begin
  if p_token is null or length(p_token) < 6 then return null; end if;
  select * into v from public.invitados where token = p_token;
  if not found then return null; end if;
  if p_registrar then
    insert into public.aperturas (invitado_id, origen, user_agent, referrer)
    values (v.id, 'link', left(p_user_agent,400), left(p_referrer,400))
    on conflict (invitado_id, bloque_min) do nothing;
  end if;
  return public.invitado_json(v);
end;
$fn$;

-- 3) Clave admin: se registran los intentos fallidos y el castigo crece con
--    la ráfaga. La clave ya es fortísima (~98 bits); esto es defensa extra.
create table if not exists public.admin_intentos (
  id bigserial primary key, cuando timestamptz not null default now(), ip_hash text);
alter table public.admin_intentos enable row level security;
revoke all on public.admin_intentos from anon, authenticated;

create or replace function public.admin_verificar(p_clave text)
returns void language plpgsql security definer set search_path = public, extensions as $fn$
declare v_hash text; v_recientes int;
begin
  select valor into v_hash from public.config where clave = 'admin_hash';
  if v_hash is null or extensions.crypt(coalesce(p_clave,''), v_hash) <> v_hash then
    insert into public.admin_intentos (cuando) values (now());
    select count(*) into v_recientes from public.admin_intentos where cuando > now() - interval '1 minute';
    perform pg_sleep(least(0.5 + v_recientes * 0.4, 4));
    raise exception 'Clave incorrecta' using errcode = '28000';
  end if;
end;
$fn$;

-- 4) search_path fijo en las funciones auxiliares (cierra el WARN del linter).
alter function public.norm(text) set search_path = public;
alter function public.invitado_json(public.invitados) set search_path = public;
