-- 012 · Mesas redondas, asientos y notas del listado
--
-- Hasta aquí la mesa era un simple entero en invitados.mesa: servía para
-- apuntar algo, pero no para armar el salón. Aquí se separa en dos tablas:
--
--   mesas    · cada mesa redonda, con su capacidad y su posición en el croquis
--   asientos · una fila por PERSONA sentada, no por invitación
--
-- Sentar por persona es lo que permite partir una familia de seis en dos
-- mesas, que es justo lo que siempre termina pasando. La persona se
-- identifica por (invitado_id, persona_idx): el índice dentro de la lista
-- de asistentes que confirmó, o dentro de los cupos si todavía no confirma.
-- Así el croquis se puede empezar antes de tener todas las confirmaciones y
-- se va afinando solo conforme la gente responde.
--
-- invitados.mesa se mantiene sincronizada por trigger con la mesa más baja
-- de la invitación, para que los exports que ya existían sigan sirviendo.

-- ---------------------------------------------------------------- tablas

create table if not exists public.mesas (
  id         smallint primary key,
  nombre     text,
  capacidad  smallint not null default 10 check (capacidad between 1 and 24),
  -- Posición en el croquis, en fracción del lienzo (0..1). Sin unidades
  -- absolutas: el lienzo cambia de tamaño según la pantalla.
  pos_x      real not null default 0.5 check (pos_x between 0 and 1),
  pos_y      real not null default 0.5 check (pos_y between 0 and 1),
  creado_en  timestamptz not null default now()
);

create table if not exists public.asientos (
  invitado_id    text     not null references public.invitados(id) on delete cascade,
  persona_idx    smallint not null check (persona_idx >= 0),
  mesa_id        smallint not null references public.mesas(id) on delete cascade,
  actualizado_en timestamptz not null default now(),
  primary key (invitado_id, persona_idx)
);

create index if not exists asientos_mesa_idx on public.asientos (mesa_id);

-- Igual que el resto: RLS encendido y sin políticas. Nadie toca las tablas
-- de frente; todo entra por las funciones de abajo, que piden la clave.
alter table public.mesas    enable row level security;
alter table public.asientos enable row level security;
revoke all on public.mesas    from anon, authenticated;
revoke all on public.asientos from anon, authenticated;

-- ------------------------------------------------- cuántas personas caben

-- Cuántas personas hay realmente que sentar en una invitación:
--   confirmó que no  → 0
--   confirmó que sí  → las que apuntó (al menos una)
--   todavía no sabe  → sus cupos, para poder ir armando el salón igual
create or replace function public.mesas_personas(p_invitado_id text)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select case
           when r.asistira is false then 0
           when r.asistira is true
             then greatest(jsonb_array_length(coalesce(r.asistentes, '[]'::jsonb)), 1)
           else i.cupos
         end
  from public.invitados i
  left join public.rsvps r on r.invitado_id = i.id
  where i.id = p_invitado_id;
$$;

-- ------------------------------------------- invitados.mesa siempre al día

create or replace function public.trg_asientos_sync_mesa()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text := coalesce(new.invitado_id, old.invitado_id);
begin
  update public.invitados
     set mesa = (select min(mesa_id) from public.asientos where invitado_id = v_id)
   where id = v_id;
  return null;
end;
$$;

drop trigger if exists asientos_sync_mesa on public.asientos;
create trigger asientos_sync_mesa
after insert or update or delete on public.asientos
for each row execute function public.trg_asientos_sync_mesa();

-- ------------------------------------------------------------------ RPCs

-- Todo lo que la página de mesas necesita, en una sola llamada.
create or replace function public.admin_mesas_datos(p_clave text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_verificar(p_clave);

  return jsonb_build_object(
    'mesas', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id',        m.id,
               'nombre',    m.nombre,
               'capacidad', m.capacidad,
               'pos_x',     m.pos_x,
               'pos_y',     m.pos_y
             ) order by m.id), '[]'::jsonb)
      from public.mesas m
    ),
    'invitados', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id',                 i.id,
               'nombre',             i.nombre,
               'grupo',              i.grupo,
               'tipo',               i.tipo,
               'cupos',              i.cupos,
               'notas',              i.notas,
               'nombre_acompanante', i.nombre_acompanante,
               'acompanantes',       to_jsonb(coalesce(i.acompanantes, '{}'::text[])),
               'asistira',           r.asistira,
               'asistentes',         coalesce(r.asistentes, '[]'::jsonb)
             ) order by i.nombre), '[]'::jsonb)
      from public.invitados i
      left join public.rsvps r on r.invitado_id = i.id
    ),
    'asientos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'invitado_id', a.invitado_id,
               'persona_idx', a.persona_idx,
               'mesa_id',     a.mesa_id
             )), '[]'::jsonb)
      from public.asientos a
    )
  );
