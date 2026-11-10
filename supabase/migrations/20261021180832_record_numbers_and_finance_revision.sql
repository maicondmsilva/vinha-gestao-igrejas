begin;
set local lock_timeout='5s';
-- Private, transactional counters. Public UUIDs remain identities, never human registration numbers.
create table private.record_counters(organization_id uuid not null references public.organizations(id),scope text not null,last_number bigint not null check(last_number>0),primary key(organization_id,scope));
create table private.member_numbering_preferences(organization_id uuid primary key references public.organizations(id),mode text not null default 'ministry' check(mode in('ministry','unit')));
create table private.member_record_numbers(person_id uuid primary key references public.people(id),organization_id uuid not null references public.organizations(id),unit_id uuid,ministry_number bigint not null check(ministry_number>0),unit_number bigint check(unit_number>0),unique(organization_id,ministry_number),unique(organization_id,unit_id,unit_number),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id));
create index member_record_numbers_unit on private.member_record_numbers(unit_id,organization_id);
create table private.finance_record_numbers(entry_id uuid primary key,organization_id uuid not null,unit_id uuid not null,number bigint not null check(number>0),unique(organization_id,unit_id,number),foreign key(entry_id,organization_id,unit_id) references private.finance_entries(id,organization_id,unit_id));
create index finance_record_numbers_entry_scope on private.finance_record_numbers(entry_id,organization_id,unit_id);
do $$declare t text;begin foreach t in array array['record_counters','member_numbering_preferences','member_record_numbers','finance_record_numbers'] loop execute format('alter table private.%I enable row level security',t);execute format('create policy %I on private.%I as restrictive for all using(false) with check(false)',t||'_deny',t);execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);end loop;end$$;
create function private.next_record_number(p_org uuid,p_scope text) returns bigint language sql volatile security definer set search_path='' as $$insert into private.record_counters values(p_org,p_scope,1) on conflict(organization_id,scope) do update set last_number=private.record_counters.last_number+1 returning last_number$$;
revoke all on function private.next_record_number(uuid,text) from public,anon,authenticated,service_role;
-- Stable allocation for existing records; no renumbering of UUIDs or business records.
lock table public.people,private.finance_entries in share row exclusive mode;
insert into private.member_record_numbers select id,organization_id,unit_id,row_number()over(partition by organization_id order by created_at,id),case when unit_id is not null then row_number()over(partition by organization_id,unit_id order by created_at,id) end from public.people;
insert into private.finance_record_numbers select id,organization_id,unit_id,row_number()over(partition by organization_id,unit_id order by created_at,id) from private.finance_entries;
insert into private.record_counters select organization_id,'members:ministry',max(ministry_number) from private.member_record_numbers group by organization_id;
insert into private.record_counters select organization_id,'members:unit:'||unit_id,max(unit_number) from private.member_record_numbers where unit_id is not null group by organization_id,unit_id;
insert into private.record_counters select organization_id,'finance:unit:'||unit_id,max(number) from private.finance_record_numbers group by organization_id,unit_id;
create function private.assign_record_numbers() returns trigger language plpgsql security definer set search_path='' as $$declare n bigint;u bigint;begin
 if tg_table_name='people' then
  if tg_op='UPDATE' then
   if new.organization_id is distinct from old.organization_id then raise exception 'record_organization_immutable' using errcode='42501';end if;
   if new.unit_id is distinct from old.unit_id then u:=case when new.unit_id is not null then private.next_record_number(new.organization_id,'members:unit:'||new.unit_id) end;update private.member_record_numbers set unit_id=new.unit_id,unit_number=u where person_id=new.id;end if;
  else n:=private.next_record_number(new.organization_id,'members:ministry');u:=case when new.unit_id is not null then private.next_record_number(new.organization_id,'members:unit:'||new.unit_id) end;insert into private.member_record_numbers values(new.id,new.organization_id,new.unit_id,n,u);end if;
 else n:=private.next_record_number(new.organization_id,'finance:unit:'||new.unit_id);insert into private.finance_record_numbers values(new.id,new.organization_id,new.unit_id,n);end if;return new;
