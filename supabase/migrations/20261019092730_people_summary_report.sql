-- Read-only, single-statement aggregate: no personal fields leave the database.
-- Applied after explicit production approval; version aligned to the MCP receipt.
create function public.people_summary_report(p_organization uuid,p_unit uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or p_unit is null or not private.has_organization_role(p_organization,array['owner','admin','pastor','secretary','leader']::public.membership_role[])
 or not private.can_access_unit(p_organization,p_unit)
 or not private.target_unit_module_enabled(p_organization,p_unit,'reports')
 or not private.target_unit_module_enabled(p_organization,p_unit,'people')
 or not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_organization and u.status='active' and o.status in ('active','trial')) then
  raise exception 'report_access_denied' using errcode='42501';
 end if;
 select jsonb_build_object('total',count(*)::text,'members',count(*) filter(where journey_status='Membro')::text,
 'visitors',count(*) filter(where journey_status='Visitante')::text,'integration',count(*) filter(where journey_status='Em integração')::text,
 'other',count(*) filter(where journey_status is null or journey_status not in ('Membro','Visitante','Em integração'))::text)
 into result from public.people where organization_id=p_organization and unit_id=p_unit;
 return jsonb_build_object('unitId',p_unit,'generatedAt',statement_timestamp(),'counts',result);
end $$;
revoke all on function public.people_summary_report(uuid,uuid) from public,anon,service_role;
grant execute on function public.people_summary_report(uuid,uuid) to authenticated;
