-- 017 · Los textos de lo fijo del salón se pueden cambiar
--
-- La tarima, la mesa larga frente a ella, la pista, el bar y el pastel van
-- dibujados en el croquis pero no son mesas. Sus textos venían fijos en la
-- página; la mesa larga salía como "Mesa de honor" y todavía no se sabe qué
-- va a ser. Ahora cada texto se edita desde mesas.html y se guarda aquí,
-- en config, como un JSON bajo la clave 'salon_etiquetas'. Lo que no está
-- guardado usa el texto por defecto de la página.

-- Con p_elemento nulo solo lee. Con p_elemento cambia ese texto (vacío lo
-- deja sin nombre). Siempre devuelve todos los textos guardados.
create or replace function public.admin_salon_etiqueta(
  p_clave    text,
  p_elemento text default null,
  p_texto    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actual jsonb;
begin
  perform public.admin_verificar(p_clave);

  select coalesce(valor::jsonb, '{}'::jsonb) into v_actual
    from public.config where clave = 'salon_etiquetas';
  v_actual := coalesce(v_actual, '{}'::jsonb);

  if p_elemento is not null then
    if p_elemento not in ('tarima', 'larga', 'pista', 'bar', 'pastel') then
      raise exception 'Elemento del salón desconocido' using errcode = '22023';
    end if;
    if length(coalesce(p_texto, '')) > 40 then
      raise exception 'El texto es demasiado largo' using errcode = '22023';
    end if;

    v_actual := v_actual || jsonb_build_object(p_elemento, btrim(coalesce(p_texto, '')));
    insert into public.config (clave, valor) values ('salon_etiquetas', v_actual::text)
    on conflict (clave) do update set valor = excluded.valor;
  end if;

  return v_actual;
end;
$$;

revoke all on function public.admin_salon_etiqueta(text, text, text) from public;
grant execute on function public.admin_salon_etiqueta(text, text, text) to anon, authenticated;

-- La mesa larga empieza sin nombre.
insert into public.config (clave, valor) values ('salon_etiquetas', '{"larga": ""}')
on conflict (clave) do nothing;

notify pgrst, 'reload schema';
