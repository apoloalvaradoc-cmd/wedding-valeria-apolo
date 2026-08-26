-- ============================================================
-- wedding-valeria-apolo · migración 003
-- Funciones RPC: única puerta de entrada desde el navegador.
--
-- Regla que siguen todas: nunca devuelven `telefono` ni `email`
-- del invitado al frontend público. Esos datos solo salen por
-- admin_datos(), y solo con la clave correcta.
-- ============================================================

-- ------------------------------------------------------------
-- Helper interno: arma el JSON público de un invitado.
-- Incluye el token porque el frontend lo necesita para guardar
-- el RSVP, pero deja fuera teléfono, correo y notas.
-- ------------------------------------------------------------
create or replace function public.invitado_json(v public.invitados)
returns jsonb
language sql
stable
as $fn$
  select jsonb_build_object(
    'id',           v.id,
    'token',        v.token,
    'nombre',       v.nombre,
    'acompanantes', to_jsonb(coalesce(v.acompanantes, '{}'::text[])),
    'cupos',        v.cupos,
    'grupo',        v.grupo,
    'mesa',         v.mesa,
    'tipo',         v.tipo,
    'rsvp', (
      select jsonb_build_object(
        'asistira',       r.asistira,
        'asistentes',     r.asistentes,
        'roster',         r.roster,
        'email',          r.email,
        'comentarios',    r.comentarios,
        'actualizado_en', r.actualizado_en
      )
      from public.rsvps r where r.invitado_id = v.id
    )
  );
$fn$;

