-- Digital receipts. No charge execution or fabricated provider activation.
set local lock_timeout='5s';
create table private.finance_purposes(
 id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 name text not null check(length(btrim(name)) between 2 and 120),origin text not null check(origin in('tithe','offering','donation','campaign','event','other')),
 account_id uuid not null,category_id uuid not null,subcategory_id uuid,center_id uuid,fee_category uuid not null,refund_category uuid not null,credit_category uuid not null,
 active boolean not null default true,version integer not null default 1,created_by uuid not null references auth.users(id),
 unique(id,organization_id,unit_id),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),
 foreign key(account_id,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(category_id,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(subcategory_id,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(center_id,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(fee_category,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(refund_category,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(credit_category,organization_id) references private.finance_catalog(id,organization_id)
);
create index finance_purposes_unit on private.finance_purposes(unit_id,organization_id);
create index finance_purposes_org on private.finance_purposes(organization_id);
create table private.finance_digital_orders(
 id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,purpose_id uuid not null,
 receiver_id uuid not null references private.finance_receivers(id),environment text not null check(environment in('sandbox','production')),
 gross bigint not null check(gross between 1 and 999999999999),person_id uuid,party_name text not null default '',source_reference text not null default '',
 classification jsonb not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(id,organization_id,unit_id),foreign key(purpose_id,organization_id,unit_id) references private.finance_purposes(id,organization_id,unit_id),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),foreign key(person_id,organization_id) references public.people(id,organization_id)
);
create index finance_digital_orders_unit on private.finance_digital_orders(unit_id,organization_id,created_at desc);
create index finance_digital_orders_org on private.finance_digital_orders(organization_id);
create index finance_digital_orders_purpose on private.finance_digital_orders(purpose_id,organization_id,unit_id);
create index finance_digital_orders_receiver on private.finance_digital_orders(receiver_id);
create index finance_digital_orders_person on private.finance_digital_orders(person_id,organization_id);
create table private.finance_digital_receipts(
 id uuid primary key default extensions.gen_random_uuid(),order_id uuid not null unique references private.finance_digital_orders(id),receiver_id uuid not null references private.finance_receivers(id),
 external_id text not null,version integer not null default 1,snapshot jsonb not null,occurred_at timestamptz not null,
 review_reason text,posted_gross bigint not null default 0,posted_fee bigint not null default 0,posted_refund bigint not null default 0,
 updated_at timestamptz not null default now(),unique(receiver_id,external_id)
);
create table private.finance_digital_events(
 id bigint generated always as identity primary key,receipt_id uuid not null references private.finance_digital_receipts(id),actor_id uuid references auth.users(id),
 event text not null,details jsonb not null,created_at timestamptz not null default now()
);
create index finance_digital_events_receipt on private.finance_digital_events(receipt_id,id desc);
create index finance_digital_events_actor on private.finance_digital_events(actor_id);
create table private.finance_digital_links(
 entry_id uuid primary key references private.finance_entries(id),receipt_id uuid not null references private.finance_digital_receipts(id),kind text not null,
 unique(receipt_id,entry_id)
);
do $$declare t text; c text;begin
 foreach t in array array['finance_purposes','finance_digital_orders','finance_digital_receipts','finance_digital_events','finance_digital_links'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('create policy %I on private.%I as restrictive for all using(false) with check(false)',t||'_deny',t);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 end loop;
 -- Every FK gets a covering index, including catalog mappings.
 foreach c in array array['account_id','category_id','subcategory_id','center_id','fee_category','refund_category','credit_category'] loop
  execute format('create index %I on private.finance_purposes(%I,organization_id)','finance_purposes_'||c,c);
 end loop;
end $$;
create index finance_purposes_creator on private.finance_purposes(created_by);
create index finance_digital_orders_creator on private.finance_digital_orders(created_by);
revoke all on sequence private.finance_digital_events_id_seq from public,anon,authenticated,service_role;
create trigger digital_events_immutable before update or delete on private.finance_digital_events for each row execute function private.finance_history_immutable();
create trigger digital_orders_immutable before update or delete on private.finance_digital_orders for each row execute function private.finance_history_immutable();

create function private.digital_catalog(p_org uuid,p_unit uuid,p_id uuid,p_kind text,p_direction text default null) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.finance_catalog where id=p_id and organization_id=p_org and (unit_id=p_unit or unit_id is null) and kind=p_kind and active and (p_direction is null or direction=p_direction));
$$;
revoke all on function private.digital_catalog(uuid,uuid,uuid,text,text) from public,anon,authenticated,service_role;

-- Internal system posting: callers cannot choose org, mappings, actor or signed amount.
-- Only verified receipt processing invokes this primitive, while holding org/unit locks.
create function private.digital_post(p_order private.finance_digital_orders,p_receipt uuid,p_kind text,p_amount bigint,p_date date) returns uuid language plpgsql security definer set search_path='' as $$
declare id uuid:=extensions.gen_random_uuid();cat uuid;asset uuid;counter uuid;k text;memo text;
begin
 if p_amount<=0 or p_amount>999999999999 or p_date>current_date then raise exception 'invalid_digital_amount' using errcode='22023';end if;
 k:=case when p_kind in('gross','fee_credit') then 'income' else 'expense' end;
 cat:=case p_kind when 'gross' then coalesce(nullif(p_order.classification->>'subcategory_id','')::uuid,(p_order.classification->>'category_id')::uuid) when 'fee' then (p_order.classification->>'fee_category')::uuid when 'refund' then (p_order.classification->>'refund_category')::uuid when 'fee_credit' then (p_order.classification->>'credit_category')::uuid end;
 if cat is null or not private.digital_catalog(p_order.organization_id,p_order.unit_id,cat,'category',k) or not private.digital_catalog(p_order.organization_id,p_order.unit_id,(p_order.classification->>'account_id')::uuid,'account') then raise exception 'classification_unavailable' using errcode='22023';end if;
 if nullif(p_order.classification->>'center_id','') is not null and not private.digital_catalog(p_order.organization_id,p_order.unit_id,(p_order.classification->>'center_id')::uuid,'center') then raise exception 'classification_unavailable' using errcode='22023';end if;
 insert into public.church_ledger_periods(organization_id,unit_id) values(p_order.organization_id,p_order.unit_id) on conflict do nothing;
 update public.church_ledger_periods set generation=generation+1 where organization_id=p_order.organization_id and unit_id=p_order.unit_id;
 if exists(select 1 from public.church_ledger_periods where organization_id=p_order.organization_id and unit_id=p_order.unit_id and closed_through>=p_date) then raise exception 'period_closed' using errcode='22023';end if;
 select ledger_id into asset from private.finance_account_links where catalog_id=(p_order.classification->>'account_id')::uuid and unit_id=p_order.unit_id;
 select ledger_id into counter from private.finance_account_links where catalog_id=cat and unit_id=p_order.unit_id;
 if counter is null then
  counter:=extensions.gen_random_uuid();insert into public.church_ledger_accounts(id,organization_id,unit_id,name,kind) values(counter,p_order.organization_id,p_order.unit_id,'F4 · Categoria · '||cat::text,k);
  insert into private.finance_account_links values(cat,p_order.organization_id,p_order.unit_id,counter);
 end if;
 if asset is null then raise exception 'account_unavailable' using errcode='22023';end if;
 memo:=left('Recebimento digital · '||p_kind||' · '||(p_order.classification->>'name'),300);
 insert into public.church_ledger_journals(id,organization_id,unit_id,effective_date,memo,fingerprint,created_by) values(id,p_order.organization_id,p_order.unit_id,p_date,memo,'digital:'||id::text,p_order.created_by);
 insert into public.church_ledger_lines values(id,p_order.organization_id,p_order.unit_id,asset,case when k='income' then p_amount else -p_amount end),(id,p_order.organization_id,p_order.unit_id,counter,case when k='income' then -p_amount else p_amount end);
 insert into private.finance_entries(id,organization_id,unit_id,kind,amount_cents,description,account_id,category_id,center_id,person_id,party_name,method,notes,competence_date,due_date,paid_date,status,journal_id,fingerprint,created_by)
 values(id,p_order.organization_id,p_order.unit_id,k,p_amount,memo,(p_order.classification->>'account_id')::uuid,cat,nullif(p_order.classification->>'center_id','')::uuid,p_order.person_id,p_order.party_name,'other','F4 · Pedido '||p_order.id::text,p_date,p_date,p_date,'posted',id,'digital:'||id::text,p_order.created_by);
 insert into private.finance_digital_links values(id,p_receipt,p_kind);
 return id;
end $$;
revoke all on function private.digital_post(private.finance_digital_orders,uuid,text,bigint,date) from public,anon,authenticated,service_role;
create function private.digital_entry_guard() returns trigger language plpgsql set search_path='' as $$begin
 if exists(select 1 from private.finance_digital_links where entry_id=old.id) then raise exception 'digital_adjustment_required' using errcode='42501';end if;return case when tg_op='DELETE' then old else new end;
end $$;
revoke all on function private.digital_entry_guard() from public,anon,authenticated,service_role;
create trigger digital_entry_guard before update or delete on private.finance_entries for each row execute function private.digital_entry_guard();

create function private.digital_apply(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.finance_digital_receipts;o private.finance_digital_orders;s jsonb;fee bigint;refund bigint;gross bigint;day date;detail text;
begin
 select * into r from private.finance_digital_receipts where id=p_id for update;
 select * into o from private.finance_digital_orders where id=r.order_id;
 s:=r.snapshot;
 if o.environment='sandbox' then update private.finance_digital_receipts set review_reason='sandbox_no_ledger' where id=r.id;return jsonb_build_object('ok',true,'review','sandbox_no_ledger');end if;
 if not exists(select 1 from private.finance_receivers c where c.id=o.receiver_id and c.status='configured' and o.unit_id=any(c.beneficiary_units) and c.holder_confirmed and private.receiver_actor_allowed(c.created_by,o.organization_id,o.unit_id)) then update private.finance_digital_receipts set review_reason='receiver_or_access_unavailable' where id=r.id;return jsonb_build_object('ok',true,'review','receiver_or_access_unavailable');end if;
 if s->>'state'='disputed' then update private.finance_digital_receipts set review_reason='dispute_requires_review' where id=r.id;return jsonb_build_object('ok',true,'review','dispute_requires_review');end if;
 if s->>'state' not in('approved','partially_refunded','refunded') or s->>'settlement' not in('available','settled') then update private.finance_digital_receipts set review_reason=case when r.posted_gross>0 then 'state_changed_after_posting' else null end where id=r.id;return jsonb_build_object('ok',true);end if;
 if jsonb_typeof(s->'fees') is distinct from 'array' then update private.finance_digital_receipts set review_reason='fees_unknown' where id=r.id;return jsonb_build_object('ok',true,'review','fees_unknown');end if;
 select coalesce(sum((v->>'amount')::bigint),0) into fee from jsonb_array_elements(s->'fees')v;
 gross:=o.gross;refund:=(s->>'refunded')::bigint;day:=nullif(s->>'paidDate','')::date;
 if r.posted_gross=0 and (nullif(s->>'net','') is null or refund>0 or (s->>'net')::bigint<>gross-fee) then update private.finance_digital_receipts set review_reason='net_or_refund_requires_review' where id=r.id;return jsonb_build_object('ok',true,'review','net_or_refund_requires_review');end if;
 if day is null or day>current_date or fee>gross or refund<r.posted_refund then update private.finance_digital_receipts set review_reason='amount_or_date_divergence' where id=r.id;return jsonb_build_object('ok',true,'review','amount_or_date_divergence');end if;
 begin
  if r.posted_gross=0 then perform private.digital_post(o,r.id,'gross',gross,day);end if;
  if fee>r.posted_fee then perform private.digital_post(o,r.id,'fee',fee-r.posted_fee,case when r.posted_gross=0 then day else (r.occurred_at at time zone 'America/Sao_Paulo')::date end);
  elsif fee<r.posted_fee then perform private.digital_post(o,r.id,'fee_credit',r.posted_fee-fee,(r.occurred_at at time zone 'America/Sao_Paulo')::date);end if;
  if refund>r.posted_refund then perform private.digital_post(o,r.id,'refund',refund-r.posted_refund,(r.occurred_at at time zone 'America/Sao_Paulo')::date);end if;
  update private.finance_digital_receipts set posted_gross=gross,posted_fee=fee,posted_refund=refund,review_reason=null where id=r.id;
  insert into private.finance_digital_events(receipt_id,actor_id,event,details) values(r.id,auth.uid(),'ledger_applied',jsonb_build_object('gross',gross::text,'fee',fee::text,'refunded',refund::text));
 exception when sqlstate '22023' or check_violation or foreign_key_violation then
  get stacked diagnostics detail=message_text;
  update private.finance_digital_receipts set review_reason=case when detail='period_closed' then 'period_closed' else 'classification_unavailable' end where id=r.id;
 end;
 return jsonb_build_object('ok',true,'id',r.id);
end $$;
revoke all on function private.digital_apply(uuid) from public,anon,authenticated,service_role;

create function private.finance_digital(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare x private.finance_purposes;r private.finance_receivers;o private.finance_digital_orders;uid uuid;cat uuid;sub uuid;center uuid;account uuid;fee uuid;refund uuid;credit uuid;party text;person uuid;res jsonb;
begin
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'digital_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for update;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'digital_denied' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16384 then raise exception 'invalid_input' using errcode='22023';end if;
 if p_action='list' then
  return jsonb_build_object('purposes',coalesce((select jsonb_agg(to_jsonb(p) order by name,id) from private.finance_purposes p where organization_id=p_org and unit_id=p_unit),'[]'),
  'receivers',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'provider',c.provider,'environment',c.environment,'holder',c.holder,'status',c.status))from private.finance_receivers c where c.organization_id=p_org and p_unit=any(c.beneficiary_units) and c.status='configured'),'[]'),
  'items',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id) from(select ord.id,ord.gross::text,ord.environment,ord.party_name,ord.source_reference,ord.created_at,ord.classification->>'name' purpose,ord.classification->>'origin' origin,rec.id receipt_id,rec.snapshot,rec.review_reason,rec.version,rec.posted_gross::text,rec.posted_fee::text,rec.posted_refund::text from private.finance_digital_orders ord left join private.finance_digital_receipts rec on rec.order_id=ord.id where ord.organization_id=p_org and ord.unit_id=p_unit and (nullif(p_data->>'from','') is null or (ord.created_at at time zone 'America/Sao_Paulo')::date>=(p_data->>'from')::date) and (nullif(p_data->>'to','') is null or (ord.created_at at time zone 'America/Sao_Paulo')::date<=(p_data->>'to')::date) and (nullif(p_data->>'before','') is null or ord.created_at<(p_data->>'before')::timestamptz) order by ord.created_at desc,ord.id limit 100)q),'[]'));
 end if;
 uid:=(p_data->>'id')::uuid;
 if p_action='purpose' then
  if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) then raise exception 'purpose_denied' using errcode='42501';end if;
  cat:=(p_data->>'category')::uuid;sub:=nullif(p_data->>'subcategory','')::uuid;center:=nullif(p_data->>'center','')::uuid;account:=(p_data->>'account')::uuid;fee:=(p_data->>'feeCategory')::uuid;refund:=(p_data->>'refundCategory')::uuid;credit:=(p_data->>'creditCategory')::uuid;
  if not private.digital_catalog(p_org,p_unit,cat,'category','income') or exists(select 1 from private.finance_catalog where id=cat and parent_id is not null) or not private.digital_catalog(p_org,p_unit,account,'account') or not private.digital_catalog(p_org,p_unit,fee,'category','expense') or not private.digital_catalog(p_org,p_unit,refund,'category','expense') or not private.digital_catalog(p_org,p_unit,credit,'category','income') or (center is not null and not private.digital_catalog(p_org,p_unit,center,'center')) or (sub is not null and (not private.digital_catalog(p_org,p_unit,sub,'category','income') or not exists(select 1 from private.finance_catalog where id=sub and parent_id=cat))) then raise exception 'invalid_classification' using errcode='22023';end if;
  select * into x from private.finance_purposes where id=uid;
  if found then
   if x.organization_id<>p_org or x.unit_id<>p_unit then raise exception 'purpose_denied' using errcode='42501';end if;
   if x.version is distinct from (p_data->>'version')::integer then raise exception 'purpose_conflict' using errcode='40001';end if;
   update private.finance_purposes set name=btrim(p_data->>'name'),origin=p_data->>'origin',account_id=account,category_id=cat,subcategory_id=sub,center_id=center,fee_category=fee,refund_category=refund,credit_category=credit,active=(p_data->>'active')::boolean,version=version+1 where id=uid;
  else
   if (p_data->>'version')::integer is distinct from 0 then raise exception 'purpose_conflict' using errcode='40001';end if;
   insert into private.finance_purposes(id,organization_id,unit_id,name,origin,account_id,category_id,subcategory_id,center_id,fee_category,refund_category,credit_category,created_by,active) values(uid,p_org,p_unit,btrim(p_data->>'name'),p_data->>'origin',account,cat,sub,center,fee,refund,credit,auth.uid(),(p_data->>'active')::boolean);
  end if;
 elsif p_action='order' then
  select * into o from private.finance_digital_orders where id=uid;
  if found then
   if o.organization_id<>p_org or o.unit_id<>p_unit or o.purpose_id is distinct from (p_data->>'purpose')::uuid or o.receiver_id is distinct from (p_data->>'receiver')::uuid or o.gross is distinct from (p_data->>'gross')::bigint or o.person_id is distinct from nullif(p_data->>'person','')::uuid or o.source_reference is distinct from coalesce(p_data->>'sourceReference','') or (o.person_id is null and o.party_name is distinct from coalesce(p_data->>'party','')) then raise exception 'order_conflict' using errcode='40001';end if;
   return jsonb_build_object('ok',true,'id',o.id);
  end if;
  select * into x from private.finance_purposes where id=(p_data->>'purpose')::uuid and organization_id=p_org and unit_id=p_unit and active;
  if not found then raise exception 'purpose_unavailable' using errcode='22023';end if;
  select * into r from private.finance_receivers where id=(p_data->>'receiver')::uuid and organization_id=p_org and status='configured' and holder_confirmed and p_unit=any(beneficiary_units);
  if not found then raise exception 'receiver_unavailable' using errcode='42501';end if;
  if r.account_id is distinct from x.account_id then raise exception 'receiver_destination_divergence' using errcode='22023';end if;
  person:=nullif(p_data->>'person','')::uuid;party:=coalesce(p_data->>'party','');
  if person is not null then
   if not private.target_unit_module_enabled(p_org,p_unit,'people') then raise exception 'person_denied' using errcode='42501';end if;
   select full_name into party from public.people where id=person and organization_id=p_org and unit_id=p_unit and status='active';if not found then raise exception 'person_denied' using errcode='42501';end if;
  end if;
  insert into private.finance_digital_orders(id,organization_id,unit_id,purpose_id,receiver_id,environment,gross,person_id,party_name,source_reference,classification,created_by) values(uid,p_org,p_unit,x.id,r.id,r.environment,(p_data->>'gross')::bigint,person,party,coalesce(p_data->>'sourceReference',''),to_jsonb(x),auth.uid());
 elsif p_action='retry' then
  select ord.* into o from private.finance_digital_orders ord join private.finance_digital_receipts rec on rec.order_id=ord.id where rec.id=uid and ord.organization_id=p_org and ord.unit_id=p_unit;
  if not found then raise exception 'receipt_denied' using errcode='42501';end if;
  return private.digital_apply(uid);
 else raise exception 'invalid_action' using errcode='22023';end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'digital.'||p_action,'finance_digital',uid::text,jsonb_build_object('unit',p_unit));
 return jsonb_build_object('ok',true,'id',uid);
