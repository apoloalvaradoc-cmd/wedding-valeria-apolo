-- 014 · Corregir nombres desde el listado
--
-- Mismo caso que los cupos: los nombres vinieron del Google Sheet con
-- erratas y tratamientos raros, y arreglar uno obligaba a recargar la lista
-- entera, lo que regenera todos los tokens y deja inservibles los links ya
-- enviados. Esto cambia un nombre suelto y nada más.
--
-- Sigue la misma forma que admin_set_telefono: un solo campo por llamada,
-- validado contra una lista blanca.
--
-- No toca rsvps.nombre_titular a propósito: eso es lo que el invitado
-- escribió al confirmar, y es un registro de lo que pasó, no un dato que
-- nosotros debamos corregir por él.

create or replace function public.admin_set_nombre(
  p_clave       text,
  p_invitado_id text,
  p_nombre      text,
  p_campo       text default 'nombre'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_val text;
begin
  perform public.admin_verificar(p_clave);

  if p_campo not in ('nombre', 'nombre_acompanante') then
    raise exception 'Campo no válido: %', p_campo using errcode = '22023';
  end if;

  v_val := nullif(btrim(coalesce(p_nombre, '')), '');

  if length(coalesce(v_val, '')) > 120 then
    raise exception 'El nombre es demasiado largo' using errcode = '22023';
  end if;

  if p_campo = 'nombre' then
    -- El titular sí es obligatorio: es como se identifica la invitación en
    -- todas las pantallas y en el saludo del mensaje.
    if v_val is null then
      raise exception 'La invitación no puede quedarse sin nombre' using errcode = '22023';
    end if;
    update public.invitados set nombre = v_val where id = p_invitado_id;
  else
    update public.invitados set nombre_acompanante = v_val where id = p_invitado_id;
  end if;

  if not found then
    raise exception 'Esa invitación no existe' using errcode = '22023';
  end if;

  return jsonb_build_object('ok', true, 'valor', v_val);
end;
$$;

revoke all on function public.admin_set_nombre(text, text, text, text) from public;
grant execute on function public.admin_set_nombre(text, text, text, text) to anon, authenticated;