-- ------------------------------------------------------------
-- abrir_invitacion(token) · camino del link personalizado.
-- Registra la apertura y devuelve los datos para precargar.
-- ------------------------------------------------------------
create or replace function public.abrir_invitacion(
  p_token      text,
  p_user_agent text default null,
  p_referrer   text default null,
  p_registrar  boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare v public.invitados;
begin
  if p_token is null or length(p_token) < 6 then
    return null;
  end if;

  select * into v from public.invitados where token = p_token;
  if not found then
    return null;
  end if;

  if p_registrar then
    insert into public.aperturas (invitado_id, origen, user_agent, referrer)
    values (v.id, 'link', left(p_user_agent, 400), left(p_referrer, 400));
  end if;

  return public.invitado_json(v);
end;
$fn$;

-- ------------------------------------------------------------
-- buscar_invitado(q) · respaldo para quien perdió su link.
-- Mínimo 3 caracteres y máximo 8 resultados: no permite
-- descargar la lista completa a fuerza de consultas vacías.
-- ------------------------------------------------------------
create or replace function public.buscar_invitado(q text)
returns table (id text, nombre text, cupos integer)
language sql
security definer
set search_path = public
as $fn$
  select i.id, i.nombre, i.cupos
  from public.invitados i
  where length(coalesce(btrim(q), '')) >= 3
    and public.norm(i.nombre) like '%' || public.norm(btrim(q)) || '%'
  order by i.nombre
  limit 8;
$fn$;

-- ------------------------------------------------------------
-- cargar_invitado(id) · segundo paso del buscador.
-- También cuenta como apertura, marcada con origen 'buscador'.
-- ------------------------------------------------------------
create or replace function public.cargar_invitado(
  p_id         text,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare v public.invitados;
begin
  select * into v from public.invitados where id = p_id;
  if not found then
    return null;
  end if;

  insert into public.aperturas (invitado_id, origen, user_agent)
  values (v.id, 'buscador', left(p_user_agent, 400));

  return public.invitado_json(v);
end;
$fn$;

-- ------------------------------------------------------------
-- guardar_rsvp(token, ...) · única vía de escritura.
-- Valida el token y que no se confirmen más personas que cupos.
-- ------------------------------------------------------------
create or replace function public.guardar_rsvp(
  p_token       text,
  p_asistira    boolean,
  p_asistentes  jsonb default '[]'::jsonb,
  p_roster      jsonb default null,
  p_email       text  default null,
  p_comentarios text  default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v   public.invitados;
  v_n integer;
begin
  select * into v from public.invitados where token = p_token;
  if not found then
    raise exception 'Token invalido' using errcode = '22023';
  end if;

  v_n := jsonb_array_length(coalesce(p_asistentes, '[]'::jsonb));
  if v_n > v.cupos then
    raise exception 'Se confirmaron % personas pero solo hay % cupos', v_n, v.cupos
      using errcode = '23514';
  end if;

  insert into public.rsvps (
    invitado_id, nombre_titular, asistira, asistentes, roster,
    email, comentarios, actualizado_en
  )
  values (
    v.id, v.nombre, p_asistira,
    coalesce(p_asistentes, '[]'::jsonb), p_roster,
    nullif(btrim(coalesce(p_email, '')), ''),
    nullif(btrim(coalesce(p_comentarios, '')), ''),
    now()
  )
  on conflict (invitado_id) do update set
    asistira       = excluded.asistira,
    asistentes     = excluded.asistentes,
    roster         = excluded.roster,
    email          = excluded.email,
    comentarios    = excluded.comentarios,
    actualizado_en = now();

  return jsonb_build_object('ok', true, 'actualizado_en', now());
end;
$fn$;

-- ------------------------------------------------------------
-- admin_datos(clave) · tablero completo, incluye PII.
-- La clave se compara contra un hash bcrypt guardado en `config`,
-- así que ya no viaja dentro del HTML público.
-- ------------------------------------------------------------
create or replace function public.admin_datos(p_clave text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare v_hash text;
begin
  select valor into v_hash from public.config where clave = 'admin_hash';

  if v_hash is null or extensions.crypt(coalesce(p_clave, ''), v_hash) <> v_hash then
    perform pg_sleep(0.5);   -- frena el ensayo y error
    raise exception 'Clave incorrecta' using errcode = '28000';
  end if;

  return jsonb_build_object(
    'invitados', (
      select coalesce(jsonb_agg(to_jsonb(i) - 'token' order by i.nombre), '[]'::jsonb)
      from public.invitados i
    ),
    'rsvps', (
      select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) from public.rsvps r
    ),
    'aperturas', (
      select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb) from (
        select invitado_id,
               count(*)        as veces,
               min(abierto_en) as primera,
               max(abierto_en) as ultima
        from public.aperturas group by invitado_id
      ) a
    ),
    'envios', (
      select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb) from (
        select invitado_id,
               count(*) filter (where tipo = 'invitacion')   as invitaciones,
               count(*) filter (where tipo = 'recordatorio') as recordatorios,
               max(enviado_en) as ultimo
        from public.envios group by invitado_id
      ) e
    )
  );
end;
$fn$;

-- ------------------------------------------------------------
-- Permisos: solo estas cinco funciones son alcanzables desde
-- el navegador. invitado_json queda interna.
-- ------------------------------------------------------------
revoke all on function public.invitado_json(public.invitados) from public, anon, authenticated;

revoke all on function public.abrir_invitacion(text, text, text, boolean)           from public;
revoke all on function public.buscar_invitado(text)                                 from public;
revoke all on function public.cargar_invitado(text, text)                            from public;
revoke all on function public.guardar_rsvp(text, boolean, jsonb, jsonb, text, text)  from public;
revoke all on function public.admin_datos(text)                                      from public;

grant execute on function public.abrir_invitacion(text, text, text, boolean)          to anon, authenticated;
grant execute on function public.buscar_invitado(text)                                to anon, authenticated;
grant execute on function public.cargar_invitado(text, text)                          to anon, authenticated;
grant execute on function public.guardar_rsvp(text, boolean, jsonb, jsonb, text, text) to anon, authenticated;
grant execute on function public.admin_datos(text)                                     to anon, authenticated;
