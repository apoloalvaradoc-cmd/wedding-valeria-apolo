-- ============================================================
-- 019 · Cada regalo de las mesas sabe a qué invitación pertenece
--
-- Adivinar por nombre falla cuando compra la pareja del titular, un
-- familiar, o varias familias juntas ("Familia Aguiluz y Familia
-- Quixchán"). Ahora cada compra guarda la(s) invitación(es) validadas y
-- la consola usa eso antes que el parecido de nombres.
-- Los datos se cargan desde el SQL Editor (el repo es público).
-- ============================================================

alter table public.regalos_registro
  add column if not exists invitados text[] not null default '{}';

create or replace function public.admin_regalos_registro(p_clave text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
begin
  perform public.admin_verificar(p_clave);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'tienda', tienda, 'quien', quien, 'regalo', regalo,
             'monto', monto, 'invitados', to_jsonb(invitados)) order by quien)
    from public.regalos_registro
  ), '[]'::jsonb);
end;
$fn$;

revoke all on function public.admin_regalos_registro(text) from public;
grant execute on function public.admin_regalos_registro(text) to anon, authenticated;