end $$;
revoke all on function private.finance_digital(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.finance_digital(uuid,uuid,text,jsonb) to authenticated;
create function public.finance_digital(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.finance_digital(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.finance_digital(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.finance_digital(uuid,uuid,text,jsonb) to authenticated;

-- This endpoint accepts ONLY provider snapshots independently fetched by trusted server code.
create function private.finance_digital_ingest(p_receiver uuid,p_snapshot jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare c private.finance_receivers;o private.finance_digital_orders;r private.finance_digital_receipts;fee jsonb;gross bigint;refund bigint;at timestamptz;ext text;
begin
 select * into c from private.finance_receivers where id=p_receiver;
 if not found then raise exception 'receiver_unavailable' using errcode='42501';end if;
 select * into o from private.finance_digital_orders where id=(p_snapshot->>'reference')::uuid and receiver_id=c.id;
 if not found then raise exception 'order_unavailable' using errcode='42501';end if;
 perform 1 from public.organizations where id=o.organization_id for update;
 perform 1 from public.organization_units where id=o.unit_id and organization_id=o.organization_id for update;
 select * into c from private.finance_receivers where id=p_receiver for share;
 if c.status<>'configured' or not c.holder_confirmed or c.expires_at is null or c.expires_at<=clock_timestamp() or not o.unit_id=any(c.beneficiary_units) or not private.receiver_actor_allowed(c.created_by,c.organization_id,c.unit_id) then raise exception 'receiver_unavailable' using errcode='42501';end if;
 if jsonb_typeof(p_snapshot) is distinct from 'object' or octet_length(p_snapshot::text)>32768 or p_snapshot->>'environment' is distinct from c.environment or p_snapshot->>'receiverExternalId' is distinct from c.external_id or p_snapshot->>'currency' is distinct from 'BRL' then raise exception 'proof_divergence' using errcode='22023';end if;
 gross:=(p_snapshot->>'gross')::bigint;refund:=(p_snapshot->>'refunded')::bigint;at:=(p_snapshot->>'occurredAt')::timestamptz;ext:=p_snapshot->>'externalId';
 if (p_snapshot->>'state'='refunded' and refund is distinct from gross) or (p_snapshot->>'state'='partially_refunded' and (refund is null or refund<=0 or refund>=gross)) then raise exception 'refund_state_divergence' using errcode='22023';end if;
 if gross is distinct from o.gross or refund is null or refund<0 or refund>gross or at is null or at>clock_timestamp()+interval '5 minutes' or ext is null or ext !~ '^[A-Za-z0-9_-]{1,100}$' or coalesce(p_snapshot->>'state','') not in('pending','processing','approved','rejected','expired','cancelled','partially_refunded','refunded','disputed') or coalesce(p_snapshot->>'settlement','') not in('expected','available','settled') then raise exception 'invalid_proof' using errcode='22023';end if;
 if jsonb_typeof(p_snapshot->'fees') not in('null','array') or not p_snapshot ? 'fees' then raise exception 'invalid_fees' using errcode='22023';end if;
 if jsonb_typeof(p_snapshot->'fees')='array' then
  if jsonb_array_length(p_snapshot->'fees')>30 then raise exception 'invalid_fees' using errcode='22023';end if;
  for fee in select value from jsonb_array_elements(p_snapshot->'fees') loop if coalesce(fee->>'amount','')!~'^[0-9]{1,12}$' or (fee->>'amount')::bigint>gross or coalesce(length(fee->>'kind'),0) not between 1 and 60 then raise exception 'invalid_fees' using errcode='22023';end if;end loop;
 end if;
 select * into r from private.finance_digital_receipts where order_id=o.id for update;
 if found then
  if r.external_id<>ext then raise exception 'order_payment_conflict' using errcode='40001';end if;
  if at<r.occurred_at then return jsonb_build_object('ok',true,'stale',true);end if;
  if at=r.occurred_at then
   if r.snapshot<>p_snapshot then raise exception 'same_version_conflict' using errcode='40001';end if;
   return jsonb_build_object('ok',true,'duplicate',true,'id',r.id);
  end if;
  update private.finance_digital_receipts set snapshot=p_snapshot,occurred_at=at,version=version+1,updated_at=now() where id=r.id;
 else
  insert into private.finance_digital_receipts(order_id,receiver_id,external_id,snapshot,occurred_at) values(o.id,c.id,ext,p_snapshot,at) returning * into r;
 end if;
 insert into private.finance_digital_events(receipt_id,event,details) values(r.id,'provider_verified',p_snapshot);
 return private.digital_apply(r.id);
end $$;
revoke all on function private.finance_digital_ingest(uuid,jsonb) from public,anon,authenticated;
grant execute on function private.finance_digital_ingest(uuid,jsonb) to service_role;
create function public.finance_digital_ingest(p_receiver uuid,p_snapshot jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_digital_ingest(p_receiver,p_snapshot)$$;
revoke all on function public.finance_digital_ingest(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.finance_digital_ingest(uuid,jsonb) to service_role;

create function private.finance_digital_connection(p_receiver uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare c private.finance_receivers;begin
 select * into c from private.finance_receivers where id=p_receiver;
 if not found or c.status<>'configured' or not c.holder_confirmed or not private.receiver_actor_allowed(c.created_by,c.organization_id,c.unit_id) or c.expires_at is null or c.expires_at<=now() then raise exception 'receiver_unavailable' using errcode='42501';end if;
 return jsonb_build_object('org',c.organization_id,'unit',c.unit_id,'provider',c.provider,'environment',c.environment,'externalId',c.external_id,'beneficiaries',c.beneficiary_units,'sealed',(select sealed from private.finance_receiver_secrets where receiver_id=c.id));
end $$;
revoke all on function private.finance_digital_connection(uuid) from public,anon,authenticated;
grant execute on function private.finance_digital_connection(uuid) to service_role;
create function public.finance_digital_connection(p_receiver uuid) returns jsonb language sql security invoker set search_path='' as $$select private.finance_digital_connection(p_receiver)$$;
revoke all on function public.finance_digital_connection(uuid) from public,anon,authenticated;
grant execute on function public.finance_digital_connection(uuid) to service_role;
