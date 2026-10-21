begin;
set local lock_timeout='5s';
create table private.finance_bank_imports(
 id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,account_id uuid not null references private.finance_catalog(id),
 source_hash text not null check(source_hash ~ '^[0-9a-f]{64}$'),account_hash text not null check(account_hash ~ '^[0-9a-f]{64}$'),filename text not null,account_tail text not null,
 date_from date not null,date_to date not null,balance_date date not null,balance_cents bigint not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(account_id,source_hash),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index finance_bank_imports_scope on private.finance_bank_imports(organization_id,unit_id,account_id,balance_date desc);
create index finance_bank_imports_actor on private.finance_bank_imports(created_by);
create table private.finance_bank_transactions(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,account_id uuid not null references private.finance_catalog(id),import_id uuid not null references private.finance_bank_imports(id),
 fitid text not null check(length(fitid) between 1 and 255),effective_date date not null,amount_cents bigint not null check(amount_cents<>0),memo text not null,reference text not null,fingerprint text not null,
 ignored boolean not null default false,ignore_reason text,version integer not null default 1,
 unique(account_id,fitid),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index finance_bank_transactions_scope on private.finance_bank_transactions(organization_id,unit_id,account_id,effective_date,id);
create index finance_bank_transactions_duplicate_hint on private.finance_bank_transactions(account_id,effective_date,amount_cents);
create index finance_bank_transactions_import on private.finance_bank_transactions(import_id);
create table private.finance_reconciliation_groups(
 id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,account_id uuid not null references private.finance_catalog(id),reason text not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),undone_at timestamptz,undone_by uuid references auth.users(id),undo_reason text,
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index finance_reconciliation_groups_scope on private.finance_reconciliation_groups(organization_id,unit_id,account_id,created_at desc);
create index finance_reconciliation_groups_account on private.finance_reconciliation_groups(account_id);
create index finance_reconciliation_groups_creator on private.finance_reconciliation_groups(created_by);
create index finance_reconciliation_groups_undo_actor on private.finance_reconciliation_groups(undone_by);
create table private.finance_reconciliation_bank_items(group_id uuid not null references private.finance_reconciliation_groups(id),transaction_id uuid not null references private.finance_bank_transactions(id),active boolean not null default true,primary key(group_id,transaction_id));
create unique index finance_bank_match_once on private.finance_reconciliation_bank_items(transaction_id) where active;
create index finance_bank_items_transaction on private.finance_reconciliation_bank_items(transaction_id);
create table private.finance_reconciliation_book_items(group_id uuid not null references private.finance_reconciliation_groups(id),journal_id uuid not null,ledger_account uuid not null,active boolean not null default true,primary key(group_id,journal_id,ledger_account),foreign key(journal_id,ledger_account) references public.church_ledger_lines(journal_id,account_id));
create unique index finance_book_match_once on private.finance_reconciliation_book_items(journal_id,ledger_account) where active;
create index finance_book_items_journal on private.finance_reconciliation_book_items(journal_id,ledger_account);
create table private.finance_f5_commands(id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,action text not null,fingerprint text not null,result jsonb not null,created_at timestamptz not null default now(),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id));
create index finance_f5_commands_scope on private.finance_f5_commands(organization_id,unit_id,created_at desc);
do $$declare t text;begin foreach t in array array['finance_bank_imports','finance_bank_transactions','finance_reconciliation_groups','finance_reconciliation_bank_items','finance_reconciliation_book_items','finance_f5_commands'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('create policy %I on private.%I as restrictive for all using(false) with check(false)',t||'_deny',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end$$;
create trigger finance_bank_imports_immutable before update or delete on private.finance_bank_imports for each row execute function private.finance_history_immutable();
create trigger finance_f5_commands_immutable before update or delete on private.finance_f5_commands for each row execute function private.finance_history_immutable();

-- Read-only checklist: closing is distinct from reconciliation. Missing evidence is explicit.
create function private.finance_f5_checklist(p_org uuid,p_unit uuid,p_from date,p_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare accounts jsonb;bank_pending bigint;book_pending bigint;reviews bigint;ignored bigint;missing bigint;differences bigint;
begin
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'book',coalesce(b.amount,0)::text,'statement',i.balance_cents::text,'balanceDate',i.balance_date,'difference',case when i.id is not null then (i.balance_cents-coalesce(b.amount,0))::text end,'evidence',i.id is not null) order by a.name),'[]') into accounts
 from private.finance_catalog a join private.finance_account_links m on m.catalog_id=a.id and m.unit_id=p_unit
 left join lateral(select sum(l.delta_cents) amount from public.church_ledger_lines l join public.church_ledger_journals j on j.id=l.journal_id where l.account_id=m.ledger_id and j.effective_date<=p_to)b on true
 left join lateral(select * from private.finance_bank_imports bi where bi.account_id=a.id and bi.balance_date=p_to order by bi.created_at desc,bi.id desc limit 1)i on true
 where a.organization_id=p_org and a.unit_id=p_unit and a.kind='account' and (a.active or exists(select 1 from public.church_ledger_lines l join public.church_ledger_journals j on j.id=l.journal_id where l.account_id=m.ledger_id and j.effective_date between p_from and p_to));
 select count(*) into missing from jsonb_array_elements(accounts) x where not(x->>'evidence')::boolean;
 select count(*) into differences from jsonb_array_elements(accounts) x where (x->>'difference')::bigint<>0;
 select count(*) filter(where not t.ignored and not exists(select 1 from private.finance_reconciliation_bank_items b where b.transaction_id=t.id and b.active)),count(*) filter(where t.ignored)
 into bank_pending,ignored from private.finance_bank_transactions t where t.organization_id=p_org and t.unit_id=p_unit and t.effective_date between p_from and p_to;
 select count(*) into book_pending from public.church_ledger_lines l join public.church_ledger_journals j on j.id=l.journal_id join private.finance_account_links m on m.ledger_id=l.account_id and m.unit_id=p_unit join private.finance_catalog c on c.id=m.catalog_id and c.kind='account'
 where j.organization_id=p_org and j.unit_id=p_unit and j.effective_date between p_from and p_to
 and j.reversal_of is null and not exists(select 1 from public.church_ledger_journals reversal where reversal.reversal_of=j.id)
 and not exists(select 1 from private.finance_entries opening where opening.journal_id=j.id and opening.kind='opening')
 and not exists(select 1 from private.finance_reconciliation_book_items b where b.journal_id=l.journal_id and b.ledger_account=l.account_id and b.active);
 select count(*) into reviews from private.finance_digital_orders o join private.finance_digital_receipts r on r.order_id=o.id where o.organization_id=p_org and o.unit_id=p_unit and o.environment='production' and r.review_reason is not null and r.occurred_at::date<=p_to;
 return jsonb_build_object('accounts',accounts,'bankPending',bank_pending,'bookPending',book_pending,'providerReviews',reviews,'ignored',ignored,'missingEvidence',missing,'balanceDifferences',differences,'reconciled',bank_pending+book_pending+reviews+ignored+missing+differences=0);
end$$;
revoke all on function private.finance_f5_checklist(uuid,uuid,date,date) from public,anon,authenticated,service_role;

-- A matched posting must first be unlinked in an open period, even through old APIs.
create function private.finance_guard_reconciled_journal() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.reversal_of is not null and exists(select 1 from private.finance_reconciliation_book_items b where b.journal_id=new.reversal_of and b.active) then raise exception 'undo_reconciliation_first' using errcode='22023';end if;return new;
end$$;
revoke all on function private.finance_guard_reconciled_journal() from public,anon,authenticated,service_role;
create trigger guard_reconciled_journal before insert on public.church_ledger_journals for each row execute function private.finance_guard_reconciled_journal();

alter function public.close_church_ledger_period(uuid,uuid,date) set schema private;
revoke all on function private.close_church_ledger_period(uuid,uuid,date) from public,anon,authenticated,service_role;
create function private.finance_f5_legacy_close(p_org uuid,p_unit uuid,p_through date) returns void language plpgsql security definer set search_path='' as $$
declare checks jsonb;begin
 perform private.require_confirmed_self_service_email();
 -- Legacy callers may already hold the unit. Do not invert unit -> org locks.
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 checks:=private.finance_f5_checklist(p_org,p_unit,coalesce((select closed_through+1 from public.church_ledger_periods where organization_id=p_org and unit_id=p_unit),'-infinity'::date),p_through);
 if not(checks->>'reconciled')::boolean then raise exception 'use_finance_closing_checklist' using errcode='22023';end if;
 perform private.close_church_ledger_period(p_org,p_unit,p_through);
end$$;
revoke all on function private.finance_f5_legacy_close(uuid,uuid,date) from public,anon,service_role;
grant execute on function private.finance_f5_legacy_close(uuid,uuid,date) to authenticated;
create function public.close_church_ledger_period(p_org uuid,p_unit uuid,p_through date) returns void language sql security invoker set search_path='' as $$select private.finance_f5_legacy_close(p_org,p_unit,p_through)$$;
revoke all on function public.close_church_ledger_period(uuid,uuid,date) from public,anon,service_role;
grant execute on function public.close_church_ledger_period(uuid,uuid,date) to authenticated;

create function private.finance_f5(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare req uuid;hash text;receipt private.finance_f5_commands;result jsonb;acc uuid;ledger uuid;v_from date;v_to date;closed date;reason text;item jsonb;old private.finance_bank_transactions;imported integer:=0;duplicates integer:=0;group_row private.finance_reconciliation_groups;
 bank_ids uuid[];book_ids uuid[];bank_sum numeric;book_sum numeric;checks jsonb;rows jsonb;books jsonb;groups jsonb;imports jsonb;v_date date;v_amount bigint;v_fitid text;v_fingerprint text;
begin
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 if p_action is null or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>1500000 then raise exception 'invalid_reconciliation' using errcode='22023';end if;
 perform 1 from public.organizations where id=p_org for no key update;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 select closed_through into closed from public.church_ledger_periods where organization_id=p_org and unit_id=p_unit;closed:=coalesce(closed,'-infinity');
 if p_action='snapshot' then
  acc:=nullif(p_data->>'account','')::uuid;v_from:=(p_data->>'from')::date;v_to:=(p_data->>'to')::date;
  if v_from is null or v_to is null or v_to<v_from or v_to-v_from>366 then raise exception 'invalid_period' using errcode='22023';end if;
  if acc is not null then
   select m.ledger_id into ledger from private.finance_account_links m join private.finance_catalog c on c.id=m.catalog_id where c.id=acc and c.organization_id=p_org and c.unit_id=p_unit and c.kind='account';
   if not found then raise exception 'invalid_account' using errcode='42501';end if;
  end if;
  select coalesce(jsonb_agg(x),'[]') into rows from(select t.id,t.effective_date as date,t.amount_cents::text as amount,t.memo,t.reference,t.ignored,t.ignore_reason,t.version,
   exists(select 1 from private.finance_reconciliation_bank_items b where b.transaction_id=t.id and b.active) as matched,
   exists(select 1 from private.finance_bank_transactions other where other.account_id=t.account_id and other.id<>t.id and other.effective_date=t.effective_date and other.amount_cents=t.amount_cents and other.memo=t.memo) as possible_duplicate
   from private.finance_bank_transactions t where t.organization_id=p_org and t.unit_id=p_unit and t.account_id=acc and t.effective_date between v_from and v_to order by t.effective_date,t.id limit 101)x;
  select coalesce(jsonb_agg(x),'[]') into books from(select j.id,j.effective_date as date,j.memo,l.delta_cents::text as amount,
   (j.reversal_of is not null or exists(select 1 from public.church_ledger_journals reversal where reversal.reversal_of=j.id) or e.kind='opening') is true as internal,
   exists(select 1 from private.finance_reconciliation_book_items b where b.journal_id=j.id and b.ledger_account=ledger and b.active) as matched,
   coalesce(e.kind,original.kind) as kind,coalesce(n.number::text,onum.number::text) as code,
   r.external_id as provider_reference,receiver.provider as provider,dl.receipt_id,
   case when r.id is not null then (select sum(bl.delta_cents)::text from private.finance_digital_links all_links join private.finance_entries be on be.id=all_links.entry_id join public.church_ledger_lines bl on bl.journal_id=be.journal_id and bl.account_id=ledger where all_links.receipt_id=r.id) end as provider_net
   from public.church_ledger_lines l join public.church_ledger_journals j on j.id=l.journal_id
   left join private.finance_entries e on e.journal_id=j.id left join private.finance_entries original on original.journal_id=j.reversal_of
   left join private.finance_record_numbers n on n.entry_id=e.id left join private.finance_record_numbers onum on onum.entry_id=original.id
   left join private.finance_digital_links dl on dl.entry_id=e.id left join private.finance_digital_receipts r on r.id=dl.receipt_id left join private.finance_receivers receiver on receiver.id=r.receiver_id
   where l.organization_id=p_org and l.unit_id=p_unit and l.account_id=ledger and j.effective_date between v_from and v_to order by j.effective_date,j.id limit 101)x;
  select coalesce(jsonb_agg(x),'[]') into groups from(select g.id,g.reason,g.created_at,g.undone_at,g.undo_reason,u.email as actor from private.finance_reconciliation_groups g left join auth.users u on u.id=g.created_by where g.organization_id=p_org and g.unit_id=p_unit and (acc is null or g.account_id=acc) order by g.created_at desc,g.id desc limit 30)x;
  select coalesce(jsonb_agg(x),'[]') into imports from(select id,filename,date_from,date_to,balance_date,balance_cents::text as balance,created_at,account_tail from private.finance_bank_imports where organization_id=p_org and unit_id=p_unit and (acc is null or account_id=acc) order by created_at desc,id desc limit 30)x;
  checks:=private.finance_f5_checklist(p_org,p_unit,case when closed<v_to then case when isfinite(closed) then least(v_from,closed+1) else '-infinity'::date end else v_from end,v_to);
  return jsonb_build_object('bank',rows,'book',books,'groups',groups,'imports',imports,'checklist',checks,'closedThrough',case when isfinite(closed) then closed::text end,'canReopen',private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]),'history',(select coalesce(jsonb_agg(x),'[]') from(select c.action,c.result,c.created_at from private.finance_f5_commands c where c.organization_id=p_org and c.unit_id=p_unit and c.action in('close','reopen') order by c.created_at desc,c.id desc limit 20)x));
 end if;
 req:=(p_data->>'id')::uuid;hash:=encode(extensions.digest(p_data::text,'sha256'),'hex');if req is null then raise exception 'missing_request' using errcode='22023';end if;
 select * into receipt from private.finance_f5_commands where id=req;
 if found then if receipt.organization_id<>p_org or receipt.unit_id<>p_unit or receipt.action<>p_action or receipt.fingerprint<>hash then raise exception 'request_conflict' using errcode='22023';end if;return receipt.result;end if;
 reason:=btrim(p_data->>'reason');result:=jsonb_build_object('ok',true,'id',req,'actor',(select email from auth.users where id=auth.uid()));
 if p_action='import' then
  acc:=(p_data->>'account')::uuid;v_from:=(p_data->>'from')::date;v_to:=(p_data->>'to')::date;
  if not exists(select 1 from private.finance_catalog where id=acc and organization_id=p_org and unit_id=p_unit and kind='account' and active) then raise exception 'invalid_account' using errcode='42501';end if;
  if p_data->>'sourceHash' is null or (p_data->>'sourceHash')!~'^[0-9a-f]{64}$' or p_data->>'accountHash' is null or (p_data->>'accountHash')!~'^[0-9a-f]{64}$' or v_from is null or v_to is null or v_to<v_from or v_to-v_from>366 or (p_data->>'balanceDate')::date<v_from or p_data->>'balance' is null or p_data->>'filename' is null or length(p_data->>'filename') not between 1 and 160 or length(p_data->>'accountTail') not between 1 and 4 or jsonb_typeof(p_data->'transactions') is distinct from 'array' or jsonb_array_length(p_data->'transactions')>1000 then raise exception 'invalid_statement' using errcode='22023';end if;
  if exists(select 1 from private.finance_bank_imports where account_id=acc and account_hash<>p_data->>'accountHash') then raise exception 'different_bank_account' using errcode='22023';end if;
  if exists(select 1 from private.finance_bank_imports where account_id=acc and source_hash=p_data->>'sourceHash') then result:=result||jsonb_build_object('duplicateFile',true,'imported',0,'duplicates',jsonb_array_length(p_data->'transactions'));
  else
   if (p_data->>'balanceDate')::date<=closed then raise exception 'period_closed' using errcode='22023';end if;
   insert into private.finance_bank_imports values(req,p_org,p_unit,acc,p_data->>'sourceHash',p_data->>'accountHash',p_data->>'filename',p_data->>'accountTail',v_from,v_to,(p_data->>'balanceDate')::date,(p_data->>'balance')::bigint,auth.uid(),now());
   for item in select value from jsonb_array_elements(p_data->'transactions') loop
    v_fitid:=item->>'fitid';v_date:=(item->>'date')::date;v_amount:=(item->>'amount')::bigint;v_fingerprint:=encode(extensions.digest(jsonb_build_object('date',v_date,'amount',v_amount,'memo',item->>'memo','reference',item->>'reference')::text,'sha256'),'hex');
    if v_fitid is null or length(v_fitid) not between 1 and 255 or v_date is null or v_date not between v_from and v_to or v_amount is null or v_amount=0 or abs(v_amount)>999999999999 or item->>'memo' is null or length(item->>'memo')>600 or item->>'reference' is null or length(item->>'reference')>255 then raise exception 'invalid_bank_transaction' using errcode='22023';end if;
    select * into old from private.finance_bank_transactions where account_id=acc and fitid=v_fitid;
    if found then if old.fingerprint<>v_fingerprint then raise exception 'bank_transaction_changed' using errcode='22023';end if;duplicates:=duplicates+1;
    else
     if v_date<=closed then raise exception 'period_closed' using errcode='22023';end if;
     insert into private.finance_bank_transactions(organization_id,unit_id,account_id,import_id,fitid,effective_date,amount_cents,memo,reference,fingerprint) values(p_org,p_unit,acc,req,v_fitid,v_date,v_amount,item->>'memo',item->>'reference',v_fingerprint);imported:=imported+1;
    end if;
   end loop;
   result:=result||jsonb_build_object('duplicateFile',false,'imported',imported,'duplicates',duplicates);
  end if;
 elsif p_action='match' then
  if reason is null or length(reason) not between 2 and 300 then raise exception 'reason_required' using errcode='22023';end if;
  acc:=(p_data->>'account')::uuid;
  select m.ledger_id into ledger from private.finance_account_links m join private.finance_catalog c on c.id=m.catalog_id where c.id=acc and c.organization_id=p_org and c.unit_id=p_unit and c.kind='account';if not found then raise exception 'invalid_account' using errcode='42501';end if;
  if jsonb_typeof(p_data->'bank') is distinct from 'array' or jsonb_typeof(p_data->'book') is distinct from 'array' or jsonb_array_length(p_data->'bank') not between 1 and 100 or jsonb_array_length(p_data->'book') not between 1 and 100 then raise exception 'invalid_selection' using errcode='22023';end if;
  select array_agg(value::uuid) into bank_ids from jsonb_array_elements_text(p_data->'bank');select array_agg(value::uuid) into book_ids from jsonb_array_elements_text(p_data->'book');
  if (select count(distinct x) from unnest(bank_ids)x)<>cardinality(bank_ids) or (select count(distinct x) from unnest(book_ids)x)<>cardinality(book_ids) then raise exception 'duplicate_selection' using errcode='22023';end if;
  if (select count(*) from private.finance_bank_transactions t where t.id=any(bank_ids) and t.organization_id=p_org and t.unit_id=p_unit and t.account_id=acc and not t.ignored and t.effective_date>closed and not exists(select 1 from private.finance_reconciliation_bank_items b where b.transaction_id=t.id and b.active))<>cardinality(bank_ids) then raise exception 'bank_selection_changed' using errcode='40001';end if;
  if (select count(*) from public.church_ledger_lines l join public.church_ledger_journals j on j.id=l.journal_id where l.journal_id=any(book_ids) and l.account_id=ledger and l.organization_id=p_org and l.unit_id=p_unit and j.effective_date>closed and j.reversal_of is null and not exists(select 1 from public.church_ledger_journals reversal where reversal.reversal_of=j.id) and not exists(select 1 from private.finance_entries opening where opening.journal_id=j.id and opening.kind='opening') and not exists(select 1 from private.finance_reconciliation_book_items b where b.journal_id=l.journal_id and b.ledger_account=ledger and b.active))<>cardinality(book_ids) then raise exception 'book_selection_changed' using errcode='40001';end if;
  select sum(amount_cents) into bank_sum from private.finance_bank_transactions where id=any(bank_ids);select sum(delta_cents) into book_sum from public.church_ledger_lines where journal_id=any(book_ids) and account_id=ledger;
  if bank_sum is distinct from book_sum then raise exception 'amount_difference' using errcode='22023';end if;
  insert into private.finance_reconciliation_groups(id,organization_id,unit_id,account_id,reason,created_by) values(req,p_org,p_unit,acc,reason,auth.uid());
  insert into private.finance_reconciliation_bank_items select req,x,true from unnest(bank_ids)x;
  insert into private.finance_reconciliation_book_items select req,x,ledger,true from unnest(book_ids)x;
  result:=result||jsonb_build_object('amount',bank_sum::text,'bankCount',cardinality(bank_ids),'bookCount',cardinality(book_ids));
 elsif p_action='undo' then
  select * into group_row from private.finance_reconciliation_groups where id=(p_data->>'group')::uuid and organization_id=p_org and unit_id=p_unit for update;
  if not found or group_row.undone_at is not null then raise exception 'group_changed' using errcode='40001';end if;
  if reason is null or length(reason) not between 10 and 300 then raise exception 'reason_required' using errcode='22023';end if;
  if exists(select 1 from private.finance_reconciliation_bank_items b join private.finance_bank_transactions t on t.id=b.transaction_id where b.group_id=group_row.id and t.effective_date<=closed) or exists(select 1 from private.finance_reconciliation_book_items b join public.church_ledger_journals j on j.id=b.journal_id where b.group_id=group_row.id and j.effective_date<=closed) then raise exception 'period_closed' using errcode='22023';end if;
  update private.finance_reconciliation_groups set undone_at=now(),undone_by=auth.uid(),undo_reason=p_data->>'reason' where id=group_row.id;
  update private.finance_reconciliation_bank_items set active=false where group_id=group_row.id;update private.finance_reconciliation_book_items set active=false where group_id=group_row.id;
  result:=result||jsonb_build_object('group',group_row.id);
 elsif p_action='ignore' then
  select * into old from private.finance_bank_transactions where id=(p_data->>'transaction')::uuid and organization_id=p_org and unit_id=p_unit for update;
  if not found or old.version is distinct from (p_data->>'version')::integer then raise exception 'transaction_changed' using errcode='40001';end if;
  if old.effective_date<=closed or exists(select 1 from private.finance_reconciliation_bank_items where transaction_id=old.id and active) or reason is null or length(reason) not between 10 and 300 or jsonb_typeof(p_data->'ignored') is distinct from 'boolean' then raise exception 'invalid_ignore' using errcode='22023';end if;
  update private.finance_bank_transactions set ignored=(p_data->>'ignored')::boolean,ignore_reason=reason,version=version+1 where id=old.id;
  result:=result||jsonb_build_object('transaction',old.id,'previousIgnored',old.ignored,'ignored',(p_data->>'ignored')::boolean);
 elsif p_action in('close','reopen') then
  v_to:=(p_data->>'through')::date;
  if reason is null or length(reason) not between 10 and 300 or v_to is null or v_to>=current_date or v_to<>(date_trunc('month',v_to)+interval '1 month - 1 day')::date then raise exception 'invalid_month' using errcode='22023';end if;
  if nullif(p_data->>'expectedClosed','')::date is distinct from (case when isfinite(closed) then closed end) then raise exception 'period_changed' using errcode='40001';end if;
  if p_action='close' then
   if v_to<=closed then raise exception 'period_already_closed' using errcode='22023';end if;
   checks:=private.finance_f5_checklist(p_org,p_unit,case when isfinite(closed) then closed+1 else '-infinity'::date end,v_to);
   if not(checks->>'reconciled')::boolean and (coalesce((p_data->>'allowPending')::boolean,false) is not true or not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[])) then raise exception 'closing_pending_review' using errcode='22023';end if;
   perform private.close_church_ledger_period(p_org,p_unit,v_to);
   result:=result||jsonb_build_object('through',v_to,'checklist',checks,'reconciled',(checks->>'reconciled')::boolean,'reason',reason);
  else
   if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) then raise exception 'closing_admin_required' using errcode='42501';end if;
   if v_to>=closed then raise exception 'invalid_reopening' using errcode='22023';end if;
   update public.church_ledger_periods set closed_through=v_to,generation=generation+1 where organization_id=p_org and unit_id=p_unit;
   result:=result||jsonb_build_object('previous',closed,'through',v_to,'reason',reason);
  end if;
 else raise exception 'invalid_reconciliation_action' using errcode='22023';end if;
 insert into private.finance_f5_commands values(req,p_org,p_unit,p_action,hash,result,now());
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'finance.f5.'||p_action,'finance_f5',req::text,jsonb_build_object('unit_id',p_unit,'reason',reason,'result',result));
 return result;
