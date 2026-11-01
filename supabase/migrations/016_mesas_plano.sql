-- 016 · El salón de verdad: forma de las mesas, lugares apartados y
--       pasar una mesa completa a otra
--
-- El plano del salón (LayoutValeriaApolo.pdf) trae 30 mesas de 10: la mitad
-- redondas y la mitad rectangulares, unas acostadas y otras paradas. Hasta
-- aquí todas se dibujaban redondas, así que el croquis no se parecía al
-- salón. Ahora cada mesa guarda su forma:
--
--   redonda · rect_h (rectangular acostada) · rect_v (rectangular parada)
--
-- Apartados: un lugar guardado con un nombre pero sin invitación detrás.
-- Sirve para la gente que ya tiene mesa en la lista de los novios pero que
-- todavía no sabemos a qué invitación corresponde ("Pepe Girón", "esposa de
-- Mauricio"). Ocupa lugar igual que una persona sentada, para que la mesa no
-- se llene por otro lado sin querer.
--
-- Intercambiar: pasar a toda la gente de una mesa a otra de un jalón. Si la
-- otra ya tiene gente, se cambian. Es lo que se usa cuando una mesa entera
-- queda en el lugar equivocado del salón.

-- ---------------------------------------------------------------- tablas

alter table public.mesas
  add column if not exists forma text not null default 'redonda';

alter table public.mesas drop constraint if exists mesas_forma_check;
alter table public.mesas
  add constraint mesas_forma_check check (forma in ('redonda', 'rect_h', 'rect_v'));

create table if not exists public.apartados (
  id        bigserial primary key,
  mesa_id   smallint not null references public.mesas(id) on delete cascade,
  nombre    text     not null check (length(btrim(nombre)) between 1 and 80),
  creado_en timestamptz not null default now()
);

create index if not exists apartados_mesa_idx on public.apartados (mesa_id);

alter table public.apartados enable row level security;
revoke all on public.apartados from anon, authenticated;

-- ------------------------------------------------ cuántos lugares van usados

-- Personas sentadas más lugares apartados. Es lo que se compara contra la
-- capacidad en todas partes.
create or replace function public.mesa_ocupados(p_mesa_id integer)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select (select count(*) from public.asientos  where mesa_id = p_mesa_id)::integer
       + (select count(*) from public.apartados where mesa_id = p_mesa_id)::integer;
$$;

-- ------------------------------------------------------------------ RPCs

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
               'forma',     m.forma,
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
    ),
    'apartados', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id',      p.id,
               'mesa_id', p.mesa_id,
               'nombre',  p.nombre
             ) order by p.id), '[]'::jsonb)
      from public.apartados p
    )
  );
end;
$$;

-- La firma cambia (entra p_forma), así que la vieja se tira para que no
-- queden dos versiones con el mismo nombre.
drop function if exists public.admin_mesa_guardar(text, integer, text, integer, real, real);

