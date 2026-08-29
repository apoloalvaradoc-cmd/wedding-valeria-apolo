-- 013 · Cambiar los cupos desde el listado
--
-- Los cupos venían del Google Sheet y solo se podían corregir volviendo a
-- cargar la lista entera, lo que además regenera los tokens. Para un ajuste
-- suelto ("al final van tres, no dos") eso no tiene sentido.
--
-- Dos cuidados:
--   · Si ya confirmaron más gente de la que cabría, no se deja bajar: primero
--     hay que corregir la confirmación desde el panel de la invitación.
--   · Si todavía no confirman, los cupos son los que reservan lugar en las
--     mesas, así que al bajarlos se sueltan los asientos que quedaron fuera.

create or replace function public.admin_set_cupos(
  p_clave       text,
  p_invitado_id text,
  p_cupos       integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asistira    boolean;
  v_confirmados integer;
begin
  perform public.admin_verificar(p_clave);

  if p_cupos is null or p_cupos < 1 or p_cupos > 20 then
    raise exception 'Los cupos van de 1 a 20' using errcode = '22023';
  end if;

  select r.asistira, jsonb_array_length(coalesce(r.asistentes, '[]'::jsonb))
    into v_asistira, v_confirmados
    from public.invitados i
    left join public.rsvps r on r.invitado_id = i.id
   where i.id = p_invitado_id;

  if not found then
    raise exception 'Esa invitación no existe' using errcode = '22023';
  end if;

  if v_asistira is true and coalesce(v_confirmados, 0) > p_cupos then
    raise exception 'Ya confirmaron % personas. Baja primero la confirmación desde el panel.',
      v_confirmados using errcode = '22023';
  end if;

  update public.invitados set cupos = p_cupos where id = p_invitado_id;

  -- Solo cuando no hay respuesta todavía: si ya confirmaron, los asientos
  -- siguen la lista de asistentes, no los cupos.
  if v_asistira is null then
    delete from public.asientos
     where invitado_id = p_invitado_id and persona_idx >= p_cupos;
  end if;

  return jsonb_build_object('ok', true, 'cupos', p_cupos);
end;
$$;

revoke all on function public.admin_set_cupos(text, text, integer) from public;
grant execute on function public.admin_set_cupos(text, text, integer) to anon, authenticated;
