begin;
set local lock_timeout='5s';
-- Manual corrections retain stable identity, numbering and attachments. Journals are reversed,
-- never rewritten. Old callers keep the strictly pending-only API.
create function private.finance_revise_entry(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
<<revision>>
declare ent private.finance_entries;receipt private.finance_f2_commands;payment record;
 req uuid;hash text;result jsonb;uid uuid:=p_unit;v_id uuid;amount bigint;account uuid;destination uuid;category uuid;center uuid;supplier uuid;person uuid;party text;k text;v_status text;
 effective date;competence date;due date;memo text;method text;notes text;reason text;link uuid;other_link uuid;
 had_payments boolean;interest bigint;fine bigint;discount bigint;fee bigint;fee_category uuid;current_version integer;
begin
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>8192 or exists(select 1 from jsonb_object_keys(p_data) as keys(field) where keys.field not in('id','title','version','amountCents','description','kind','account','destination','category','center','supplier','person','party','competence','due','paid','method','notes','reason')) then raise exception 'invalid_revision' using errcode='22023';end if;
 perform 1 from public.organizations where id=p_org for update;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 req:=(p_data->>'id')::uuid;v_id:=req;hash:=encode(extensions.digest(p_data::text,'sha256'),'hex');
 reason:=btrim(p_data->>'reason');
 if req is null or reason is null or length(reason) not between 2 and 300 or not(p_data ? 'paid') then raise exception 'invalid_revision' using errcode='22023';end if;
 select * into receipt from private.finance_f2_commands where id=req;
 if found then
  if receipt.organization_id<>p_org or receipt.unit_id<>p_unit or receipt.action<>'revise_entry' or receipt.fingerprint<>hash then raise exception 'request_conflict' using errcode='22023';end if;
  return receipt.result;
 end if;
 select * into ent from private.finance_entries where id=(p_data->>'title')::uuid and organization_id=p_org and unit_id=p_unit for update;
 if not found then raise exception 'entry_unavailable' using errcode='42501';end if;
 if ent.version is distinct from (p_data->>'version')::integer then raise exception 'entry_changed' using errcode='40001';end if;
 if ent.status not in('pending','posted') or ent.reversal_id is not null
 or exists(select 1 from private.finance_digital_links where entry_id=ent.id)
 or exists(select 1 from private.finance_settlements where cash_entry=ent.id or fee_entry=ent.id)
 then raise exception 'entry_revision_not_allowed' using errcode='22023';end if;
 -- Existing settlement adjustments are retained on a re-settlement, never silently discarded.
 select exists(select 1 from private.finance_settlements where title_id=ent.id and reversed_at is null) into had_payments;
 select coalesce(sum(interest_cents),0),coalesce(sum(fine_cents),0),coalesce(sum(discount_cents),0),coalesce(sum(fee_cents),0)
 into interest,fine,discount,fee from private.finance_settlements where title_id=ent.id and reversed_at is null;
 if had_payments and p_data->>'kind' not in('income','expense') then raise exception 'settled_title_kind' using errcode='22023';end if;
 if had_payments and nullif(p_data->>'paid','') is not null then
  if (select count(distinct e.category_id) from private.finance_settlements s join private.finance_entries e on e.id=s.fee_entry where s.title_id=ent.id and s.reversed_at is null)>1 then raise exception 'multiple_fee_categories' using errcode='22023';end if;
  select e.category_id into fee_category from private.finance_settlements s join private.finance_entries e on e.id=s.fee_entry where s.title_id=ent.id and s.reversed_at is null limit 1;
 end if;
 -- Reverse at the original dates. A closed period rejects the whole correction atomically.
 if ent.journal_id is not null then
  perform private.post_church_journal(p_org,p_unit,extensions.gen_random_uuid(),ent.paid_date,reason,'[]',ent.journal_id);
 end if;
 for payment in select s.id,e.paid_date from private.finance_settlements s join private.finance_entries e on e.id=s.cash_entry where s.title_id=ent.id and s.reversed_at is null order by s.created_at,s.id loop
  perform private.finance_f2(p_org,p_unit,'reverse',jsonb_build_object('id',extensions.gen_random_uuid(),'settlement',payment.id,'reason',reason,'date',payment.paid_date));
 end loop;
  k:=p_data->>'kind';memo:=btrim(p_data->>'description');amount:=(p_data->>'amountCents')::bigint;
  competence:=(p_data->>'competence')::date;due:=(p_data->>'due')::date;effective:=nullif(p_data->>'paid','')::date;v_status:=case when effective is null then 'pending' else 'posted' end;
  account:=(p_data->>'account')::uuid;destination:=nullif(p_data->>'destination','')::uuid;category:=nullif(p_data->>'category','')::uuid;center:=nullif(p_data->>'center','')::uuid;supplier:=nullif(p_data->>'supplier','')::uuid;person:=nullif(p_data->>'person','')::uuid;party:=btrim(coalesce(p_data->>'party',''));method:=p_data->>'method';notes:=coalesce(p_data->>'notes','');
  if k is null or k not in('income','expense','transfer','opening') or memo is null or length(memo) not between 2 and 300 or amount is null or amount not between 1 and 999999999999 or competence is null or due is null or length(notes)>2000 or length(party)>160 or method is null or method not in('cash','pix','card','boleto','bank','other') or effective>current_date or (k in('transfer','opening') and effective is null) or (person is not null and supplier is not null) then raise exception 'invalid_entry' using errcode='22023';end if;
  if not exists(select 1 from private.finance_catalog where id=account and organization_id=p_org and unit_id=uid and kind='account' and active) then raise exception 'invalid_account' using errcode='22023';end if;
  if k='transfer' then
   if destination is null or destination=account or not exists(select 1 from private.finance_catalog where id=destination and organization_id=p_org and unit_id=uid and kind='account' and active) then raise exception 'invalid_destination' using errcode='22023';end if;
  elsif destination is not null then raise exception 'invalid_destination' using errcode='22023';end if;
  if k in('income','expense') then
   if category is null or not exists(select 1 from private.finance_catalog where id=category and organization_id=p_org and (unit_id=uid or unit_id is null) and kind='category' and active and direction=k) then raise exception 'invalid_category' using errcode='22023';end if;
  elsif category is not null then raise exception 'invalid_category' using errcode='22023';end if;
  if center is not null and not exists(select 1 from private.finance_catalog where id=center and organization_id=p_org and (unit_id=uid or unit_id is null) and kind='center' and active) then raise exception 'invalid_center' using errcode='22023';end if;
  if supplier is not null then
   select name into party from private.finance_catalog where id=supplier and organization_id=p_org and (unit_id=uid or unit_id is null) and kind='supplier' and active;
   if not found then raise exception 'invalid_supplier' using errcode='42501';end if;
  end if;
  if person is not null then
   if not private.target_unit_module_enabled(p_org,uid,'people') then raise exception 'member_access_denied' using errcode='42501';end if;
   select full_name into party from public.people where id=person and organization_id=p_org and unit_id=uid and status='active' for share;
   if not found then raise exception 'member_access_denied' using errcode='42501';end if;
  end if;
  if effective is not null and not had_payments then
   select ledger_id into link from private.finance_account_links where catalog_id=account and unit_id=uid;
   if k='transfer' then select ledger_id into other_link from private.finance_account_links where catalog_id=destination and unit_id=uid;
   elsif k='opening' then
    if exists(select 1 from private.finance_entries where account_id=account and kind='opening' and reversal_id is null and status='posted' and id<>ent.id) then raise exception 'opening_already_exists' using errcode='23505';end if;
    other_link:=public.create_church_ledger_account(p_org,uid,'F1 · Abertura · '||v_id::text,'income');
   else
    select ledger_id into other_link from private.finance_account_links where catalog_id=category and unit_id=uid;
    if other_link is null then
     other_link:=public.create_church_ledger_account(p_org,uid,'F1 · Categoria · '||category::text,k);
     insert into private.finance_account_links values(category,p_org,uid,other_link);
    end if;
   end if;
   perform private.post_church_journal(p_org,uid,v_id,effective,memo,jsonb_build_array(jsonb_build_object('accountId',link,'deltaCents',case when k in('expense','transfer') then -amount else amount end),jsonb_build_object('accountId',other_link,'deltaCents',case when k in('expense','transfer') then amount else -amount end)));
  end if;

 update private.finance_entries set kind=k,amount_cents=amount,description=memo,account_id=account,destination_id=destination,category_id=category,center_id=center,supplier_id=supplier,person_id=person,party_name=party,method=revision.method,notes=revision.notes,competence_date=competence,due_date=due,
 paid_date=case when had_payments then null else effective end,status=case when had_payments then 'pending' else v_status end,
 journal_id=case when not had_payments and effective is not null then req end,
 reversal_id=null,reversed_date=null,void_request=null,void_fingerprint=null,version=version+1 where id=ent.id returning version into current_version;
 if had_payments and effective is not null then
  perform private.finance_f2(p_org,p_unit,'settle',jsonb_build_object('id',extensions.gen_random_uuid(),'title',ent.id,'version',current_version,'reason',reason,'date',effective,'principal',amount::text,'interest',interest::text,'fine',fine::text,'discount',discount::text,'fee',fee::text,'feeCategory',coalesce(fee_category::text,''),'account',account,'method',method));
 end if;
 select version into current_version from private.finance_entries where id=ent.id;
 result:=jsonb_build_object('id',req,'ok',true,'title',ent.id,'version',current_version);
 insert into private.finance_f2_commands values(req,p_org,p_unit,'revise_entry',hash,result,now());
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'finance.entry_revised','finance_entry',ent.id::text,jsonb_build_object('request',req,'unit_id',p_unit,'reason',reason,'previous_journal',ent.journal_id,'replaced_settlements',had_payments,'paid',effective));
 return result;
end$$;
revoke all on function private.finance_revise_entry(uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function private.finance_revise_entry(uuid,uuid,jsonb) to authenticated;
create function public.finance_revise_entry(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_revise_entry(p_org,p_unit,p_data)$$;
revoke all on function public.finance_revise_entry(uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function public.finance_revise_entry(uuid,uuid,jsonb) to authenticated;
commit;
