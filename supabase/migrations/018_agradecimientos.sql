-- ============================================================
-- 018 · Agradecimientos después de la boda
--
-- Después del 7 de noviembre toca dar las gracias por WhatsApp. Hay dos
-- mensajes: uno para quien nos dio regalo por las mesas de regalos
-- (Cemaco, Max, Siman) y otro para el resto, que lleva el link a la
-- página de gracias con el video y las opciones de regalo.
--
--   · invitados.regalo / regalo_nota: de dónde vino el regalo y qué fue.
--   · admin_set_regalo(): lo marca desde la consola.
--   · admin_registrar_envio(): acepta el tipo 'agradecimiento'.
--   · admin_lista_envio(): devuelve el regalo y los envíos de gracias.
-- ============================================================

alter table public.invitados add column if not exists regalo      text;
alter table public.invitados add column if not exists regalo_nota text;

do $$ begin
  alter table public.invitados
    add constraint invitados_regalo_chk
    check (regalo is null or regalo in ('cemaco', 'max', 'siman', 'efectivo', 'otro'));
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------ marcar regalo

create or replace function public.admin_set_regalo(
  p_clave       text,
  p_invitado_id text,
  p_regalo      text,
  p_nota        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare v_regalo text := nullif(btrim(lower(coalesce(p_regalo, ''))), '');
begin
  perform public.admin_verificar(p_clave);

  if v_regalo is not null and v_regalo not in ('cemaco', 'max', 'siman', 'efectivo', 'otro') then
    raise exception 'Regalo no válido: %', p_regalo using errcode = '22023';
  end if;

  update public.invitados
     set regalo      = v_regalo,
         regalo_nota = nullif(btrim(coalesce(p_nota, '')), '')
   where id = p_invitado_id;

  if not found then
    raise exception 'No existe la invitación %', p_invitado_id using errcode = 'P0002';
  end if;

  return jsonb_build_object('ok', true);
end;
$fn$;

-- ------------------------------------------------ envío de agradecimiento

create or replace function public.admin_registrar_envio(
  p_clave       text,
  p_invitado_id text,
  p_tipo        text default 'invitacion',
  p_nota        text default null,
  p_destino     text default 'titular'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
begin
  perform public.admin_verificar(p_clave);

  if p_tipo not in ('invitacion', 'recordatorio', 'agradecimiento') then
    raise exception 'Tipo de envío no válido: %', p_tipo using errcode = '22023';
  end if;
  if p_destino not in ('titular', 'acompanante') then
    raise exception 'Destino no válido: %', p_destino using errcode = '22023';
  end if;

  insert into public.envios (invitado_id, tipo, nota, destino)
  values (p_invitado_id, p_tipo, p_nota, p_destino);

  return jsonb_build_object('ok', true);
end;
$fn$;

-- ------------------------------------- el listado trae regalo y agradecimientos

create or replace function public.admin_lista_envio(p_clave text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_verificar(p_clave);

  return (
    select coalesce(jsonb_agg(x order by x->>'nombre'), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'id',                 i.id,
        'nombre',             i.nombre,
        'telefono',           i.telefono,
        'telefono_alt',       i.telefono_alt,
        'nombre_acompanante', i.nombre_acompanante,
        'token',              i.token,
        'cupos',              i.cupos,
        'tipo',               i.tipo,
        'grupo',              i.grupo,
        'notas',              i.notas,
        'mesa',               i.mesa,
        'regalo',             i.regalo,
        'regalo_nota',        i.regalo_nota,
        'acompanantes',       to_jsonb(coalesce(i.acompanantes, '{}'::text[])),
        'asistira',           r.asistira,
        'asistentes',         coalesce(jsonb_array_length(r.asistentes), 0),
        'nombres_asistentes', coalesce((
          select jsonb_agg(a->>'nombre')
          from jsonb_array_elements(coalesce(r.asistentes, '[]'::jsonb)) a
          where coalesce(btrim(a->>'nombre'), '') <> ''
        ), '[]'::jsonb),
        'confirmado_en',      r.actualizado_en,
        'comentarios',        r.comentarios,
        'email',              r.email,
        'restricciones',      (
          select string_agg(a->>'nombre' || ': ' || (a->>'restriccion'), ' · ')
          from jsonb_array_elements(coalesce(r.asistentes, '[]'::jsonb)) a
          where coalesce(btrim(a->>'restriccion'), '') <> ''
        ),
        'aperturas',          coalesce(ap.veces, 0),
        'ultima_apertura',    ap.ultima,
        'inv_titular',        coalesce(ev.inv_titular, 0),
        'inv_acomp',          coalesce(ev.inv_acomp, 0),
        'rec_titular',        coalesce(ev.rec_titular, 0),
        'rec_acomp',          coalesce(ev.rec_acomp, 0),
        'agr_titular',        coalesce(ev.agr_titular, 0),
        'agr_acomp',          coalesce(ev.agr_acomp, 0),
        'ultimo_envio',       ev.ultimo
      ) as x
      from public.invitados i
      left join public.rsvps r on r.invitado_id = i.id
      left join (
        select invitado_id, count(*) as veces, max(abierto_en) as ultima
        from public.aperturas group by invitado_id
      ) ap on ap.invitado_id = i.id
      left join (
        select invitado_id,
               count(*) filter (where tipo = 'invitacion'     and destino = 'titular')     as inv_titular,
               count(*) filter (where tipo = 'invitacion'     and destino = 'acompanante') as inv_acomp,
               count(*) filter (where tipo = 'recordatorio'   and destino = 'titular')     as rec_titular,
               count(*) filter (where tipo = 'recordatorio'   and destino = 'acompanante') as rec_acomp,
               count(*) filter (where tipo = 'agradecimiento' and destino = 'titular')     as agr_titular,
               count(*) filter (where tipo = 'agradecimiento' and destino = 'acompanante') as agr_acomp,
               max(enviado_en) filter (where tipo <> 'agradecimiento') as ultimo
        from public.envios group by invitado_id
      ) ev on ev.invitado_id = i.id
    ) s
  );
end;
$$;


-- ------------------------------------------------ regalos de las mesas
-- Quién compró qué en Cemaco / Max / Siman, copiado de cada tienda. Los
-- datos NO van en este archivo (el repo es público): se cargan aparte
-- desde el SQL Editor. La consola los usa para sugerir a quién marcar.

create table if not exists public.regalos_registro (
  id      bigserial primary key,
  tienda  text not null check (tienda in ('cemaco', 'max', 'siman')),
  quien   text not null,
  regalo  text,
  monto   numeric(10,2)
);
alter table public.regalos_registro enable row level security;
revoke all on public.regalos_registro from anon, authenticated;

create or replace function public.admin_regalos_registro(p_clave text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
begin
  perform public.admin_verificar(p_clave);
  return coalesce((
    select jsonb_agg(jsonb_build_object('tienda', tienda, 'quien', quien, 'regalo', regalo, 'monto', monto) order by quien)
    from public.regalos_registro
  ), '[]'::jsonb);
end;
$fn$;

-- ---------------------------------------------------------------- permisos

revoke all on function public.admin_set_regalo(text, text, text, text)            from public;
revoke all on function public.admin_registrar_envio(text, text, text, text, text) from public;
revoke all on function public.admin_lista_envio(text)                              from public;
revoke all on function public.admin_regalos_registro(text)                         from public;

grant execute on function public.admin_set_regalo(text, text, text, text)            to anon, authenticated;
grant execute on function public.admin_registrar_envio(text, text, text, text, text) to anon, authenticated;
grant execute on function public.admin_lista_envio(text)                              to anon, authenticated;
grant execute on function public.admin_regalos_registro(text)                         to anon, authenticated;
