begin;
set local lock_timeout='5s';
create table private.finance_budgets(
 id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 month date not null check(extract(day from month)=1),category_id uuid not null,center_id uuid,
 amount_cents bigint not null check(amount_cents between 0 and 999999999999),version integer not null default 1,
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),
 foreign key(category_id,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(center_id,organization_id) references private.finance_catalog(id,organization_id)
);
create unique index finance_budget_scope on private.finance_budgets(organization_id,unit_id,month,category_id,coalesce(center_id,'00000000-0000-0000-0000-000000000000'));
create index finance_budget_unit on private.finance_budgets(unit_id,organization_id);
create index finance_budget_category on private.finance_budgets(category_id,organization_id);
create index finance_budget_center on private.finance_budgets(center_id,organization_id);
create index finance_budget_actor on private.finance_budgets(updated_by);
alter table private.finance_budgets enable row level security;
create policy finance_budgets_deny on private.finance_budgets as restrictive for all using(false) with check(false);
revoke all on private.finance_budgets from public,anon,authenticated,service_role;

-- Immutable journals are the source of actual cash. Reversals retain their signed dates.
-- Unavailable historical metadata is explicit rather than attributed to a revised entry.
create view private.finance_report_cash as
select j.organization_id,j.unit_id,j.id as journal_id,j.effective_date as cash_date,j.created_by,
 l.account_id as ledger_account,a.catalog_id as account_id,l.delta_cents as signed_cents,
 e.id as entry_id,n.number::text as code,j.memo as description,e.competence_date,e.due_date,
 case when coalesce(e.kind,'')='opening' or exists(select 1 from public.church_ledger_lines cl join public.church_ledger_accounts ca on ca.id=cl.account_id where cl.journal_id=j.id and ca.name like 'F1 · Abertura · %') then 'opening'
 when exists(select 1 from public.church_ledger_lines cl join public.church_ledger_accounts ca on ca.id=cl.account_id where cl.journal_id=j.id and ca.kind='income') then 'income'
 when exists(select 1 from public.church_ledger_lines cl join public.church_ledger_accounts ca on ca.id=cl.account_id where cl.journal_id=j.id and ca.kind='expense') then 'expense'
 when coalesce(e.kind,'')='opening' then 'opening' else 'transfer' end as kind,
 cat.catalog_id as category_id,e.center_id,e.person_id,e.supplier_id,e.party_name,e.method,
 j.reversal_of is not null as reversal,e.id is null as metadata_missing,
 r.id as receipt_id,o.purpose_id,o.source_reference,p.origin,r.snapshot->>'state' as payment_state,r.snapshot->>'settlement' as settlement,
 receiver.provider,coalesce(r.snapshot->>'method',e.method) as payment_method,
 exists(select 1 from private.finance_reconciliation_book_items b where b.journal_id=j.id and b.ledger_account=l.account_id and b.active) as reconciled
from public.church_ledger_journals j join public.church_ledger_lines l on l.journal_id=j.id
join private.finance_account_links a on a.ledger_id=l.account_id
join private.finance_catalog ac on ac.id=a.catalog_id and ac.kind='account'
left join private.finance_entries e on e.journal_id=coalesce(j.reversal_of,j.id)
left join private.finance_record_numbers n on n.entry_id=e.id
left join lateral(select m.catalog_id from public.church_ledger_lines c join public.church_ledger_accounts k on k.id=c.account_id and k.kind in('income','expense') join private.finance_account_links m on m.ledger_id=c.account_id where c.journal_id=j.id limit 1)cat on true
left join private.finance_digital_links dl on dl.entry_id=e.id
left join private.finance_digital_receipts r on r.id=dl.receipt_id
left join private.finance_digital_orders o on o.id=r.order_id
left join private.finance_purposes p on p.id=o.purpose_id
left join private.finance_receivers receiver on receiver.id=r.receiver_id;
revoke all on private.finance_report_cash from public,anon,authenticated,service_role;