create or replace function public.admin_mesa_guardar(
  p_clave     text,
  p_id        integer default null,
  p_nombre    text    default null,
  p_capacidad integer default null,
  p_pos_x     real    default null,
  p_pos_y     real    default null,
  p_forma     text    default null
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

  if p_forma is not null and p_forma not in ('redonda', 'rect_h', 'rect_v') then
    raise exception 'Forma de mesa desconocida' using errcode = '22023';
  end if;

  if p_id is null then
    select coalesce(max(id), 0) + 1 into v_id from public.mesas;
    if v_id > 200 then
      raise exception 'Demasiadas mesas' using errcode = '22023';
    end if;
    insert into public.mesas (id, nombre, capacidad, forma, pos_x, pos_y)
    values (v_id,
            nullif(btrim(coalesce(p_nombre, '')), ''),
            coalesce(p_capacidad, 10),
            coalesce(p_forma, 'redonda'),
            coalesce(p_pos_x, 0.5),
            coalesce(p_pos_y, 0.5));
  else
    v_id := p_id;
    update public.mesas
       set nombre    = case when p_nombre    is null then nombre
                            else nullif(btrim(p_nombre), '') end,
           capacidad = coalesce(p_capacidad, capacidad),
           forma     = coalesce(p_forma, forma),
           pos_x     = coalesce(p_pos_x, pos_x),
           pos_y     = coalesce(p_pos_y, pos_y)
     where id = v_id;
    if not found then
      raise exception 'La mesa % no existe', v_id using errcode = '22023';
    end if;
    -- Encoger una mesa no puede dejar gente sentada fuera de su capacidad.
    if public.mesa_ocupados(v_id) > (select capacidad from public.mesas where id = v_id) then
      raise exception 'La mesa % ya tiene más gente que esa capacidad', v_id
        using errcode = '22023';
    end if;
  end if;

  return (select jsonb_build_object('id', id, 'nombre', nombre, 'capacidad', capacidad,
                                    'forma', forma, 'pos_x', pos_x, 'pos_y', pos_y)
          from public.mesas where id = v_id);
end;
$$;

-- Igual que en la 012; lo único que cambia es que los apartados ocupan lugar.
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

  -- Sin contar a la propia persona: moverla dentro de la misma mesa no
  -- debe chocar con la capacidad.
  v_ocupados := public.mesa_ocupados(p_mesa_id)
              - (select count(*) from public.asientos
                  where mesa_id = p_mesa_id
                    and invitado_id = p_invitado_id and persona_idx = p_persona_idx)::integer;
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

  v_libres := v_cap - public.mesa_ocupados(p_mesa_id);

  for i in 0 .. v_personas - 1 loop
    exit when v_libres <= 0;
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

-- Guardar un lugar con nombre en una mesa.
create or replace function public.admin_apartar(
  p_clave   text,
  p_mesa_id integer,
  p_nombre  text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cap    integer;
  v_nombre text := nullif(btrim(coalesce(p_nombre, '')), '');
  v_id     bigint;
begin
  perform public.admin_verificar(p_clave);

  if v_nombre is null then
    raise exception 'Falta el nombre' using errcode = '22023';
  end if;
  if length(v_nombre) > 80 then
    raise exception 'El nombre es demasiado largo' using errcode = '22023';
  end if;

  select capacidad into v_cap from public.mesas where id = p_mesa_id;
  if v_cap is null then
    raise exception 'La mesa % no existe', p_mesa_id using errcode = '22023';
  end if;
  if public.mesa_ocupados(p_mesa_id) >= v_cap then
    raise exception 'La mesa % ya está llena', p_mesa_id using errcode = '22023';
  end if;

  insert into public.apartados (mesa_id, nombre) values (p_mesa_id, v_nombre)
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'mesa_id', p_mesa_id, 'nombre', v_nombre);
end;
$$;

create or replace function public.admin_apartado_borrar(p_clave text, p_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.admin_verificar(p_clave);
  delete from public.apartados where id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;

-- Toda la gente de la mesa A pasa a la B y la de la B a la A. Con la B
-- vacía es simplemente mover. La forma no importa: solo que quepan.
create or replace function public.admin_mesa_intercambiar(
  p_clave text,
  p_a     integer,
  p_b     integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cap_a integer;
  v_cap_b integer;
  v_en_a  integer;
  v_en_b  integer;
begin
  perform public.admin_verificar(p_clave);

  if p_a = p_b then
    raise exception 'Elige otra mesa' using errcode = '22023';
  end if;

  select capacidad into v_cap_a from public.mesas where id = p_a;
  select capacidad into v_cap_b from public.mesas where id = p_b;
  if v_cap_a is null then
    raise exception 'La mesa % no existe', p_a using errcode = '22023';
  end if;
  if v_cap_b is null then
    raise exception 'La mesa % no existe', p_b using errcode = '22023';
  end if;

  v_en_a := public.mesa_ocupados(p_a);
  v_en_b := public.mesa_ocupados(p_b);
  if v_en_a > v_cap_b then
    raise exception 'La gente de la mesa % (%) no cabe en la mesa % (% lugares)',
      p_a, v_en_a, p_b, v_cap_b using errcode = '22023';
  end if;
  if v_en_b > v_cap_a then
    raise exception 'La gente de la mesa % (%) no cabe en la mesa % (% lugares)',
      p_b, v_en_b, p_a, v_cap_a using errcode = '22023';
  end if;

  update public.asientos
     set mesa_id = case when mesa_id = p_a then p_b else p_a end,
         actualizado_en = now()
   where mesa_id in (p_a, p_b);

  update public.apartados
     set mesa_id = case when mesa_id = p_a then p_b else p_a end
   where mesa_id in (p_a, p_b);

  return jsonb_build_object('ok', true, 'a', v_en_b, 'b', v_en_a);
end;
$$;

-- ---------------------------------------------------------------- permisos

revoke all on function public.mesa_ocupados(integer) from public, anon, authenticated;

revoke all on function public.admin_mesas_datos(text)                                           from public;
revoke all on function public.admin_mesa_guardar(text, integer, text, integer, real, real, text) from public;
revoke all on function public.admin_sentar(text, text, integer, integer)                         from public;
revoke all on function public.admin_sentar_grupo(text, text, integer)                            from public;
revoke all on function public.admin_apartar(text, integer, text)                                 from public;
revoke all on function public.admin_apartado_borrar(text, bigint)                                from public;
revoke all on function public.admin_mesa_intercambiar(text, integer, integer)                    from public;

grant execute on function public.admin_mesas_datos(text)                                           to anon, authenticated;
grant execute on function public.admin_mesa_guardar(text, integer, text, integer, real, real, text) to anon, authenticated;
grant execute on function public.admin_sentar(text, text, integer, integer)                         to anon, authenticated;
grant execute on function public.admin_sentar_grupo(text, text, integer)                            to anon, authenticated;
grant execute on function public.admin_apartar(text, integer, text)                                 to anon, authenticated;
grant execute on function public.admin_apartado_borrar(text, bigint)                                to anon, authenticated;
grant execute on function public.admin_mesa_intercambiar(text, integer, integer)                    to anon, authenticated;

-- Que la API vea las funciones nuevas sin esperar.
notify pgrst, 'reload schema';
