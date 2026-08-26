-- ============================================================
-- wedding-valeria-apolo · migración 005
-- Segundo teléfono por invitación (el del acompañante).
--
-- La invitación se manda al titular Y al acompañante, con el mismo
-- link — es una sola invitación. Por eso `envios` necesita saber a
-- cuál de los dos números ya se le escribió.
--
-- Reemplaza las tres funciones de la consola definidas en la 004.
-- ============================================================

alter table public.invitados
  add column if not exists telefono_alt       text,
  add column if not exists nombre_acompanante text;

alter table public.envios
  add column if not exists destino text not null default 'titular';

create index if not exists idx_envios_destino on public.envios (invitado_id, tipo, destino);

-- ------------------------------------------------------------
-- Lista para la consola: ahora con los dos números y los envíos
-- desglosados por destino.
-- ------------------------------------------------------------
create or replace function public.admin_lista_envio(p_clave text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
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
        'acompanantes',       to_jsonb(coalesce(i.acompanantes, '{}'::text[])),
        'asistira',           r.asistira,
        'asistentes',         coalesce(jsonb_array_length(r.asistentes), 0),
        'confirmado_en',      r.actualizado_en,
        'aperturas',          coalesce(ap.veces, 0),
        'ultima_apertura',    ap.ultima,
        'inv_titular',        coalesce(ev.inv_titular, 0),
        'inv_acomp',          coalesce(ev.inv_acomp, 0),
        'rec_titular',        coalesce(ev.rec_titular, 0),
        'rec_acomp',          coalesce(ev.rec_acomp, 0),
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
               count(*) filter (where tipo = 'invitacion'   and destino = 'titular')     as inv_titular,
               count(*) filter (where tipo = 'invitacion'   and destino = 'acompanante') as inv_acomp,
               count(*) filter (where tipo = 'recordatorio' and destino = 'titular')     as rec_titular,
               count(*) filter (where tipo = 'recordatorio' and destino = 'acompanante') as rec_acomp,
               max(enviado_en) as ultimo
        from public.envios group by invitado_id
      ) ev on ev.invitado_id = i.id
    ) s
  );
end;
$fn$;

-- ------------------------------------------------------------
-- Registrar envío, indicando a cuál de los dos números fue.
-- ------------------------------------------------------------
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

  if p_tipo not in ('invitacion', 'recordatorio') then
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

-- ------------------------------------------------------------
-- Corregir cualquiera de los dos números desde la consola.
-- ------------------------------------------------------------
create or replace function public.admin_set_telefono(
  p_clave       text,
  p_invitado_id text,
  p_telefono    text,
  p_campo       text default 'telefono'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare v_val text;
begin
  perform public.admin_verificar(p_clave);

  if p_campo not in ('telefono', 'telefono_alt') then
    raise exception 'Campo no válido: %', p_campo using errcode = '22023';
  end if;

  v_val := nullif(btrim(coalesce(p_telefono, '')), '');

  if p_campo = 'telefono' then
    update public.invitados set telefono = v_val where id = p_invitado_id;
  else
    update public.invitados set telefono_alt = v_val where id = p_invitado_id;
  end if;

  return jsonb_build_object('ok', found);
end;
$fn$;

revoke all on function public.admin_registrar_envio(text, text, text, text, text) from public;
revoke all on function public.admin_set_telefono(text, text, text, text)          from public;

grant execute on function public.admin_registrar_envio(text, text, text, text, text) to anon, authenticated;
grant execute on function public.admin_set_telefono(text, text, text, text)          to anon, authenticated;

-- Las firmas de la 004 quedan huérfanas: si se dejan, hay dos versiones
-- alcanzables desde el navegador y PostgREST puede elegir la equivocada.
drop function if exists public.admin_registrar_envio(text, text, text, text);
drop function if exists public.admin_set_telefono(text, text, text);