end;
$$;

-- Crear o editar una mesa. Con p_id nulo agrega la siguiente en número.
create or replace function public.admin_mesa_guardar(
  p_clave     text,
  p_id        integer default null,
  p_nombre    text    default null,
  p_capacidad integer default null,
  p_pos_x     real    default null,
  p_pos_y     real    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id smallint;
begin
  perform public.admin_verificar(p_clave);

  if p_id is null then
    select coalesce(max(id), 0) + 1 into v_id from public.mesas;
    if v_id > 200 then
      raise exception 'Demasiadas mesas' using errcode = '22023';
    end if;
    insert into public.mesas (id, nombre, capacidad, pos_x, pos_y)
    values (v_id,
            nullif(btrim(coalesce(p_nombre, '')), ''),
            coalesce(p_capacidad, 10),
            coalesce(p_pos_x, 0.5),
            coalesce(p_pos_y, 0.5));
  else
    v_id := p_id;
    update public.mesas
       set nombre    = case when p_nombre    is null then nombre
                            else nullif(btrim(p_nombre), '') end,
           capacidad = coalesce(p_capacidad, capacidad),
           pos_x     = coalesce(p_pos_x, pos_x),
           pos_y     = coalesce(p_pos_y, pos_y)
     where id = v_id;
    if not found then
      raise exception 'La mesa % no existe', v_id using errcode = '22023';
    end if;
    -- Encoger una mesa no puede dejar gente sentada fuera de su capacidad.
    if (select count(*) from public.asientos where mesa_id = v_id)
       > (select capacidad from public.mesas where id = v_id) then
      raise exception 'La mesa % ya tiene más gente sentada que esa capacidad', v_id
        using errcode = '22023';
    end if;
  end if;

  return (select jsonb_build_object('id', id, 'nombre', nombre, 'capacidad', capacidad,
                                    'pos_x', pos_x, 'pos_y', pos_y)
          from public.mesas where id = v_id);
end;
$$;

create or replace function public.admin_mesa_borrar(p_clave text, p_id integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_verificar(p_clave);
  delete from public.mesas where id = p_id;   -- los asientos caen en cascada
  return jsonb_build_object('ok', true);
end;
$$;

-- Sentar a una persona. Con p_mesa_id nulo la levanta de la mesa.
create or replace function public.admin_sentar(
  p_clave       text,
  p_invitado_id text,
  p_persona_idx integer,
  p_mesa_id     integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_personas integer;
  v_cap      integer;
  v_ocupados integer;
begin
  perform public.admin_verificar(p_clave);

  if p_mesa_id is null then
    delete from public.asientos
     where invitado_id = p_invitado_id and persona_idx = p_persona_idx;
    return jsonb_build_object('ok', true, 'mesa_id', null);
  end if;

  v_personas := public.mesas_personas(p_invitado_id);
  if v_personas is null then
    raise exception 'Esa invitación no existe' using errcode = '22023';
  end if;
  if v_personas = 0 then
    raise exception 'Esa invitación ya dijo que no asiste' using errcode = '22023';
  end if;
  if p_persona_idx < 0 or p_persona_idx >= v_personas then
    raise exception 'Esa persona no existe dentro de la invitación' using errcode = '22023';
  end if;

  select capacidad into v_cap from public.mesas where id = p_mesa_id;
  if v_cap is null then
    raise exception 'La mesa % no existe', p_mesa_id using errcode = '22023';
  end if;

  select count(*) into v_ocupados
    from public.asientos
   where mesa_id = p_mesa_id
     and not (invitado_id = p_invitado_id and persona_idx = p_persona_idx);
  if v_ocupados >= v_cap then
    raise exception 'La mesa % ya está llena', p_mesa_id using errcode = '22023';
  end if;

  insert into public.asientos (invitado_id, persona_idx, mesa_id)
  values (p_invitado_id, p_persona_idx, p_mesa_id)
      on conflict (invitado_id, persona_idx)
      do update set mesa_id = excluded.mesa_id, actualizado_en = now();

  return jsonb_build_object('ok', true, 'mesa_id', p_mesa_id);
end;
$$;

-- Sentar de un jalón a toda la gente de una invitación que aún no tiene
-- lugar. Es lo normal: una familia se sienta junta y arrastrarlos de a uno
-- para 328 personas no lo hace nadie.
create or replace function public.admin_sentar_grupo(
  p_clave       text,
  p_invitado_id text,
  p_mesa_id     integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_personas integer;
  v_cap      integer;
  v_libres   integer;
  v_puestos  integer := 0;
  i          integer;
begin
  perform public.admin_verificar(p_clave);

  v_personas := public.mesas_personas(p_invitado_id);
  if coalesce(v_personas, 0) = 0 then
    raise exception 'Esa invitación no tiene gente que sentar' using errcode = '22023';
  end if;

  select capacidad into v_cap from public.mesas where id = p_mesa_id;
  if v_cap is null then
    raise exception 'La mesa % no existe', p_mesa_id using errcode = '22023';
  end if;

  select v_cap - count(*) into v_libres
    from public.asientos where mesa_id = p_mesa_id;

  for i in 0 .. v_personas - 1 loop
    exit when v_libres <= 0;
    -- Solo los que todavía no tienen lugar: mover a los ya sentados sería
    -- una sorpresa desagradable si la mesa se llena a la mitad.
    if not exists (select 1 from public.asientos
                    where invitado_id = p_invitado_id and persona_idx = i) then
      insert into public.asientos (invitado_id, persona_idx, mesa_id)
      values (p_invitado_id, i, p_mesa_id);
      v_libres  := v_libres - 1;
      v_puestos := v_puestos + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'sentados', v_puestos,
                            'faltaron', greatest(v_personas - v_puestos, 0));
end;
$$;

-- Levantar de la mesa a toda la invitación de un jalón.
create or replace function public.admin_levantar_grupo(p_clave text, p_invitado_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_verificar(p_clave);
  delete from public.asientos where invitado_id = p_invitado_id;
  return jsonb_build_object('ok', true);
end;
$$;

-- ------------------------------------------------------- notas del listado

-- La columna notas ya existía en invitados pero no había forma de escribirla
-- desde ninguna pantalla. Sirve para lo que no cabe en ningún otro campo:
-- "no come mariscos", "llega tarde", "confirmó por teléfono".
create or replace function public.admin_set_notas(
  p_clave       text,
  p_invitado_id text,
  p_notas       text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_verificar(p_clave);

  if length(coalesce(p_notas, '')) > 500 then
    raise exception 'La nota es demasiado larga' using errcode = '22023';
  end if;

  update public.invitados
     set notas = nullif(btrim(coalesce(p_notas, '')), '')
   where id = p_invitado_id;
  if not found then
    raise exception 'Esa invitación no existe' using errcode = '22023';
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

-- ------------------------------- el listado ahora también trae notas y mesa

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
        'acompanantes',       to_jsonb(coalesce(i.acompanantes, '{}'::text[])),
        'asistira',           r.asistira,
        'asistentes',         coalesce(jsonb_array_length(r.asistentes), 0),
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

-- ---------------------------------------------------------------- permisos

revoke all on function public.mesas_personas(text)                    from public, anon, authenticated;
revoke all on function public.trg_asientos_sync_mesa()                from public, anon, authenticated;

revoke all on function public.admin_mesas_datos(text)                                     from public;
revoke all on function public.admin_mesa_guardar(text, integer, text, integer, real, real) from public;
revoke all on function public.admin_mesa_borrar(text, integer)                             from public;
revoke all on function public.admin_sentar(text, text, integer, integer)                   from public;
revoke all on function public.admin_sentar_grupo(text, text, integer)                      from public;
revoke all on function public.admin_levantar_grupo(text, text)                             from public;
revoke all on function public.admin_set_notas(text, text, text)                            from public;
revoke all on function public.admin_lista_envio(text)                                      from public;

grant execute on function public.admin_mesas_datos(text)                                     to anon, authenticated;
grant execute on function public.admin_mesa_guardar(text, integer, text, integer, real, real) to anon, authenticated;
grant execute on function public.admin_mesa_borrar(text, integer)                             to anon, authenticated;
grant execute on function public.admin_sentar(text, text, integer, integer)                   to anon, authenticated;
grant execute on function public.admin_sentar_grupo(text, text, integer)                      to anon, authenticated;
grant execute on function public.admin_levantar_grupo(text, text)                             to anon, authenticated;
grant execute on function public.admin_set_notas(text, text, text)                            to anon, authenticated;
grant execute on function public.admin_lista_envio(text)                                      to anon, authenticated;
