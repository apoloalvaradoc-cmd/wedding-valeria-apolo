-- 011 · Los mensajes de los invitados en la consola de envío
--
-- Al confirmar, la gente escribe un recado ("comentarios") y a veces una
-- restricción alimenticia por persona. Todo eso quedaba únicamente en el panel
-- de administración de la invitación, así que desde la consola de envío no
-- había forma de leerlo. admin_lista_envio() ahora lo devuelve junto al resto.
--
-- Se agregan tres campos por invitado:
--   comentarios   · el recado tal cual lo escribieron
--   email         · el correo, que es opcional en el formulario
--   restricciones · "Nombre: restricción" de cada asistente que puso algo,
--                   ya unido en una sola línea para pintarlo directo

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
        'acompanantes',       to_jsonb(coalesce(i.acompanantes, '{}'::text[])),
        'asistira',           r.asistira,
        'asistentes',         coalesce(jsonb_array_length(r.asistentes), 0),
        'confirmado_en',      r.actualizado_en,
        -- nuevos: lo que escriben los invitados
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
$$;

revoke all on function public.admin_lista_envio(text) from public, anon, authenticated;
grant execute on function public.admin_lista_envio(text) to anon, authenticated;