end$$;
revoke all on function private.assign_record_numbers() from public,anon,authenticated,service_role;
create trigger assign_member_record_numbers after insert or update of unit_id on public.people for each row execute function private.assign_record_numbers();
create trigger assign_finance_record_numbers after insert on private.finance_entries for each row execute function private.assign_record_numbers();
create function private.record_numbering(p_org uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare mode text;result jsonb;begin
 perform private.require_confirmed_self_service_email();
 if not exists(select 1 from public.organization_memberships m join public.organizations o on o.id=m.organization_id where m.user_id=auth.uid() and m.organization_id=p_org and m.status='active' and o.status in('active','trial')) then raise exception 'numbering_denied' using errcode='42501';end if;
 select pref.mode into mode from private.member_numbering_preferences pref where organization_id=p_org;mode:=coalesce(mode,'ministry');
 if p_action in('settings','set_mode') then
  if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) then raise exception 'numbering_manager_required' using errcode='42501';end if;
  if p_action='set_mode' then
   perform 1 from public.organizations where id=p_org for no key update;
   if not exists(select 1 from public.organization_memberships m join public.organizations o on o.id=m.organization_id where m.user_id=auth.uid() and m.organization_id=p_org and m.status='active' and m.role in('owner','admin') and o.status in('active','trial')) then raise exception 'numbering_manager_required' using errcode='42501';end if;
   if p_data->>'mode' is null or p_data->>'mode' not in('ministry','unit') then raise exception 'invalid_numbering_mode' using errcode='22023';end if;
   insert into private.member_numbering_preferences values(p_org,p_data->>'mode') on conflict(organization_id) do update set mode=excluded.mode;
   insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'members.numbering_mode','organization',p_org::text,jsonb_build_object('previous',mode,'mode',p_data->>'mode'));
   mode:=p_data->>'mode';
  end if;return jsonb_build_object('mode',mode);
 end if;
 if jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids')>100 then raise exception 'invalid_numbering_ids' using errcode='22023';end if;
 if p_action='people' then
  select coalesce(jsonb_object_agg(n.person_id::text,case when mode='unit' then n.unit_number::text else n.ministry_number::text end),'{}') into result from private.member_record_numbers n where n.organization_id=p_org and n.person_id in(select value::uuid from jsonb_array_elements_text(p_data->'ids')) and private.can_view_person(n.person_id);
 elsif p_action='finance' then
  select coalesce(jsonb_object_agg(n.entry_id::text,n.number::text),'{}') into result from private.finance_record_numbers n where n.organization_id=p_org and n.entry_id in(select value::uuid from jsonb_array_elements_text(p_data->'ids')) and private.church_ledger_allowed(p_org,n.unit_id);
 else raise exception 'invalid_numbering_action' using errcode='22023';end if;
 return jsonb_build_object('mode',mode,'codes',result);
