-- ============================================================
-- wedding-valeria-apolo · migración 004
-- RPCs de la consola de envío (consola.html).
--
-- La consola no usa la llave de servicio: se autentica con la
-- misma clave de administración, validada contra el hash bcrypt
-- de la tabla `config`. Por eso se puede abrir desde el teléfono
-- sin exponer credenciales.
-- ============================================================

-- Verificación de clave reutilizable por las funciones de admin.
create or replace function public.admin_verificar(p_clave text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare v_hash text;
begin
  select valor into v_hash from public.config where clave = 'admin_hash';
  if v_hash is null or extensions.crypt(coalesce(p_clave, ''), v_hash) <> v_hash then
    perform pg_sleep(0.5);
    raise exception 'Clave incorrecta' using errcode = '28000';
  end if;
end;
$fn$;

-- Lista completa para la consola de envío: incluye teléfono y token,
-- que es justo lo que hace falta para armar el link de WhatsApp.
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
        'id',              i.id,
        'nombre',          i.nombre,
        'telefono',        i.telefono,
        'token',           i.token,
        'cupos',           i.cupos,
        'tipo',            i.tipo,
        'grupo',           i.grupo,
        'acompanantes',    to_jsonb(coalesce(i.acompanantes, '{}'::text[])),
        'asistira',        r.asistira,
        'asistentes',      coalesce(jsonb_array_length(r.asistentes), 0),
        'confirmado_en',   r.actualizado_en,
        'aperturas',       coalesce(ap.veces, 0),
        'ultima_apertura', ap.ultima,
        'invitaciones',    coalesce(ev.invitaciones, 0),
        'recordatorios',   coalesce(ev.recordatorios, 0),
        'ultimo_envio',    ev.ultimo
      ) as x
      from public.invitados i
      left join public.rsvps r on r.invitado_id = i.id
      left join (
        select invitado_id, count(*) as veces, max(abierto_en) as ultima
        from public.aperturas group by invitado_id
      ) ap on ap.invitado_id = i.id
      left join (
        select invitado_id,
               count(*) filter (where tipo = 'invitacion')   as invitaciones,
               count(*) filter (where tipo = 'recordatorio') as recordatorios,
               max(enviado_en) as ultimo
        from public.envios group by invitado_id
      ) ev on ev.invitado_id = i.id
    ) s
  );
end;
$fn$;

-- Marca un envío. Lo llama la consola justo después de abrir WhatsApp.
create or replace function public.admin_registrar_envio(
  p_clave       text,
  p_invitado_id text,
  p_tipo        text default 'invitacion',
  p_nota        text default null
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

  insert into public.envios (invitado_id, tipo, nota)
  values (p_invitado_id, p_tipo, p_nota);

  return jsonb_build_object('ok', true);
end;
$fn$;

-- Corregir un teléfono desde la consola, sin entrar al dashboard de Supabase.
create or replace function public.admin_set_telefono(
  p_clave       text,
  p_invitado_id text,
  p_telefono    text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
begin
  perform public.admin_verificar(p_clave);

  update public.invitados
  set telefono = nullif(btrim(coalesce(p_telefono, '')), '')
  where id = p_invitado_id;

  return jsonb_build_object('ok', found);
end;
$fn$;

revoke all on function public.admin_verificar(text)                         from public, anon, authenticated;
revoke all on function public.admin_lista_envio(text)                       from public;
revoke all on function public.admin_registrar_envio(text, text, text, text) from public;
revoke all on function public.admin_set_telefono(text, text, text)          from public;

grant execute on function public.admin_lista_envio(text)                       to anon, authenticated;
grant execute on function public.admin_registrar_envio(text, text, text, text) to anon, authenticated;
grant execute on function public.admin_set_telefono(text, text, text)          to anon, authenticated;

-- ------------------------------------------------------------
-- Pendiente al restaurar en un proyecto nuevo: sembrar la clave.
--   insert into public.config (clave, valor)
--   values ('admin_hash', extensions.crypt('TU_CLAVE', extensions.gen_salt('bf', 10)))
--   on conflict (clave) do update set valor = excluded.valor;
--
-- Y generar los tokens de quienes no lo tengan:
--   update public.invitados
--   set token = substr(md5(id || gen_random_uuid()::text), 1, 12)
--   where token is null;
-- ------------------------------------------------------------
