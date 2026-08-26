-- ============================================================
-- wedding-valeria-apolo · migración 006
-- Gestión de confirmaciones desde el panel de los novios.
--
-- Buena parte de los invitados va a contestar por WhatsApp en vez de
-- llenar el formulario. Estas funciones permiten registrar esa
-- respuesta a mano, marcada con origen='admin' para poder distinguirla
-- después de la que llenó el invitado.
-- ============================================================

alter table public.rsvps
  add column if not exists origen text not null default 'invitado';

-- ------------------------------------------------------------
-- admin_datos · payload completo del panel.
-- Incluye a los asistentes nombre por nombre (para la lista de la
-- finca), las aperturas con su origen, y los envíos por destino.
-- El token va incluido: el panel está detrás de la misma clave que
-- la consola, y permite copiar el link personalizado de alguien
-- desde su ficha. El buscador público sigue sin exponerlo.
-- ------------------------------------------------------------
create or replace function public.admin_datos(p_clave text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
begin
  perform public.admin_verificar(p_clave);

  return jsonb_build_object(
    'invitados', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',                 i.id,
        'nombre',             i.nombre,
        'token',              i.token,
        'acompanantes',       to_jsonb(coalesce(i.acompanantes, '{}'::text[])),
        'cupos',              i.cupos,
        'grupo',              i.grupo,
        'mesa',               i.mesa,
        'tipo',               i.tipo,
        'codigo',             i.codigo,
        'telefono',           i.telefono,
        'telefono_alt',       i.telefono_alt,
        'nombre_acompanante', i.nombre_acompanante
      ) order by i.nombre), '[]'::jsonb)
      from public.invitados i
    ),
    'rsvps', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'invitado_id',    r.invitado_id,
        'nombre_titular', r.nombre_titular,
        'asistira',       r.asistira,
        'asistentes',     r.asistentes,
        'roster',         r.roster,
        'email',          r.email,
        'comentarios',    r.comentarios,
        'origen',         r.origen,
        'actualizado_en', r.actualizado_en
      )), '[]'::jsonb)
      from public.rsvps r
    ),
    'aperturas', (
      select coalesce(jsonb_agg(to_jsonb(a)), '[]'::jsonb)
      from (
        select invitado_id,
               count(*)                                    as veces,
               count(*) filter (where origen = 'link')     as por_link,
               count(*) filter (where origen = 'buscador') as por_buscador,
               min(abierto_en)                             as primera,
               max(abierto_en)                             as ultima
        from public.aperturas group by invitado_id
      ) a
    ),
    'envios', (
      select coalesce(jsonb_agg(to_jsonb(e)), '[]'::jsonb)
      from (
        select invitado_id,
               count(*) filter (where tipo = 'invitacion')     as invitaciones,
               count(*) filter (where tipo = 'recordatorio')   as recordatorios,
               count(*) filter (where destino = 'titular')     as a_titular,
               count(*) filter (where destino = 'acompanante') as a_acompanante,
               max(enviado_en) as ultimo
        from public.envios group by invitado_id
      ) e
    )
  );
end;
$fn$;

-- ------------------------------------------------------------
-- admin_guardar_rsvp · registrar a quien contestó por WhatsApp.
-- Misma validación de cupos que el formulario público.
-- ------------------------------------------------------------
create or replace function public.admin_guardar_rsvp(
  p_clave       text,
  p_invitado_id text,
  p_asistira    boolean,
  p_asistentes  jsonb default '[]'::jsonb,
  p_comentarios text default null,
  p_email       text default null
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
  perform public.admin_verificar(p_clave);

  select * into v from public.invitados where id = p_invitado_id;
  if not found then
    raise exception 'No existe el invitado %', p_invitado_id using errcode = '22023';
  end if;

  v_n := jsonb_array_length(coalesce(p_asistentes, '[]'::jsonb));
  if v_n > v.cupos then
    raise exception 'Se marcaron % personas pero solo hay % cupos', v_n, v.cupos
      using errcode = '23514';
  end if;

  insert into public.rsvps (
    invitado_id, nombre_titular, asistira, asistentes,
    email, comentarios, origen, actualizado_en
  )
  values (
    v.id, v.nombre, p_asistira, coalesce(p_asistentes, '[]'::jsonb),
    nullif(btrim(coalesce(p_email, '')), ''),
    nullif(btrim(coalesce(p_comentarios, '')), ''),
    'admin', now()
  )
  on conflict (invitado_id) do update set
    asistira       = excluded.asistira,
    asistentes     = excluded.asistentes,
    -- No pisamos con null lo que el invitado ya haya dejado.
    email          = coalesce(excluded.email, public.rsvps.email),
    comentarios    = coalesce(excluded.comentarios, public.rsvps.comentarios),
    origen         = 'admin',
    actualizado_en = now();

  return jsonb_build_object('ok', true);
end;
$fn$;

-- ------------------------------------------------------------
-- admin_borrar_rsvp · deshacer una confirmación (vuelve a pendiente).
-- ------------------------------------------------------------
create or replace function public.admin_borrar_rsvp(
  p_clave       text,
  p_invitado_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
begin
  perform public.admin_verificar(p_clave);
  delete from public.rsvps where invitado_id = p_invitado_id;
  return jsonb_build_object('ok', found);
end;
$fn$;

-- ------------------------------------------------------------
-- admin_set_mesa · asignar mesa desde la ficha del invitado.
-- ------------------------------------------------------------
create or replace function public.admin_set_mesa(
  p_clave       text,
  p_invitado_id text,
  p_mesa        integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
begin
  perform public.admin_verificar(p_clave);
  update public.invitados set mesa = p_mesa where id = p_invitado_id;
  return jsonb_build_object('ok', found);
end;
$fn$;

revoke all on function public.admin_guardar_rsvp(text, text, boolean, jsonb, text, text) from public;
revoke all on function public.admin_borrar_rsvp(text, text)                              from public;
revoke all on function public.admin_set_mesa(text, text, integer)                        from public;

grant execute on function public.admin_guardar_rsvp(text, text, boolean, jsonb, text, text) to anon, authenticated;
grant execute on function public.admin_borrar_rsvp(text, text)                              to anon, authenticated;
grant execute on function public.admin_set_mesa(text, text, integer)                        to anon, authenticated;