create function private.finance_f6(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid;v_from date;v_to date;date_by text;rows jsonb;digital jsonb;budgets jsonb;divergences jsonb;balances jsonb;accounting jsonb;identities boolean;old private.finance_budgets;req uuid;cat uuid;center uuid;amount bigint;v_month date;reason text;
begin
 perform private.require_confirmed_self_service_email();
 if p_units is null or cardinality(p_units) not between 1 and 100 or exists(select 1 from unnest(p_units)x where x is null) or (select count(distinct x) from unnest(p_units)x)<>cardinality(p_units) then raise exception 'invalid_scope' using errcode='22023';end if;
 foreach u in array p_units loop if not private.church_ledger_allowed(p_org,u) then raise exception 'finance_scope_denied' using errcode='42501';end if;end loop;
 identities:=private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]);
 if p_action='budget' then
  if cardinality(p_units)<>1 or not identities then raise exception 'budget_admin_required' using errcode='42501';end if;
  perform 1 from public.organizations where id=p_org for no key update;
  if not private.church_ledger_allowed(p_org,p_units[1]) or not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) then raise exception 'finance_scope_denied' using errcode='42501';end if;
  req:=(p_data->>'id')::uuid;cat:=(p_data->>'category')::uuid;center:=nullif(p_data->>'center','')::uuid;amount:=(p_data->>'amountCents')::bigint;v_month:=(p_data->>'month')::date;reason:=btrim(p_data->>'reason');
  if req is null or amount is null or amount not between 0 and 999999999999 or v_month is null or extract(day from v_month)<>1 or reason is null or length(reason) not between 10 and 300 then raise exception 'invalid_budget' using errcode='22023';end if;
  if not exists(select 1 from private.finance_catalog where id=cat and organization_id=p_org and kind='category' and active and (unit_id is null or unit_id=p_units[1])) or (center is not null and not exists(select 1 from private.finance_catalog where id=center and organization_id=p_org and kind='center' and active and (unit_id is null or unit_id=p_units[1]))) then raise exception 'invalid_classification' using errcode='22023';end if;
  select * into old from private.finance_budgets where id=req for update;
  if found then
   if old.organization_id<>p_org or old.unit_id<>p_units[1] or old.version is distinct from (p_data->>'version')::integer or old.category_id<>cat or old.center_id is distinct from center or old.month<>v_month then raise exception 'budget_changed' using errcode='40001';end if;
   update private.finance_budgets set amount_cents=amount,version=version+1,updated_by=auth.uid(),updated_at=now() where id=req;
  else
   if coalesce((p_data->>'version')::integer,-1)<>0 then raise exception 'budget_changed' using errcode='40001';end if;
   insert into private.finance_budgets(id,organization_id,unit_id,month,category_id,center_id,amount_cents,updated_by) values(req,p_org,p_units[1],v_month,cat,center,amount,auth.uid());
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'finance.budget_saved','finance_budget',req::text,jsonb_build_object('unit_id',p_units[1],'before',to_jsonb(old),'amount',amount::text,'reason',reason));
  return jsonb_build_object('ok',true,'id',req,'version',coalesce(old.version,0)+1);
 end if;
 if p_action<>'report' or p_action is null then raise exception 'invalid_action' using errcode='22023';end if;
 -- Consistent report across statements: writers take org before unit locks too.
 perform 1 from public.organizations where id=p_org for share;
 perform 1 from public.organization_units where organization_id=p_org and id=any(p_units) order by id for share;
 perform private.require_confirmed_self_service_email();
 foreach u in array p_units loop if not private.church_ledger_allowed(p_org,u) then raise exception 'finance_scope_denied' using errcode='42501';end if;end loop;
 v_from:=(p_data->>'from')::date;v_to:=(p_data->>'to')::date;date_by:=p_data->>'dateBy';
 if v_from is null or v_to is null or v_to<v_from or v_to-v_from>366 or date_by is null or date_by not in('cash','competence','due') then raise exception 'invalid_period' using errcode='22023';end if;
 if p_data->>'report'='budget' and exists(select 1 from jsonb_each_text(p_data) f where f.key in('person','supplier','purpose','provider','method','origin','reference','status','min','max','responsible','account') and nullif(f.value,'') is not null) then raise exception 'budget_classification_filters_only' using errcode='22023';end if;
 if p_data->>'report'='divergences' and (date_by<>'cash' or exists(select 1 from jsonb_each_text(p_data) f where f.key in('category','subcategory','center','person','supplier','purpose','provider','method','origin','reference','status','min','max','responsible') and nullif(f.value,'') is not null)) then raise exception 'bank_scope_filters_only' using errcode='22023';end if;
 if p_data->>'report'='members' and not identities then raise exception 'individual_contributions_restricted' using errcode='42501';end if;
 if nullif(p_data->>'person','') is not null and not identities then raise exception 'individual_contributions_restricted' using errcode='42501';end if;
 -- Every filter applies before totals and exports. No partial success for unauthorized units.
 with cash as(select c.entry_id as id,c.journal_id,c.code,c.unit_id,c.cash_date,c.competence_date,c.due_date,
   case date_by when 'competence' then c.competence_date when 'due' then c.due_date else c.cash_date end as date,
   c.signed_cents,c.kind,'actual'::text as basis,case when c.reversal then 'reversed' else 'posted' end as status,
   c.description,c.account_id,c.category_id,c.center_id,c.person_id,c.supplier_id,c.party_name,c.payment_method as method,c.created_by,
   c.purpose_id,c.source_reference,c.origin,c.provider,c.payment_state,c.settlement,c.reconciled,c.metadata_missing,c.receipt_id
   from private.finance_report_cash c where c.organization_id=p_org and c.unit_id=any(p_units)
  union all
  select e.id,null::uuid,n.number::text,e.unit_id,null::date,e.competence_date,e.due_date,
   case date_by when 'competence' then e.competence_date else e.due_date end,
   case when e.kind='expense' then -e.amount_cents else e.amount_cents end,e.kind,'forecast','pending',e.description,e.account_id,e.category_id,e.center_id,e.person_id,e.supplier_id,e.party_name,e.method,e.created_by,
   null::uuid,null::text,null::text,null::text,null::text,null::text,false,false,null::uuid
   from private.finance_reporting_entries e left join private.finance_record_numbers n on n.entry_id=e.id
   where e.organization_id=p_org and e.unit_id=any(p_units) and e.status='pending' and e.amount_cents>0 and e.settlement_id is null),
 filtered as(select c.* from cash c where c.date between v_from and v_to
  and (nullif(p_data->>'account','') is null or c.account_id=(p_data->>'account')::uuid)
  and (nullif(p_data->>'category','') is null or c.category_id=(p_data->>'category')::uuid or exists(select 1 from private.finance_catalog k where k.id=c.category_id and k.parent_id=(p_data->>'category')::uuid))
  and (nullif(p_data->>'subcategory','') is null or c.category_id=(p_data->>'subcategory')::uuid)
  and (nullif(p_data->>'center','') is null or c.center_id=(p_data->>'center')::uuid)
  and (nullif(p_data->>'person','') is null or c.person_id=(p_data->>'person')::uuid)
  and (nullif(p_data->>'supplier','') is null or c.supplier_id=(p_data->>'supplier')::uuid)
  and (nullif(p_data->>'purpose','') is null or c.purpose_id=(p_data->>'purpose')::uuid)
  and (nullif(p_data->>'responsible','') is null or c.created_by=(p_data->>'responsible')::uuid)
  and (nullif(p_data->>'provider','') is null or c.provider=p_data->>'provider')
  and (nullif(p_data->>'method','') is null or c.method=p_data->>'method')
  and (nullif(p_data->>'origin','') is null or c.origin=p_data->>'origin')
  and (nullif(p_data->>'reference','') is null or strpos(lower(coalesce(c.source_reference,'')),lower(p_data->>'reference'))>0)
  and (nullif(p_data->>'status','') is null or c.status=p_data->>'status' or c.payment_state=p_data->>'status')
  and (nullif(p_data->>'min','') is null or abs(c.signed_cents)>=(p_data->>'min')::bigint)
  and (nullif(p_data->>'max','') is null or abs(c.signed_cents)<=(p_data->>'max')::bigint)
  order by c.date,c.unit_id,c.journal_id,c.id,c.account_id limit 10001)
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'journal',f.journal_id,'code',f.code,'unit',f.unit_id,'unitName',u.name,'date',f.date,'cashDate',f.cash_date,'due',f.due_date,'competence',f.competence_date,
  'amount',f.signed_cents::text,'kind',f.kind,'basis',f.basis,'status',f.status,'description',f.description,
  'account',f.account_id,'accountName',a.name,'category',f.category_id,'categoryName',coalesce(parent.name,k.name),'subcategoryName',case when parent.id is not null then k.name end,
  'center',f.center_id,'centerName',center.name,'person',case when identities then f.person_id end,'party',case when identities then coalesce(person.full_name,f.party_name) end,
  'supplier',f.supplier_id,'supplierName',supplier.name,'method',f.method,'responsible',f.created_by,'purpose',f.purpose_id,'reference',f.source_reference,'origin',f.origin,'provider',f.provider,
  'paymentState',f.payment_state,'settlement',f.settlement,'reconciled',f.reconciled,'metadataMissing',f.metadata_missing,'receipt',f.receipt_id) order by f.date,f.unit_id,f.journal_id,f.id,f.account_id),'[]') into rows
 from filtered f join public.organization_units u on u.id=f.unit_id
 left join private.finance_catalog a on a.id=f.account_id left join private.finance_catalog k on k.id=f.category_id left join private.finance_catalog parent on parent.id=k.parent_id
 left join private.finance_catalog center on center.id=f.center_id left join private.finance_catalog supplier on supplier.id=f.supplier_id left join public.people person on person.id=f.person_id;
 if jsonb_array_length(rows)>10000 then raise exception 'report_limit_reduce_period' using errcode='54000';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'unit',b.unit_id,'month',b.month,'category',b.category_id,'center',b.center_id,'amount',b.amount_cents::text,'version',b.version,'categoryName',c.name,'centerName',cc.name)),'[]') into budgets
 from private.finance_budgets b join private.finance_catalog c on c.id=b.category_id left join private.finance_catalog cc on cc.id=b.center_id
 where b.organization_id=p_org and b.unit_id=any(p_units) and b.month between date_trunc('month',v_from)::date and v_to
 and (nullif(p_data->>'category','') is null or b.category_id=(p_data->>'category')::uuid or c.parent_id=(p_data->>'category')::uuid)
 and (nullif(p_data->>'subcategory','') is null or b.category_id=(p_data->>'subcategory')::uuid)
 and (nullif(p_data->>'center','') is null or b.center_id=(p_data->>'center')::uuid);
 -- Provider values are taken once per receipt, never multiplied by gross/fee journal links.
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'gross',r.snapshot->>'gross','fees',r.snapshot->'fees','net',r.snapshot->>'net','refunded',r.snapshot->>'refunded','state',r.snapshot->>'state','provider',receiver.provider,'unit',o.unit_id,'purpose',o.purpose_id,'reference',o.source_reference,'review',r.review_reason,'settlement',r.snapshot->>'settlement')),'[]') into digital
 from private.finance_digital_receipts r join private.finance_digital_orders o on o.id=r.order_id join private.finance_receivers receiver on receiver.id=r.receiver_id
 where o.organization_id=p_org and o.unit_id=any(p_units) and o.environment='production'
 and case date_by when 'cash' then coalesce(nullif(r.snapshot->>'paidDate','')::date,(r.occurred_at at time zone 'America/Sao_Paulo')::date) else (o.created_at at time zone 'America/Sao_Paulo')::date end between v_from and v_to
 and (nullif(p_data->>'account','') is null or o.classification->>'account_id'=p_data->>'account')
 and (nullif(p_data->>'category','') is null or o.classification->>'category_id'=p_data->>'category' or exists(select 1 from private.finance_catalog c where c.id=nullif(o.classification->>'category_id','')::uuid and c.parent_id=(p_data->>'category')::uuid))
 and (nullif(p_data->>'subcategory','') is null or o.classification->>'subcategory_id'=p_data->>'subcategory')
 and (nullif(p_data->>'center','') is null or o.classification->>'center_id'=p_data->>'center')
 and (nullif(p_data->>'person','') is null or o.person_id=(p_data->>'person')::uuid)
 and nullif(p_data->>'supplier','') is null
 and (nullif(p_data->>'responsible','') is null or o.created_by=(p_data->>'responsible')::uuid)
 and (nullif(p_data->>'purpose','') is null or o.purpose_id=(p_data->>'purpose')::uuid)
 and (nullif(p_data->>'provider','') is null or receiver.provider=p_data->>'provider')
 and (nullif(p_data->>'method','') is null or r.snapshot->>'method'=p_data->>'method')
 and (nullif(p_data->>'origin','') is null or o.classification->>'origin'=p_data->>'origin')
 and (nullif(p_data->>'reference','') is null or strpos(lower(o.source_reference),lower(p_data->>'reference'))>0)
 and (nullif(p_data->>'status','') is null or r.snapshot->>'state'=p_data->>'status')
 and (nullif(p_data->>'min','') is null or o.gross>=(p_data->>'min')::bigint)
 and (nullif(p_data->>'max','') is null or o.gross<=(p_data->>'max')::bigint);
 -- Independent bank evidence is filterable by account/date; other dimensions do not exist in OFX.
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'unit',t.unit_id,'account',t.account_id,'date',t.effective_date,'amount',t.amount_cents::text,'memo',t.memo,'ignored',t.ignored,'reason',t.ignore_reason)),'[]') into divergences
 from private.finance_bank_transactions t where t.organization_id=p_org and t.unit_id=any(p_units) and t.effective_date between v_from and v_to
 and (nullif(p_data->>'account','') is null or t.account_id=(p_data->>'account')::uuid)
 and not exists(select 1 from private.finance_reconciliation_bank_items b where b.transaction_id=t.id and b.active);
 if jsonb_array_length(digital)>10000 or jsonb_array_length(divergences)>10000 then raise exception 'report_limit_reduce_period' using errcode='54000';end if;
 select coalesce(jsonb_agg(jsonb_build_object('unit',c.unit_id,'unitName',u.name,'account',c.id,'name',c.name,'opening',coalesce(b.opening,0)::text,'closing',coalesce(b.closing,0)::text)),'[]') into balances
 from private.finance_catalog c join public.organization_units u on u.id=c.unit_id join private.finance_account_links m on m.catalog_id=c.id
 left join lateral(select sum(l.delta_cents) filter(where j.effective_date<v_from) as opening,sum(l.delta_cents) as closing from public.church_ledger_lines l join public.church_ledger_journals j on j.id=l.journal_id where l.account_id=m.ledger_id and j.effective_date<=v_to)b on true
 where c.organization_id=p_org and c.unit_id=any(p_units) and c.kind='account' and (nullif(p_data->>'account','') is null or c.id=(p_data->>'account')::uuid);
 select coalesce(jsonb_agg(jsonb_build_object('journal',j.id,'date',j.effective_date,'unit',u.name,'memo',j.memo,'account',a.name,'kind',a.kind,'delta',l.delta_cents::text) order by j.effective_date,j.id,a.kind,a.name),'[]') into accounting
 from public.church_ledger_journals j join public.organization_units u on u.id=j.unit_id join public.church_ledger_lines l on l.journal_id=j.id join public.church_ledger_accounts a on a.id=l.account_id
 where j.organization_id=p_org and j.unit_id=any(p_units) and exists(select 1 from jsonb_array_elements(rows)x where x->>'journal'=j.id::text);
 return jsonb_build_object('rows',rows,'digital',digital,'budgets',budgets,'bankPending',divergences,'balances',balances,'accounting',accounting,'individualAccess',identities,'generatedAt',clock_timestamp(),'units',p_units,'filters',p_data,
 'purposes',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name)),'[]') from private.finance_purposes where organization_id=p_org and unit_id=any(p_units)),
 'responsibles',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',coalesce(a.raw_user_meta_data->>'full_name',a.email))),'[]') from auth.users a where exists(select 1 from private.finance_entries e where e.organization_id=p_org and e.unit_id=any(p_units) and e.created_by=a.id)),
 'historicalMetadataMissing',(select count(*) from jsonb_array_elements(rows)x where (x->>'metadataMissing')::boolean));
end$$;
revoke all on function private.finance_f6(uuid,uuid[],text,jsonb) from public,anon,service_role;
grant execute on function private.finance_f6(uuid,uuid[],text,jsonb) to authenticated;
create function public.finance_f6(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_f6(p_org,p_units,p_action,p_data)$$;
revoke all on function public.finance_f6(uuid,uuid[],text,jsonb) from public,anon,service_role;
grant execute on function public.finance_f6(uuid,uuid[],text,jsonb) to authenticated;
commit;
