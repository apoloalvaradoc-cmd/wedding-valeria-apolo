-- 015 · Agregar invitados y marcar asistencia desde el listado
--
-- Dos cosas que hasta ahora obligaban a salir de la consola:
--
--   · Agregar a alguien nuevo. Solo se podía metiéndolo al Google Sheet y
--     corriendo generar_lista_sql.mjs --actualizar. Para un "invitemos
--     también a fulano" es demasiado. El id sigue la misma serie (INV###),
--     así que si después también lo agregan al Sheet, el modo actualizar lo
--     empareja por teléfono en vez de duplicarlo.
--
--   · Marcar "sí van" o "ya no van" sin abrir la ficha del panel. La mayoría
--     contesta por WhatsApp, y el listado es donde se está cuando contestan.

-- ------------------------------------------------------------ crear invitado

create or replace function public.admin_crear_invitado(
  p_clave              text,
  p_nombre             text,
  p_cupos              integer default 1,
  p_telefono           text    default null,
  p_telefono_alt       text    default null,
  p_nombre_acompanante text    default null,
  p_tipo               text    default 'otro',
  p_notas              text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre text := nullif(btrim(coalesce(p_nombre, '')), '');
  v_acomp  text := nullif(btrim(coalesce(p_nombre_acompanante, '')), '');
  v_tipo   text := coalesce(nullif(btrim(coalesce(p_tipo, '')), ''), 'otro');
  v_num    integer;
  v_id     text;
begin
  perform public.admin_verificar(p_clave);

  if v_nombre is null then
    raise exception 'Falta el nombre' using errcode = '22023';
  end if;
  if length(v_nombre) > 120 or length(coalesce(v_acomp, '')) > 120 then
    raise exception 'El nombre es demasiado largo' using errcode = '22023';
  end if;
  if p_cupos is null or p_cupos < 1 or p_cupos > 20 then
    raise exception 'Los cupos van de 1 a 20' using errcode = '22023';
  end if;
  if v_tipo not in ('familia', 'cortejo', 'amigo', 'amigos_papa', 'amigos_mama', 'otro') then
    raise exception 'Tipo no válido: %', v_tipo using errcode = '22023';
  end if;

  -- Dos altas al mismo tiempo (los dos novios con la consola abierta)
  -- leerían el mismo máximo. El candado las pone en fila.
  lock table public.invitados in share row exclusive mode;

  select coalesce(max(substring(id from '^INV(\d+)$')::integer), 0) + 1
    into v_num
    from public.invitados;
  v_id := 'INV' || lpad(v_num::text, 3, '0');

  insert into public.invitados
    (id, nombre, acompanantes, cupos, grupo, tipo, codigo,
     telefono, telefono_alt, nombre_acompanante, notas, token)
  values
    (v_id, v_nombre,
     case when v_acomp is null then '{}'::text[] else array[v_acomp] end,
     p_cupos, null, v_tipo, 'VA' || lpad(v_num::text, 3, '0'),
     nullif(btrim(coalesce(p_telefono, '')), ''),
     nullif(btrim(coalesce(p_telefono_alt, '')), ''),
     v_acomp,
     nullif(btrim(coalesce(p_notas, '')), ''),
     substr(md5(v_id || gen_random_uuid()::text), 1, 12));

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

revoke all on function public.admin_crear_invitado(text, text, integer, text, text, text, text, text) from public;
grant execute on function public.admin_crear_invitado(text, text, integer, text, text, text, text, text) to anon, authenticated;

-- ------------------------------------------------------- marcar asistencia
--
-- p_asistira: true = van · false = ya no van · null = volver a pendiente.
-- p_personas: cuántos van (solo con true; si no viene, todos los cupos).
--
-- El listado no tiene los nombres de quienes confirmaron, solo cuántos, así
-- que los nombres se arman aquí: primero los que ya estaban confirmados (con
-- sus restricciones, que no se pierden al subir o bajar la cuenta), después
-- los que conocemos de la invitación, y al final un marcador.

create or replace function public.admin_marcar_asistencia(
  p_clave       text,
  p_invitado_id text,
  p_asistira    boolean,
  p_personas    integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v       public.invitados;
  r       public.rsvps;
  v_n     integer;
  v_lista jsonb := '[]'::jsonb;
  v_usados text[] := '{}';
  v_cand  text;
  a       jsonb;
begin
  perform public.admin_verificar(p_clave);

  select * into v from public.invitados where id = p_invitado_id;
  if not found then
    raise exception 'Esa invitación no existe' using errcode = '22023';
  end if;

  if p_asistira is null then
    delete from public.rsvps where invitado_id = v.id;
    return jsonb_build_object('ok', true, 'asistira', null, 'asistentes', 0);
  end if;

  if p_asistira is false then
    insert into public.rsvps (invitado_id, nombre_titular, asistira, asistentes, origen, actualizado_en)
    values (v.id, v.nombre, false, '[]'::jsonb, 'admin', now())
    on conflict (invitado_id) do update set
      asistira = false, asistentes = '[]'::jsonb, origen = 'admin', actualizado_en = now();
    return jsonb_build_object('ok', true, 'asistira', false, 'asistentes', 0);
  end if;

  v_n := coalesce(p_personas, v.cupos);
  if v_n < 1 or v_n > v.cupos then
    raise exception 'Pueden ir de 1 a % personas', v.cupos using errcode = '22023';
  end if;

  select * into r from public.rsvps where invitado_id = v.id;

  if r.asistira is true then
    for a in select * from jsonb_array_elements(r.asistentes) loop
      exit when jsonb_array_length(v_lista) >= v_n;
      v_lista  := v_lista || jsonb_build_array(a);
      v_usados := v_usados || lower(btrim(coalesce(a->>'nombre', '')));
    end loop;
  end if;

  for v_cand in
    select x from unnest(array[v.nombre, v.nombre_acompanante] || coalesce(v.acompanantes, '{}')) x
  loop
    exit when jsonb_array_length(v_lista) >= v_n;
    continue when nullif(btrim(coalesce(v_cand, '')), '') is null;
    continue when lower(btrim(v_cand)) = any(v_usados);
    v_lista  := v_lista || jsonb_build_array(jsonb_build_object('nombre', btrim(v_cand), 'restriccion', ''));
    v_usados := v_usados || lower(btrim(v_cand));
  end loop;

  while jsonb_array_length(v_lista) < v_n loop
    v_lista := v_lista || jsonb_build_array(jsonb_build_object(
      'nombre', 'Acompañante de ' || v.nombre, 'restriccion', ''));
  end loop;

  insert into public.rsvps (invitado_id, nombre_titular, asistira, asistentes, origen, actualizado_en)
  values (v.id, v.nombre, true, v_lista, 'admin', now())
  on conflict (invitado_id) do update set
    asistira = true, asistentes = excluded.asistentes, origen = 'admin', actualizado_en = now();

  return jsonb_build_object('ok', true, 'asistira', true, 'asistentes', v_n);
end;
$$;

revoke all on function public.admin_marcar_asistencia(text, text, boolean, integer) from public;
grant execute on function public.admin_marcar_asistencia(text, text, boolean, integer) to anon, authenticated;
