begin;
set local lock_timeout='5s';
do $patch$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('private.finance_f6(uuid,uuid[],text,jsonb)'::regprocedure);
 needle:='if p_data->>''report''=''members'' and not identities then';
 if strpos(definition,needle)=0 or strpos(definition,'finance.report_export_prepared')>0 then raise exception 'unexpected_f6_definition';end if;
 definition:=replace(definition,needle,'if p_data->>''report''=''providers'' and date_by<>''cash'' then raise exception ''provider_cash_date_required'' using errcode=''22023'';end if;
 '||needle);
 needle:='jsonb_build_object(''id'',b.id,''unit'',b.unit_id,''month'',b.month';
 if strpos(definition,needle)=0 then raise exception 'unexpected_budget_definition';end if;
 definition:=replace(definition,needle,'jsonb_build_object(''id'',b.id,''unit'',b.unit_id,''unitName'',(select name from public.organization_units where id=b.unit_id),''month'',b.month');
 needle:='return jsonb_build_object(''rows'',rows,''digital'',digital';
 if strpos(definition,needle)=0 then raise exception 'unexpected_report_definition';end if;
 definition:=replace(definition,needle,'if p_data->''export''=''true''::jsonb then
  req:=extensions.gen_random_uuid();
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_org,auth.uid(),''finance.report_export_prepared'',''finance_report'',req::text,jsonb_build_object(''units'',p_units,''report'',p_data->>''report'',''from'',v_from,''to'',v_to,''dateBy'',date_by,''rows'',jsonb_array_length(rows)));
 end if;
 return jsonb_build_object(''exportId'',req,''rows'',rows,''digital'',digital');
 execute definition;
end $patch$;
commit;