end$$;
revoke all on function private.finance_f5(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.finance_f5(uuid,uuid,text,jsonb) to authenticated;
create function public.finance_f5(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_f5(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.finance_f5(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function public.finance_f5(uuid,uuid,text,jsonb) to authenticated;
-- Bank reconciliation is derived from evidence links, never written into provider payment proof.
create function private.finance_receipt_bank_status(p_receipt uuid) returns text language sql stable security definer set search_path='' as $$
 select case when r.id is null then 'not_posted' when o.environment='sandbox' then 'sandbox' when r.review_reason is not null then 'needs_review'
 when not exists(select 1 from private.finance_digital_links d where d.receipt_id=r.id) then 'not_posted'
 when exists(select 1 from private.finance_digital_links d join private.finance_entries e on e.id=d.entry_id join public.church_ledger_lines l on l.journal_id=e.journal_id join private.finance_account_links m on m.ledger_id=l.account_id join private.finance_catalog c on c.id=m.catalog_id and c.kind='account'
 where d.receipt_id=r.id and not exists(select 1 from private.finance_reconciliation_book_items b where b.journal_id=l.journal_id and b.ledger_account=l.account_id and b.active)) then 'pending' else 'reconciled' end
 from (select p_receipt as id) requested left join private.finance_digital_receipts r on r.id=requested.id left join private.finance_digital_orders o on o.id=r.order_id;
$$;
revoke all on function private.finance_receipt_bank_status(uuid) from public,anon,authenticated,service_role;
do $$declare definition text;needle text:='rec.posted_refund::text from private.finance_digital_orders';begin
 definition:=pg_get_functiondef('private.finance_digital(uuid,uuid,text,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'unexpected_digital_list_definition';end if;
 execute replace(definition,needle,'rec.posted_refund::text,private.finance_receipt_bank_status(rec.id) as bank_reconciliation from private.finance_digital_orders');
end$$;
commit;
