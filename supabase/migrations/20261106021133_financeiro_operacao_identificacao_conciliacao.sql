begin;
set local lock_timeout='5s';
-- Presentation metadata never rewrites provider postings or their immutable evidence.
create table private.finance_entry_annotations(
 entry_id uuid primary key,organization_id uuid not null,unit_id uuid not null,
 description text not null check(length(btrim(description)) between 2 and 300),notes text not null check(length(notes)<=2000),
 version integer not null default 1,updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 foreign key(entry_id,organization_id,unit_id) references private.finance_entries(id,organization_id,unit_id));
create index finance_entry_annotations_scope on private.finance_entry_annotations(organization_id,unit_id);
create index finance_entry_annotations_actor on private.finance_entry_annotations(updated_by);
create table private.finance_ofx_entries(
 transaction_id uuid primary key references private.finance_bank_transactions(id),entry_id uuid not null unique references private.finance_entries(id),
 organization_id uuid not null,unit_id uuid not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id));
create index finance_ofx_entries_scope on private.finance_ofx_entries(organization_id,unit_id);
create index finance_ofx_entries_actor on private.finance_ofx_entries(created_by);
do $$declare t text;begin foreach t in array array['finance_entry_annotations','finance_ofx_entries'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('create policy %I on private.%I as restrictive for all using(false) with check(false)',t||'_deny',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end$$;
create trigger finance_ofx_entries_immutable before update or delete on private.finance_ofx_entries for each row execute function private.finance_history_immutable();

-- Only called after the outer finance API has rechecked the exact organization/unit.
create function private.finance_order_origin(p_org uuid,p_unit uuid,p_order uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('event_name',e.title,'event_number',e.display_id::text,'event_mode',e.commerce_mode)
 from private.event_ticket_orders o join private.church_app_events e on e.id=o.event_id and e.organization_id=o.organization_id
 where o.id=p_order and o.organization_id=p_org and o.receiving_unit=p_unit),'{}'::jsonb)
$$;
revoke all on function private.finance_order_origin(uuid,uuid,uuid) from public,anon,authenticated,service_role;
create function private.finance_entry_display(p_org uuid,p_entry uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e private.finance_entries;a private.finance_entry_annotations;origin jsonb:='{}';k text;d text;oid uuid;
begin
 select * into e from private.finance_entries where id=p_entry and organization_id=p_org;
 if not found then return '{}';end if;
 select * into a from private.finance_entry_annotations where entry_id=e.id;
 select l.kind,r.order_id into k,oid from private.finance_digital_links l join private.finance_digital_receipts r on r.id=l.receipt_id where l.entry_id=e.id;
 if oid is not null then origin:=private.finance_order_origin(p_org,e.unit_id,oid);end if;
 d:=case k when 'gross' then 'Recebimento' when 'fee' then 'Taxa de pagamento' when 'refund' then 'Devolução' when 'fee_credit' then 'Estorno de taxa' end;
 if d is not null then d:=d||' · '||case when origin ? 'event_name' then (origin->>'event_name')||' · ID '||(origin->>'event_number') else 'Pagamento digital' end;end if;
 return origin||jsonb_build_object('display_description',coalesce(a.description,d,e.description),'digital_kind',k,'annotation_notes',coalesce(a.notes,''),'annotation_version',coalesce(a.version,0));
end$$;
revoke all on function private.finance_entry_display(uuid,uuid) from public,anon,authenticated,service_role;

-- Add readable origins before filtering/pagination, so searches find the actual event.
do $$declare d text;begin
 d:=pg_get_functiondef('private.finance_f1_base(uuid,uuid[],text,jsonb)'::regprocedure);
 if strpos(d,'limit 30 offset (page-1)*30')=0 then raise exception 'finance_pagination_base_changed';end if;
 d:=replace(d,'limit 30 offset (page-1)*30','limit least(150,greatest(1,coalesce((p_data->>''pageSize'')::integer,30))) offset (page-1)*least(150,greatest(1,coalesce((p_data->>''pageSize'')::integer,30)))');
 if strpos(d,$needle$lower(e.description||' '||e.party_name)$needle$)=0 then raise exception 'finance_search_base_changed';end if;
 d:=replace(d,$needle$lower(e.description||' '||e.party_name)$needle$,$replacement$lower(coalesce(private.finance_entry_display(p_org,e.id)->>'display_description',e.description)||' '||e.party_name)$replacement$);
 execute d;
end$$;
alter function private.finance_f1(uuid,uuid[],text,jsonb) rename to finance_f1_before_readable_origin;
revoke all on function private.finance_f1_before_readable_origin(uuid,uuid[],text,jsonb) from public,anon,authenticated,service_role;
create function private.finance_f1(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;items jsonb;begin
 r:=private.finance_f1_before_readable_origin(p_org,p_units,p_action,p_data);
 if p_action='snapshot' then
  select coalesce(jsonb_agg(x.value||private.finance_entry_display(p_org,(x.value->>'id')::uuid) order by x.ordinality),'[]') into items from jsonb_array_elements(r->'entries') with ordinality x;
  r:=jsonb_set(r,'{entries}',items);
 end if;return r;
end$$;
revoke all on function private.finance_f1(uuid,uuid[],text,jsonb) from public,anon,service_role;
grant execute on function private.finance_f1(uuid,uuid[],text,jsonb) to authenticated;

alter function private.finance_digital(uuid,uuid,text,jsonb) rename to finance_digital_before_readable_origin;
revoke all on function private.finance_digital_before_readable_origin(uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;
create function private.finance_digital(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;items jsonb;begin
 r:=private.finance_digital_before_readable_origin(p_org,p_unit,p_action,p_data);
 if p_action='list' then
  select coalesce(jsonb_agg(x.value||private.finance_order_origin(p_org,p_unit,(x.value->>'id')::uuid) order by x.ordinality),'[]') into items from jsonb_array_elements(r->'items') with ordinality x;
  r:=jsonb_set(r,'{items}',items);
 end if;return r;
end$$;
revoke all on function private.finance_digital(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.finance_digital(uuid,uuid,text,jsonb) to authenticated;

-- Enrich report rows, including exports, without changing original journal evidence.
alter function private.finance_f6(uuid,uuid[],text,jsonb) rename to finance_f6_before_readable_origin;
revoke all on function private.finance_f6_before_readable_origin(uuid,uuid[],text,jsonb) from public,anon,authenticated,service_role;
create function private.finance_f6(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;items jsonb;begin
 r:=private.finance_f6_before_readable_origin(p_org,p_units,p_action,p_data);
 if r ? 'rows' then
  select coalesce(jsonb_agg(case when nullif(x.value->>'id','') is not null and (nullif(private.finance_entry_display(p_org,(x.value->>'id')::uuid)->>'digital_kind','') is not null or coalesce((private.finance_entry_display(p_org,(x.value->>'id')::uuid)->>'annotation_version')::integer,0)>0) then x.value||jsonb_build_object('description',case when x.value->>'status'='reversed' then 'Estorno · ' else '' end||coalesce(private.finance_entry_display(p_org,(x.value->>'id')::uuid)->>'display_description',x.value->>'description')) else x.value end order by x.ordinality),'[]') into items from jsonb_array_elements(r->'rows') with ordinality x;
  r:=jsonb_set(r,'{rows}',items);
 end if;return r;
end$$;
revoke all on function private.finance_f6(uuid,uuid[],text,jsonb) from public,anon,service_role;
grant execute on function private.finance_f6(uuid,uuid[],text,jsonb) to authenticated;

create function private.finance_annotate_entry(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare e private.finance_entries;a private.finance_entry_annotations;req uuid;hash text;previous private.finance_f2_commands;result jsonb;actor text;
begin
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for update;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or p_data-array['id','entry','version','description','notes','reason']<>'{}' or not(p_data ?& array['id','entry','version','description','notes','reason']) or length(btrim(p_data->>'description')) not between 2 and 300 or length(p_data->>'notes')>2000 or length(btrim(p_data->>'reason')) not between 2 and 300 then raise exception 'invalid_annotation' using errcode='22023';end if;
 req:=(p_data->>'id')::uuid;hash:=encode(extensions.digest(p_data::text,'sha256'),'hex');
 select * into previous from private.finance_f2_commands where id=req;
 if found then if previous.organization_id<>p_org or previous.unit_id<>p_unit or previous.action<>'annotate_entry' or previous.fingerprint<>hash then raise exception 'request_conflict' using errcode='40001';end if;return previous.result;end if;
 select * into e from private.finance_entries where id=(p_data->>'entry')::uuid and organization_id=p_org and unit_id=p_unit for update;
 if not found or not exists(select 1 from private.finance_digital_links where entry_id=e.id) then raise exception 'entry_unavailable' using errcode='42501';end if;
 select * into a from private.finance_entry_annotations where entry_id=e.id;
 if coalesce(a.version,0) is distinct from (p_data->>'version')::integer then raise exception 'entry_changed' using errcode='40001';end if;
 insert into private.finance_entry_annotations(entry_id,organization_id,unit_id,description,notes,updated_by) values(e.id,p_org,p_unit,btrim(p_data->>'description'),p_data->>'notes',auth.uid()) on conflict(entry_id) do update set description=excluded.description,notes=excluded.notes,version=finance_entry_annotations.version+1,updated_by=auth.uid(),updated_at=now();
 select coalesce(nullif(full_name,''),'Operador identificado') into actor from public.profiles where id=auth.uid();
 insert into private.finance_entry_history(entry_id,organization_id,unit_id,actor_id,actor_name,event,changes) values(e.id,p_org,p_unit,auth.uid(),coalesce(actor,'Operador identificado'),'changed',jsonb_build_object('description',jsonb_build_object('before',coalesce(a.description,e.description),'after',btrim(p_data->>'description')),'notes',jsonb_build_object('before',coalesce(a.notes,''),'after',p_data->>'notes')));
 result:=jsonb_build_object('ok',true,'id',req);
 insert into private.finance_f2_commands(id,organization_id,unit_id,action,fingerprint,result) values(req,p_org,p_unit,'annotate_entry',hash,result);
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'finance.entry.annotation','finance_entry',e.id::text,jsonb_build_object('reason',p_data->>'reason','unit_id',p_unit));
 return result;
end$$;
revoke all on function private.finance_annotate_entry(uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function private.finance_annotate_entry(uuid,uuid,jsonb) to authenticated;
create function public.finance_annotate_entry(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_annotate_entry(p_org,p_unit,p_data)$$;
revoke all on function public.finance_annotate_entry(uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function public.finance_annotate_entry(uuid,uuid,jsonb) to authenticated;

-- Larger paged comparison: no operation automatically selects all movements.
do $$declare d text;begin
 d:=pg_get_functiondef('private.finance_f5(uuid,uuid,text,jsonb)'::regprocedure);
 if strpos(d,'limit 101')=0 then raise exception 'finance_f5_base_changed';end if;
 d:=replace(d,'limit 101','limit 1001');execute d;
end$$;
alter function private.finance_f5(uuid,uuid,text,jsonb) rename to finance_f5_before_ofx_entry;
revoke all on function private.finance_f5_before_ofx_entry(uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;
create function private.finance_f5(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;items jsonb;t private.finance_bank_transactions;previous private.finance_f5_commands;hash text;req uuid;e private.finance_entries;
begin
 if p_action<>'ofx_entry' then
  r:=private.finance_f5_before_ofx_entry(p_org,p_unit,p_action,p_data);
  if p_action='snapshot' then
   select coalesce(jsonb_agg(x.value||jsonb_build_object('created_entry',m.entry_id,'created_code',n.number::text) order by x.ordinality),'[]') into items from jsonb_array_elements(r->'bank') with ordinality x left join private.finance_ofx_entries m on m.transaction_id=(x.value->>'id')::uuid and m.organization_id=p_org and m.unit_id=p_unit left join private.finance_record_numbers n on n.entry_id=m.entry_id;
   r:=jsonb_set(r,'{bank}',items);
   select coalesce(jsonb_agg(x.value||jsonb_build_object('party',coalesce(s.name,entrow.party_name,original.party_name,''),'memo',coalesce(private.finance_entry_display(p_org,entrow.id)->>'display_description',x.value->>'memo')) order by x.ordinality),'[]') into items from jsonb_array_elements(r->'book') with ordinality x join public.church_ledger_journals j on j.id=(x.value->>'id')::uuid and j.organization_id=p_org and j.unit_id=p_unit left join private.finance_entries entrow on entrow.journal_id=j.id left join private.finance_entries original on original.journal_id=j.reversal_of left join private.finance_catalog s on s.id=coalesce(entrow.supplier_id,original.supplier_id) and s.organization_id=p_org;
   r:=jsonb_set(r,'{book}',items);
  end if;return r;
 end if;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for update;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or p_data-array['id','transaction','version','entry']<>'{}' or not(p_data ?& array['id','transaction','version','entry']) then raise exception 'invalid_ofx_entry' using errcode='22023';end if;
 req:=(p_data->>'id')::uuid;hash:=encode(extensions.digest(p_data::text,'sha256'),'hex');
 select * into previous from private.finance_f5_commands where id=req;
 if found then if previous.organization_id<>p_org or previous.unit_id<>p_unit or previous.action<>p_action or previous.fingerprint<>hash then raise exception 'request_conflict' using errcode='40001';end if;return previous.result;end if;
 select * into t from private.finance_bank_transactions where id=(p_data->>'transaction')::uuid and organization_id=p_org and unit_id=p_unit for update;
 if not found or t.version is distinct from (p_data->>'version')::integer or t.ignored or exists(select 1 from private.finance_reconciliation_bank_items where transaction_id=t.id and active) or exists(select 1 from private.finance_ofx_entries where transaction_id=t.id) then raise exception 'ofx_entry_already_created' using errcode='40001';end if;
 if (p_data->'entry'->>'id')::uuid is distinct from req or p_data->'entry'->>'kind' not in('income','expense') or (p_data->'entry'->>'account')::uuid is distinct from t.account_id then raise exception 'invalid_ofx_entry' using errcode='22023';end if;
 if exists(select 1 from public.church_ledger_periods where organization_id=p_org and unit_id=p_unit and closed_through>=t.effective_date) then raise exception 'period_closed' using errcode='22023';end if;
 r:=private.finance_f1(p_org,array[p_unit],'entry',p_data->'entry');
 select * into e from private.finance_entries where id=req and organization_id=p_org and unit_id=p_unit;
 if not found then raise exception 'invalid_ofx_entry' using errcode='22023';end if;
 insert into private.finance_ofx_entries(transaction_id,entry_id,organization_id,unit_id,created_by) values(t.id,e.id,p_org,p_unit,auth.uid());
 insert into private.finance_f5_commands(id,organization_id,unit_id,action,fingerprint,result) values(req,p_org,p_unit,p_action,hash,r);
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'finance.ofx.entry','finance_entry',e.id::text,jsonb_build_object('transaction',t.id,'unit_id',p_unit));
 return r;
end$$;
revoke all on function private.finance_f5(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.finance_f5(uuid,uuid,text,jsonb) to authenticated;
commit;
