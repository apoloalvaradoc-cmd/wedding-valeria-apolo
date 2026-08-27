-- ============================================================
-- wedding-valeria-apolo · migración 007
-- Editar los datos de la invitación desde su ficha en el panel.
-- Reemplaza a admin_set_mesa, que cubría solo una parte.
-- ============================================================

create or replace function public.admin_actualizar_invitado(
  p_clave              text,
  p_invitado_id        text,
  p_nombre             text default null,
  p_telefono           text default null,
  p_telefono_alt       text default null,
  p_nombre_acompanante text default null,
  p_mesa               integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare v_nombre text;
begin
  perform public.admin_verificar(p_clave);

  v_nombre := nullif(btrim(coalesce(p_nombre, '')), '');
  if v_nombre is null then
    raise exception 'El nombre no puede quedar vacío' using errcode = '23514';
  end if;

  update public.invitados set
    nombre             = v_nombre,
    telefono           = nullif(btrim(coalesce(p_telefono, '')), ''),
    telefono_alt       = nullif(btrim(coalesce(p_telefono_alt, '')), ''),
    nombre_acompanante = nullif(btrim(coalesce(p_nombre_acompanante, '')), ''),
    mesa               = p_mesa
  where id = p_invitado_id;

  if not found then
    raise exception 'No existe el invitado %', p_invitado_id using errcode = '22023';
  end if;

  -- El RSVP guarda el nombre del titular por separado; que no se desincronice.
  update public.rsvps set nombre_titular = v_nombre where invitado_id = p_invitado_id;

  return jsonb_build_object('ok', true);
end;
$fn$;

revoke all on function public.admin_actualizar_invitado(text, text, text, text, text, text, integer) from public;
grant execute on function public.admin_actualizar_invitado(text, text, text, text, text, text, integer) to anon, authenticated;
