-- Earmarking is NOT a bank transfer, bank balance, second receipt or expense.
set local lock_timeout='5s';
create table private.finance_digital_destinations(
 receipt_id uuid primary key references private.finance_digital_receipts(id),
 organization_id uuid not null references public.organizations(id),source_unit uuid not null,beneficiary_unit uuid not null,
 version integer not null default 1,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 foreign key(source_unit,organization_id) references public.organization_units(id,organization_id),
 foreign key(beneficiary_unit,organization_id) references public.organization_units(id,organization_id)
);
create index finance_digital_destinations_org on private.finance_digital_destinations(organization_id);
create index finance_digital_destinations_source on private.finance_digital_destinations(source_unit,organization_id);
create index finance_digital_destinations_beneficiary on private.finance_digital_destinations(beneficiary_unit,organization_id);
create index finance_digital_destinations_creator on private.finance_digital_destinations(created_by);
alter table private.finance_digital_destinations enable row level security;
create policy finance_digital_destinations_deny on private.finance_digital_destinations as restrictive for all using(false) with check(false);
revoke all on private.finance_digital_destinations from public,anon,authenticated,service_role;

create function private.finance_digital_destination(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o private.finance_digital_orders;r private.finance_digital_receipts;c private.finance_receivers;d private.finance_digital_destinations;target uuid;old_target uuid;v integer;
begin
 perform private.finance_digital(p_org,p_unit,'list','{}');
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>2048 then raise exception 'invalid_destination' using errcode='22023';end if;
 if p_action='list' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc,q.receipt_id) from(
   select allocation.receipt_id,allocation.source_unit,allocation.beneficiary_unit,allocation.version,allocation.created_at,s.name source_name,b.name beneficiary_name,
   (receipt.posted_gross-receipt.posted_fee-receipt.posted_refund)::text net_cents,receipt.review_reason,
   case when allocation.source_unit=allocation.beneficiary_unit then 'retained' else 'earmarked_not_transferred' end state
   from private.finance_digital_destinations allocation join private.finance_digital_receipts receipt on receipt.id=allocation.receipt_id
   join public.organization_units s on s.id=allocation.source_unit join public.organization_units b on b.id=allocation.beneficiary_unit
   where allocation.organization_id=p_org and (allocation.source_unit=p_unit or allocation.beneficiary_unit=p_unit)
   order by allocation.created_at desc,allocation.receipt_id limit 100
  )q),'[]'));
 end if;
 if p_action<>'set' or (p_data-array['receipt','target','version'])<>'{}'::jsonb then raise exception 'invalid_destination' using errcode='22023';end if;
 select ord.* into o from private.finance_digital_orders ord join private.finance_digital_receipts rec on rec.order_id=ord.id where rec.id=(p_data->>'receipt')::uuid and ord.organization_id=p_org and ord.unit_id=p_unit;
 if not found then raise exception 'destination_denied' using errcode='42501';end if;
 select * into r from private.finance_digital_receipts where id=(p_data->>'receipt')::uuid for update;
 select * into c from private.finance_receivers where id=o.receiver_id for share;
 target:=(p_data->>'target')::uuid;v:=(p_data->>'version')::integer;
 if target is null or v is null or v<0 then raise exception 'invalid_destination' using errcode='22023';end if;
 if not private.receiver_actor_allowed(auth.uid(),p_org,p_unit) or not private.receiver_actor_allowed(auth.uid(),p_org,target) or not (target=c.unit_id or target=any(c.beneficiary_units)) or c.organization_id<>p_org or c.status<>'configured' or not c.holder_confirmed then raise exception 'destination_denied' using errcode='42501';end if;
 perform 1 from public.organization_units where id=target and organization_id=p_org for update;
 if o.environment<>'production' or r.posted_gross=0 or r.review_reason is not null then raise exception 'verified_receipt_required' using errcode='22023';end if;
 select * into d from private.finance_digital_destinations where receipt_id=r.id for update;
 if found then
  if d.version<>v then raise exception 'destination_conflict' using errcode='40001';end if;
  old_target:=d.beneficiary_unit;
  update private.finance_digital_destinations set beneficiary_unit=target,version=version+1 where receipt_id=r.id returning * into d;
 else
  if v<>0 then raise exception 'destination_conflict' using errcode='40001';end if;
  insert into private.finance_digital_destinations(receipt_id,organization_id,source_unit,beneficiary_unit,created_by) values(r.id,p_org,p_unit,target,auth.uid()) returning * into d;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'digital.destination','finance_digital_receipt',r.id::text,jsonb_build_object('source',p_unit,'previous',old_target,'beneficiary',target,'version',d.version,'no_bank_transfer',true));
 return jsonb_build_object('ok',true,'version',d.version,'state','earmarked_not_transferred');
end $$;
revoke all on function private.finance_digital_destination(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.finance_digital_destination(uuid,uuid,text,jsonb) to authenticated;
create function public.finance_digital_destination(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.finance_digital_destination(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.finance_digital_destination(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.finance_digital_destination(uuid,uuid,text,jsonb) to authenticated;
