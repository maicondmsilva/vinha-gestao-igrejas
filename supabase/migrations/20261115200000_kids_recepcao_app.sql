-- Kids · recepção no Vinha Equipe: quem pode retirar a criança presente (responsáveis aprovados com permissão de
-- retirada e validade em dia). A conferência de identidade e o código do comprovante continuam no banco (checkout).
create or replace function public.kids_pickup_guardians(p_org uuid, p_unit uuid, p_attendance uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare a private.kids_attendance;
begin
 select * into a from private.kids_attendance where id=p_attendance and organization_id=p_org and unit_id=p_unit;
 if a.id is null or not private.kids_op_allowed(p_org,p_unit,a.session_id,'receive',a.group_id) then raise exception 'kids_access_denied' using errcode='42501';end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'relationship',g.relationship,'arrived',p.id=a.arrival_guardian) order by (p.id=a.arrival_guardian) desc,p.full_name)
  from private.kids_guardians g join public.people p on p.id=g.person_id
  where g.profile_id=a.profile_id and g.organization_id=p_org and g.status='approved' and g.can_pickup
   and (g.valid_until is null or g.valid_until>=(clock_timestamp() at time zone private.unit_timezone(p_unit))::date)
   and p.status='active' and p.birth_date<=current_date-interval '18 years'),'[]'::jsonb));
end $function$;
revoke all on function public.kids_pickup_guardians(uuid,uuid,uuid) from public,anon;
grant execute on function public.kids_pickup_guardians(uuid,uuid,uuid) to authenticated;