end$$;
revoke all on function private.record_numbering(uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.record_numbering(uuid,text,jsonb) to authenticated;
create function public.record_numbering(p_org uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.record_numbering(p_org,p_action,p_data)$$;
revoke all on function public.record_numbering(uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.record_numbering(uuid,text,jsonb) to authenticated;

-- Pending manual titles may be revised; posted journals, digital receipts and series are never rewritten.
create function private.finance_revise_pending(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare ent private.finance_entries;receipt private.finance_f2_commands;req uuid;hash text;result jsonb;amount bigint;account uuid;category uuid;center uuid;competence date;due date;memo text;v_notes text;v_method text;
begin
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>8192 or exists(select 1 from jsonb_object_keys(p_data) k where k not in('id','title','version','amountCents','description','account','category','center','competence','due','method','notes')) then raise exception 'invalid_revision' using errcode='22023';end if;
 perform 1 from public.organizations where id=p_org for update;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 req:=(p_data->>'id')::uuid;hash:=encode(extensions.digest(p_data::text,'sha256'),'hex');
 if req is null then raise exception 'missing_request' using errcode='22023';end if;
 select * into receipt from private.finance_f2_commands where id=req;
 if found then
  if receipt.organization_id<>p_org or receipt.unit_id<>p_unit or receipt.action<>'edit_entry' or receipt.fingerprint<>hash then raise exception 'request_conflict' using errcode='22023';end if;
  return receipt.result;
 end if;
 select * into ent from private.finance_entries where id=(p_data->>'title')::uuid and organization_id=p_org and unit_id=p_unit for update;
 if not found then raise exception 'entry_unavailable' using errcode='42501';end if;
 if ent.version is distinct from (p_data->>'version')::integer then raise exception 'entry_changed' using errcode='40001';end if;
 if ent.status<>'pending' or ent.kind not in('income','expense') or ent.journal_id is not null or ent.reversal_id is not null
 or exists(select 1 from private.finance_series_items where entry_id=ent.id)
 or exists(select 1 from private.finance_settlements where title_id=ent.id or cash_entry=ent.id or fee_entry=ent.id)
 or exists(select 1 from private.finance_digital_links where entry_id=ent.id)
 then raise exception 'entry_revision_not_allowed' using errcode='22023';end if;
 amount:=(p_data->>'amountCents')::bigint;account:=(p_data->>'account')::uuid;category:=(p_data->>'category')::uuid;center:=nullif(p_data->>'center','')::uuid;
 competence:=(p_data->>'competence')::date;due:=(p_data->>'due')::date;memo:=btrim(p_data->>'description');v_notes:=p_data->>'notes';v_method:=p_data->>'method';
 if amount is null or amount not between 1 and 999999999999 or memo is null or length(memo) not between 2 and 300 or v_notes is null or length(v_notes)>2000 or competence is null or due is null or v_method is null or v_method not in('cash','pix','card','boleto','bank','other') then raise exception 'invalid_revision' using errcode='22023';end if;
 if not exists(select 1 from private.finance_catalog where id=account and organization_id=p_org and unit_id=p_unit and kind='account' and active)
 or not exists(select 1 from private.finance_catalog where id=category and organization_id=p_org and (unit_id=p_unit or unit_id is null) and kind='category' and active and direction=ent.kind)
 or (center is not null and not exists(select 1 from private.finance_catalog where id=center and organization_id=p_org and (unit_id=p_unit or unit_id is null) and kind='center' and active))
 then raise exception 'invalid_catalog' using errcode='22023';end if;
 update private.finance_entries set amount_cents=amount,description=memo,account_id=account,category_id=category,center_id=center,competence_date=competence,due_date=due,method=v_method,notes=v_notes,version=version+1 where id=ent.id;
 result:=jsonb_build_object('id',req,'ok',true,'title',ent.id,'version',ent.version+1);
 insert into private.finance_f2_commands values(req,p_org,p_unit,'edit_entry',hash,result,now());
 return result;
end$$;
revoke all on function private.finance_revise_pending(uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function private.finance_revise_pending(uuid,uuid,jsonb) to authenticated;
create function public.finance_revise_pending(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_revise_pending(p_org,p_unit,p_data)$$;
revoke all on function public.finance_revise_pending(uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function public.finance_revise_pending(uuid,uuid,jsonb) to authenticated;

-- Manual credentials without sufficient provider proof are saved disabled, never marked connected.
create function private.finance_receiver_manual_key(p_actor uuid,p_org uuid,p_unit uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.finance_receivers;
begin
 if not private.receiver_actor_allowed(p_actor,p_org,p_unit) then raise exception 'receiver_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for update;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 perform 1 from auth.users where id=p_actor for share;
 if not private.receiver_actor_allowed(p_actor,p_org,p_unit) then raise exception 'receiver_denied' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>20000 or p_data->>'provider' is null or p_data->>'provider' not in('mercado_pago','safe2pay') or p_data->>'environment' is null or p_data->>'environment' not in('sandbox','production') or p_data->>'sealed' is null or length(p_data->>'sealed') not between 32 and 16384 then raise exception 'invalid_manual_key' using errcode='22023';end if;
 select * into r from private.finance_receivers where organization_id=p_org and unit_id=p_unit and provider=p_data->>'provider' and environment=p_data->>'environment' for update;
 if r.status='blocked' then raise exception 'receiver_blocked' using errcode='42501';end if;
 if coalesce(r.version,0) is distinct from (p_data->>'version')::integer then raise exception 'receiver_changed' using errcode='40001';end if;
 if r.id is null then insert into private.finance_receivers(organization_id,unit_id,provider,environment,status,created_by) values(p_org,p_unit,p_data->>'provider',p_data->>'environment','reauthorize',p_actor) returning * into r;end if;
 update private.finance_receivers set status='reauthorize',provider_status='manual_key_pending_validation',holder_confirmed=false,methods='{}',beneficiary_units='{}',expires_at=null,version=version+1,updated_at=now() where id=r.id;
 insert into private.finance_receiver_secrets values(r.id,p_data->>'sealed',now()) on conflict(receiver_id) do update set sealed=excluded.sealed,updated_at=excluded.updated_at;
 insert into private.finance_receiver_events(receiver_id,actor,action,details) values(r.id,p_actor,'manual_key_pending',jsonb_build_object('provider',r.provider,'environment',r.environment));
 return jsonb_build_object('ok',true,'pendingValidation',true);
end$$;
revoke all on function private.finance_receiver_manual_key(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function private.finance_receiver_manual_key(uuid,uuid,uuid,jsonb) to service_role;
create function public.finance_receiver_manual_key(p_actor uuid,p_org uuid,p_unit uuid,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_receiver_manual_key(p_actor,p_org,p_unit,p_data)$$;
revoke all on function public.finance_receiver_manual_key(uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.finance_receiver_manual_key(uuid,uuid,uuid,jsonb) to service_role;

create table private.finance_provider_accounts(receiver_id uuid primary key references private.finance_receivers(id),catalog_id uuid not null unique references private.finance_catalog(id));
alter table private.finance_provider_accounts enable row level security;
create policy finance_provider_accounts_deny on private.finance_provider_accounts as restrictive for all using(false) with check(false);
revoke all on private.finance_provider_accounts from public,anon,authenticated,service_role;
create function private.ensure_provider_account() returns trigger language plpgsql security definer set search_path='' as $$
declare account uuid;ledger uuid;name text;
begin
 if new.status not in('connected','configured') then return new;end if;
 select catalog_id into account from private.finance_provider_accounts where receiver_id=new.id;
 if account is null then
  account:=extensions.gen_random_uuid();ledger:=extensions.gen_random_uuid();
  name:=case new.provider when 'mercado_pago' then 'Mercado Pago' when 'asaas' then 'Asaas' else 'Safe2Pay' end||' · '||case new.environment when 'sandbox' then 'Teste' else 'Recebimentos' end||' · '||left(new.id::text,8);
  insert into private.finance_catalog(id,organization_id,unit_id,kind,name,details) values(account,new.organization_id,new.unit_id,'account',name,jsonb_build_object('bank','Saldo no provedor','description','Conta de controle de recebimentos; não representa saldo bancário consultado no provedor.'));
  insert into public.church_ledger_accounts(id,organization_id,unit_id,name,kind) values(ledger,new.organization_id,new.unit_id,name,'asset');
  insert into private.finance_account_links values(account,new.organization_id,new.unit_id,ledger);
  insert into private.finance_provider_accounts values(new.id,account);
 end if;
 if new.account_id is null then update private.finance_receivers set account_id=account where id=new.id;end if;
 return new;
end$$;
revoke all on function private.ensure_provider_account() from public,anon,authenticated,service_role;
create trigger ensure_finance_provider_account after insert or update of status,account_id on private.finance_receivers for each row execute function private.ensure_provider_account();
commit;
