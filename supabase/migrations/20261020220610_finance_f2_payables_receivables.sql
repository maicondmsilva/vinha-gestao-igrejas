-- F2: manual accounts payable/receivable. No external charges or bank movement.
set local lock_timeout='5s';
create table private.finance_f2_commands (
 id uuid primary key, organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 action text not null,fingerprint text not null,result jsonb not null,created_at timestamptz not null default now(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index finance_f2_commands_unit on private.finance_f2_commands(unit_id,organization_id);
create table private.finance_settlements (
 id uuid primary key,organization_id uuid not null,unit_id uuid not null,title_id uuid not null,
 principal_cents bigint not null check(principal_cents>0),interest_cents bigint not null check(interest_cents>=0),fine_cents bigint not null check(fine_cents>=0),discount_cents bigint not null check(discount_cents>=0 and discount_cents<=principal_cents),fee_cents bigint not null check(fee_cents>=0),
 cash_entry uuid not null unique,fee_entry uuid unique,reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),reversed_at timestamptz,
 foreign key(title_id,organization_id,unit_id) references private.finance_entries(id,organization_id,unit_id),
 foreign key(cash_entry,organization_id,unit_id) references private.finance_entries(id,organization_id,unit_id),
 foreign key(fee_entry,organization_id,unit_id) references private.finance_entries(id,organization_id,unit_id)
);
create index finance_settlements_title on private.finance_settlements(title_id,organization_id,unit_id);
create index finance_settlements_cash on private.finance_settlements(cash_entry,organization_id,unit_id);
create index finance_settlements_fee on private.finance_settlements(fee_entry,organization_id,unit_id);
create index finance_settlements_creator on private.finance_settlements(created_by);
create table private.finance_series_items (
 entry_id uuid primary key,organization_id uuid not null,unit_id uuid not null,series_id uuid not null references private.finance_f2_commands(id),position integer not null,count integer not null,mode text not null,
 foreign key(entry_id,organization_id,unit_id) references private.finance_entries(id,organization_id,unit_id),unique(series_id,position)
);
create index finance_series_items_entry on private.finance_series_items(entry_id,organization_id,unit_id);
alter table private.finance_f2_commands enable row level security;
alter table private.finance_settlements enable row level security;
alter table private.finance_series_items enable row level security;
create policy finance_f2_commands_deny on private.finance_f2_commands as restrictive for all using(false) with check(false);
create policy finance_settlements_deny on private.finance_settlements as restrictive for all using(false) with check(false);
create policy finance_series_deny on private.finance_series_items as restrictive for all using(false) with check(false);
revoke all on private.finance_f2_commands,private.finance_settlements,private.finance_series_items from public,anon,authenticated,service_role;

-- Reporting view is private and never granted to clients. Forecasts are outstanding principal,
-- actual flow is independent balanced settlement entries (including the fee expense).
do $$declare columns text;begin
 select string_agg(case when attname='amount_cents' then 'case when e.status=''pending'' then e.amount_cents-coalesce(s.paid,0) else e.amount_cents end as amount_cents' when attname='status' then 'case when e.status=''pending'' and e.amount_cents=coalesce(s.paid,0) then ''settled'' else e.status end as status' else 'e.'||quote_ident(attname) end,',' order by attnum)
 into columns from pg_attribute where attrelid='private.finance_entries'::regclass and attnum>0 and not attisdropped;
 execute 'create view private.finance_reporting_entries as select '||columns||',e.amount_cents::text as original_amount_cents, (e.amount_cents-coalesce(s.paid,0))::text as remaining_cents,si.series_id,si.position as installment,si.count as installments,si.mode as series_mode,cs.id as settlement_id,cs.title_id as settlement_title from private.finance_entries e left join lateral(select sum(principal_cents)::bigint paid from private.finance_settlements where title_id=e.id and reversed_at is null)s on true left join private.finance_series_items si on si.entry_id=e.id left join private.finance_settlements cs on cs.cash_entry=e.id or cs.fee_entry=e.id';
end $$;
revoke all on private.finance_reporting_entries from public,anon,authenticated,service_role;
alter function private.finance_f1(uuid,uuid[],text,jsonb) rename to finance_f1_base;
revoke all on function private.finance_f1_base(uuid,uuid[],text,jsonb) from public,anon,authenticated,service_role;
do $$declare src text;begin
 src:=pg_get_functiondef('private.finance_f1_base(uuid,uuid[],text,jsonb)'::regprocedure);
 if strpos(src,'from private.finance_entries e')=0 then raise exception 'unexpected_f1_definition';end if;
 src:=replace(src,'from private.finance_entries e','from private.finance_reporting_entries e');
 src:=replace(src,'where e.organization_id=p_org and e.unit_id=any(p_units)','where e.organization_id=p_org and e.unit_id=any(p_units) and (coalesce(p_data->>''scope'','''')<>''titles'' or (e.kind in(''income'',''expense'') and e.settlement_id is null))');execute src;
end $$;
create function private.finance_f1(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if p_action='void' then
  perform private.require_confirmed_self_service_email();
  if cardinality(p_units) is distinct from 1 or not private.church_ledger_allowed(p_org,p_units[1]) then raise exception 'finance_access_denied' using errcode='42501';end if;
  perform 1 from public.organizations where id=p_org for update;
  if exists(select 1 from private.finance_settlements where organization_id=p_org and unit_id=p_units[1] and ((title_id=(p_data->>'id')::uuid and reversed_at is null) or cash_entry=(p_data->>'id')::uuid or fee_entry=(p_data->>'id')::uuid)) then raise exception 'use_settlement_reversal_first' using errcode='22023';end if;
 end if;
 return private.finance_f1_base(p_org,p_units,p_action,p_data);
end $$;
revoke all on function private.finance_f1(uuid,uuid[],text,jsonb) from public,anon,service_role;
grant execute on function private.finance_f1(uuid,uuid[],text,jsonb) to authenticated;

create function private.finance_f2(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare ent private.finance_entries;payment private.finance_settlements;receipt private.finance_f2_commands;
 req uuid;title uuid;cash uuid;fee_entry uuid;hash text;outstanding bigint;principal bigint;interest bigint;fine bigint;discount bigint;fee bigint;gross bigint;effective date;memo text;payload jsonb;result jsonb;items jsonb:='[]';rows jsonb;
 i integer;count integer;amount bigint;part bigint;due date;start_date date;mode text;frequency text;
begin
 perform private.require_confirmed_self_service_email();
 if p_org is null or p_unit is null or p_action is null or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16384 or not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 if p_action='history' then
  perform 1 from public.organizations where id=p_org for share;
  perform private.require_confirmed_self_service_email();
  if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
  select * into ent from private.finance_entries where id=(p_data->>'title')::uuid and organization_id=p_org and unit_id=p_unit and kind in('income','expense');
  if not found then raise exception 'title_not_found' using errcode='42501';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'principal',s.principal_cents::text,'interest',s.interest_cents::text,'fine',s.fine_cents::text,'discount',s.discount_cents::text,'fee',s.fee_cents::text,'gross',e.amount_cents::text,'date',e.paid_date,'account',c.name,'method',e.method,'reason',s.reason,'reversed',s.reversed_at is not null,'reversedDate',e.reversed_date,'cashEntry',s.cash_entry,'feeEntry',s.fee_entry) order by s.created_at,s.id),'[]') into rows from private.finance_settlements s join private.finance_entries e on e.id=s.cash_entry join private.finance_catalog c on c.id=e.account_id where s.title_id=ent.id;
  select ent.amount_cents-coalesce(sum(principal_cents),0) into outstanding from private.finance_settlements where title_id=ent.id and reversed_at is null;
  return jsonb_build_object('title',ent.id,'version',ent.version,'original',ent.amount_cents::text,'remaining',outstanding::text,'status',ent.status,'payments',rows);
 end if;
 perform 1 from public.organizations where id=p_org for update;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 req:=(p_data->>'id')::uuid;hash:=encode(extensions.digest(p_data::text,'sha256'),'hex');
 if req is null then raise exception 'missing_request' using errcode='22023';end if;
 select * into receipt from private.finance_f2_commands where id=req;
 if found then
  if receipt.organization_id<>p_org or receipt.unit_id<>p_unit or receipt.action<>p_action or receipt.fingerprint<>hash then raise exception 'request_conflict' using errcode='22023';end if;
  return receipt.result;
 end if;
 result:=jsonb_build_object('id',req,'ok',true);
 if p_action='series' then
  count:=(p_data->>'count')::integer;mode:=p_data->>'mode';frequency:=p_data->>'frequency';payload:=p_data->'entry';amount:=(payload->>'amountCents')::bigint;start_date:=(payload->>'due')::date;
  if count is null or count not between 2 and 60 or mode is null or mode not in('installments','recurring') or frequency is null or frequency not in('monthly','weekly') or amount is null or amount not between 1 and 999999999999 or start_date is null or (mode='installments' and amount<count) or payload->>'kind' not in('income','expense') or nullif(payload->>'paid','') is not null then raise exception 'invalid_series' using errcode='22023';end if;
  -- Reserve receipt within the same transaction; exceptions roll back all occurrences.
  insert into private.finance_f2_commands values(req,p_org,p_unit,p_action,hash,result,now());
  for i in 0..count-1 loop
   due:=case when frequency='weekly' then start_date+7*i else (start_date+make_interval(months=>i))::date end;
   part:=case when mode='recurring' then amount else amount/count+case when i<amount%count then 1 else 0 end end;
   cash:=extensions.gen_random_uuid();
   perform private.finance_f1_base(p_org,array[p_unit],'entry',payload||jsonb_build_object('id',cash,'amountCents',part::text,'description',left(payload->>'description',270)||' · '||(i+1)||'/'||count,'due',due,'competence',case when mode='recurring' then due else (payload->>'competence')::date end,'paid',''));
   insert into private.finance_series_items values(cash,p_org,p_unit,req,i+1,count,mode);
   items:=items||jsonb_build_array(jsonb_build_object('id',cash,'due',due,'amount',part::text));
  end loop;
  result:=result||jsonb_build_object('items',items);payload:=result;update private.finance_f2_commands set result=payload where id=req;
 else
  memo:=btrim(p_data->>'reason');effective:=nullif(p_data->>'date','')::date;
  if memo is null or length(memo) not between 2 and 300 then raise exception 'reason_required' using errcode='22023';end if;
  if p_action='reverse' then
   select * into payment from private.finance_settlements where id=(p_data->>'settlement')::uuid and organization_id=p_org and unit_id=p_unit for update;
   if not found or payment.reversed_at is not null or effective is null or effective>current_date then raise exception 'invalid_reversal' using errcode='22023';end if;
   select * into ent from private.finance_entries where id=payment.title_id for update;
   select * into strict receipt from private.finance_f2_commands where id=payment.id;
   -- Reversal of cash and its fee is indivisible and retains all original entries.
   perform private.finance_f1_base(p_org,array[p_unit],'void',jsonb_build_object('id',payment.cash_entry,'version',1,'reason',memo,'date',effective,'requestId',extensions.gen_random_uuid()));
   if payment.fee_entry is not null then perform private.finance_f1_base(p_org,array[p_unit],'void',jsonb_build_object('id',payment.fee_entry,'version',1,'reason',memo,'date',effective,'requestId',extensions.gen_random_uuid()));end if;
   update private.finance_settlements set reversed_at=now() where id=payment.id;
   update private.finance_entries set version=version+1 where id=ent.id;
   result:=result||jsonb_build_object('title',ent.id);
  else
   title:=(p_data->>'title')::uuid;
   select * into ent from private.finance_entries where id=title and organization_id=p_org and unit_id=p_unit and kind in('income','expense') for update;
   if not found or ent.status<>'pending' or ent.version is distinct from (p_data->>'version')::integer then raise exception 'title_conflict' using errcode='40001';end if;
   select ent.amount_cents-coalesce(sum(principal_cents),0) into outstanding from private.finance_settlements where title_id=ent.id and reversed_at is null;
   if outstanding<=0 then raise exception 'title_already_settled' using errcode='22023';end if;
   if p_action='reschedule' then
    due:=(p_data->>'due')::date;if due is null then raise exception 'invalid_due_date' using errcode='22023';end if;
    result:=result||jsonb_build_object('oldDue',ent.due_date,'newDue',due);
    update private.finance_entries set due_date=due,version=version+1 where id=ent.id;
   elsif p_action='settle' then
    principal:=(p_data->>'principal')::bigint;interest:=(p_data->>'interest')::bigint;fine:=(p_data->>'fine')::bigint;discount:=(p_data->>'discount')::bigint;fee:=(p_data->>'fee')::bigint;
    gross:=principal+interest+fine-discount;
    if principal is null or interest is null or fine is null or discount is null or fee is null or principal not between 1 and outstanding or interest not between 0 and 999999999999 or fine not between 0 and 999999999999 or discount not between 0 and principal or fee not between 0 and 999999999999 or gross not between 1 and 999999999999 or (ent.kind='income' and fee>=gross) or effective is null or effective>current_date then raise exception 'invalid_settlement' using errcode='22023';end if;
    if (select count(*) from private.finance_settlements where title_id=ent.id)>=200 then raise exception 'settlement_limit' using errcode='22023';end if;
    cash:=extensions.gen_random_uuid();fee_entry:=null;
    -- Frozen identity/party remains historical, including a member since archived.
    payload:=jsonb_build_object('id',cash,'kind',ent.kind,'amountCents',gross::text,'description',left(ent.description,270)||' · baixa','account',p_data->>'account','category',ent.category_id,'center',coalesce(ent.center_id::text,''),'party',ent.party_name,'method',p_data->>'method','competence',ent.competence_date,'due',ent.due_date,'paid',effective,'notes','F2 · título '||ent.id||' · '||memo);
    perform private.finance_f1_base(p_org,array[p_unit],'entry',payload);
    update private.finance_entries set person_id=ent.person_id,supplier_id=ent.supplier_id where id=cash;
    if fee>0 then
     fee_entry:=extensions.gen_random_uuid();
     perform private.finance_f1_base(p_org,array[p_unit],'entry',payload||jsonb_build_object('id',fee_entry,'kind','expense','amountCents',fee::text,'description',left(ent.description,270)||' · taxa','category',p_data->>'feeCategory'));
    end if;
    insert into private.finance_settlements values(req,p_org,p_unit,ent.id,principal,interest,fine,discount,fee,cash,fee_entry,memo,auth.uid(),now(),null);
    update private.finance_entries set version=version+1 where id=ent.id;
    result:=result||jsonb_build_object('title',ent.id,'remaining',(outstanding-principal)::text,'gross',gross::text,'fee',fee::text,'net',(gross+case when ent.kind='income' then -fee else fee end)::text);
   else raise exception 'invalid_action' using errcode='22023';end if;
  end if;
  insert into private.finance_f2_commands values(req,p_org,p_unit,p_action,hash,result,now());
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'finance.f2.'||p_action,'finance_f2',req::text,jsonb_build_object('unit_id',p_unit,'title',ent.id,'reason',memo,'result',result));
 return result;
end $$;
revoke all on function private.finance_f2(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.finance_f2(uuid,uuid,text,jsonb) to authenticated;
create function public.finance_f2(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_f2(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.finance_f2(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.finance_f2(uuid,uuid,text,jsonb) to authenticated;
