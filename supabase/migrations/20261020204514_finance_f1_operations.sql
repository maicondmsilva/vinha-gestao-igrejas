-- F1: manual operational finance. No bank transfers or provider charges.
set local lock_timeout='5s';
create table private.finance_catalog (
 id uuid primary key, organization_id uuid not null references public.organizations(id), unit_id uuid,
 kind text not null check(kind in('account','category','center','supplier')),
 name text not null check(length(btrim(name)) between 2 and 120),
 direction text check(direction in('income','expense')), parent_id uuid,
 active boolean not null default true, version integer not null default 1,
 details jsonb not null default '{}', created_at timestamptz not null default now(),
 check(kind<>'account' or unit_id is not null),check((kind='category')=(direction is not null)),
 unique(id,organization_id),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),
 foreign key(parent_id,organization_id) references private.finance_catalog(id,organization_id)
);
create unique index finance_catalog_names on private.finance_catalog(organization_id,coalesce(unit_id,'00000000-0000-0000-0000-000000000000'),kind,coalesce(direction,''),coalesce(parent_id,'00000000-0000-0000-0000-000000000000'),lower(name));
create index finance_catalog_unit on private.finance_catalog(unit_id,organization_id);
create index finance_catalog_parent on private.finance_catalog(parent_id,organization_id);
create table private.finance_account_links (
 catalog_id uuid not null,organization_id uuid not null,unit_id uuid not null,ledger_id uuid not null,
 primary key(catalog_id,unit_id),foreign key(catalog_id,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(ledger_id,organization_id,unit_id) references public.church_ledger_accounts(id,organization_id,unit_id)
);
create index finance_account_links_ledger on private.finance_account_links(ledger_id,organization_id,unit_id);
create index finance_account_links_catalog on private.finance_account_links(catalog_id,organization_id);
create table private.finance_entries (
 id uuid primary key,organization_id uuid not null references public.organizations(id),unit_id uuid not null,
 kind text not null check(kind in('income','expense','transfer','opening')),amount_cents bigint not null check(amount_cents between 1 and 999999999999),
 description text not null check(length(btrim(description)) between 2 and 300),
 account_id uuid not null, destination_id uuid, category_id uuid,center_id uuid,supplier_id uuid,person_id uuid,
 party_name text not null default '', method text not null,notes text not null default '',
 competence_date date not null,due_date date not null,paid_date date,
 status text not null check(status in('pending','posted','cancelled')),journal_id uuid,reversal_id uuid,reversed_date date,
 fingerprint text not null,void_request uuid,void_fingerprint text,version integer not null default 1,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(id,organization_id,unit_id), foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),
 foreign key(account_id,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(destination_id,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(category_id,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(center_id,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(supplier_id,organization_id) references private.finance_catalog(id,organization_id),
 foreign key(person_id,organization_id) references public.people(id,organization_id),
 foreign key(journal_id,organization_id,unit_id) references public.church_ledger_journals(id,organization_id,unit_id),
 foreign key(reversal_id,organization_id,unit_id) references public.church_ledger_journals(id,organization_id,unit_id)
);
create index finance_entries_unit on private.finance_entries(organization_id,unit_id,due_date,id);
create index finance_entries_paid on private.finance_entries(organization_id,unit_id,paid_date);
create index finance_entries_competence on private.finance_entries(organization_id,unit_id,competence_date);
create index finance_entries_reversed on private.finance_entries(organization_id,unit_id,reversed_date) where reversed_date is not null;
create index finance_entries_account on private.finance_entries(account_id,organization_id);
create index finance_entries_destination on private.finance_entries(destination_id,organization_id);
create index finance_entries_category on private.finance_entries(category_id,organization_id);
create index finance_entries_center on private.finance_entries(center_id,organization_id);
create index finance_entries_supplier on private.finance_entries(supplier_id,organization_id);
create index finance_entries_person on private.finance_entries(person_id,organization_id);
create index finance_entries_journal on private.finance_entries(journal_id,organization_id,unit_id);
create index finance_entries_reversal on private.finance_entries(reversal_id,organization_id,unit_id);
create index finance_entries_creator on private.finance_entries(created_by);
alter table private.finance_catalog enable row level security;
alter table private.finance_account_links enable row level security;
alter table private.finance_entries enable row level security;
revoke all on private.finance_catalog,private.finance_account_links,private.finance_entries from public,anon,authenticated,service_role;

create function private.finance_f1(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid; uid uuid; cid uuid; link uuid; other_link uuid; category_link uuid; old private.finance_catalog; ent private.finance_entries;
 result jsonb; catalogs jsonb; records jsonb; totals jsonb; chart jsonb; accounts jsonb; category_stats jsonb;center_stats jsonb;n text; k text; v_direction text; parent uuid; shared boolean;
 v_id uuid; amount bigint; account uuid; destination uuid; category uuid; center uuid; supplier uuid; person uuid; party text; v_status text;
 effective date; competence date; due date; memo text; method text; notes text; v_fingerprint text; v_from date; v_to date; page integer; total_count bigint;
begin
 perform private.require_confirmed_self_service_email();
 if p_units is null or cardinality(p_units) not between 1 and 100 or array_position(p_units,null) is not null or (select count(distinct x) from unnest(p_units)x)<>cardinality(p_units) or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>16384 then raise exception 'invalid_finance_input' using errcode='22023';end if;
 foreach u in array p_units loop
  if not private.church_ledger_allowed(p_org,u) then raise exception 'finance_access_denied' using errcode='42501';end if;
 end loop;
 uid:=p_units[1];
 if p_action in('snapshot','choices') then
  perform 1 from public.organizations where id=p_org for share;
  perform private.require_confirmed_self_service_email();
  foreach u in array p_units loop if not private.church_ledger_allowed(p_org,u) then raise exception 'finance_access_denied' using errcode='42501';end if;end loop;
 end if;
 if p_action='choices' then
  n:=btrim(p_data->>'search');
  if cardinality(p_units)<>1 or n is null or length(n) not between 2 and 80 then raise exception 'invalid_search' using errcode='22023';end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(x) from (
   select id,full_name as name,'member' as kind from public.people where organization_id=p_org and unit_id=uid and status='active' and private.target_unit_module_enabled(p_org,uid,'people') and strpos(lower(full_name),lower(n))>0
   union all select id,name,'supplier' from private.finance_catalog where organization_id=p_org and (unit_id=uid or unit_id is null) and kind='supplier' and active and strpos(lower(name),lower(n))>0 order by name,id limit 25
  )x),'[]'));
 end if;
 if p_action='snapshot' then
  v_from:=(p_data->>'from')::date;v_to:=(p_data->>'to')::date;page:=coalesce((p_data->>'page')::integer,1);
  if v_from is null or v_to is null or v_to<v_from or v_to-v_from>366 or page not between 1 and 10000 then raise exception 'invalid_period' using errcode='22023';end if;
  if (select count(*) from private.finance_catalog where organization_id=p_org and (unit_id=any(p_units) or unit_id is null))>3000 then raise exception 'catalog_limit' using errcode='22023';end if;
  select coalesce(jsonb_agg(to_jsonb(c) order by c.kind,c.name),'[]') into catalogs from private.finance_catalog c where organization_id=p_org and (unit_id=any(p_units) or unit_id is null);
  -- A single SQL statement snapshot for all rows, summaries and charts. Cash uses payment dates; forecasts use due dates.
  with filtered as (
   select e.*,c.name || case when c.unit_id is not null then ' · '||un.name else '' end category_name,s.name || case when s.unit_id is not null then ' · '||un.name else '' end center_name,a.name account_name,d.name destination_name,un.name unit_name from private.finance_entries e
   join public.organization_units un on un.id=e.unit_id
   join private.finance_catalog a on a.id=e.account_id
   left join private.finance_catalog c on c.id=e.category_id left join private.finance_catalog s on s.id=e.center_id left join private.finance_catalog d on d.id=e.destination_id
   where e.organization_id=p_org and e.unit_id=any(p_units)
   and (e.due_date between v_from and v_to or e.paid_date between v_from and v_to or e.reversed_date between v_from and v_to or e.competence_date between v_from and v_to)
   and (nullif(p_data->>'category','') is null or e.category_id=(p_data->>'category')::uuid)
   and (nullif(p_data->>'center','') is null or e.center_id=(p_data->>'center')::uuid)
   and (nullif(p_data->>'account','') is null or e.account_id=(p_data->>'account')::uuid or e.destination_id=(p_data->>'account')::uuid)
   and (nullif(p_data->>'kind','') is null or e.kind=p_data->>'kind')
   and (nullif(p_data->>'status','') is null or (case when e.reversal_id is not null then 'reversed' else e.status end)=p_data->>'status')
   and (nullif(p_data->>'search','') is null or strpos(lower(e.description||' '||e.party_name),lower(p_data->>'search'))>0)
  ), visible as (
   select * from filtered where (case when p_data->>'dateBy'='competence' then competence_date when p_data->>'dateBy'='paid' then paid_date else due_date end) between v_from and v_to
  ), flow as (
   select kind,paid_date as day,amount_cents::numeric as cents,category_id,center_id,category_name,center_name from filtered where status='posted' and kind in('income','expense')
   union all select kind,reversed_date,-amount_cents::numeric,category_id,center_id,category_name,center_name from filtered where reversal_id is not null and kind in('income','expense')
  ), monthly_flow as (
   select to_char(day,'YYYY-MM') as month,case when kind='income' then cents else 0 end income,case when kind='expense' then cents else 0 end expense,0::numeric receivable,0::numeric payable from flow where day between v_from and v_to
   union all select to_char(due_date,'YYYY-MM'),0,0,case when kind='income' then amount_cents else 0 end,case when kind='expense' then amount_cents else 0 end from filtered where status='pending' and kind in('income','expense') and due_date between v_from and v_to
  ) select
   (select count(*) from visible),
   coalesce((select jsonb_agg(to_jsonb(x) - 'fingerprint' - 'void_fingerprint' - 'void_request' - 'created_by' - 'amount_cents' || jsonb_build_object('amountCents',x.amount_cents::text) order by x.due_date desc,x.id desc) from (select * from visible order by due_date desc,id desc limit 30 offset (page-1)*30)x),'[]'),
   jsonb_build_object('income',coalesce((select sum(cents) from flow where kind='income' and day between v_from and v_to),0)::text,'expense',coalesce((select sum(cents) from flow where kind='expense' and day between v_from and v_to),0)::text,
    'receivable',coalesce((select sum(amount_cents) from filtered where status='pending' and kind='income' and due_date between v_from and v_to),0)::text,
    'payable',coalesce((select sum(amount_cents) from filtered where status='pending' and kind='expense' and due_date between v_from and v_to),0)::text,
    'overdue',coalesce((select sum(amount_cents) from filtered where status='pending' and due_date<current_date and due_date between v_from and v_to),0)::text),
   coalesce((select jsonb_agg(x order by x.month) from (select month,sum(income)::text income,sum(expense)::text expense,sum(receivable)::text receivable,sum(payable)::text payable from monthly_flow group by month)x),'[]'),
   coalesce((select jsonb_agg(x order by x.name,x.kind) from(select category_id as id,coalesce(category_name,'Sem categoria') name,kind,sum(cents)::text amount from flow where day between v_from and v_to group by category_id,category_name,kind)x),'[]'),
   coalesce((select jsonb_agg(x order by x.name,x.kind) from(select center_id as id,coalesce(center_name,'Sem centro de custo') name,kind,sum(cents)::text amount from flow where day between v_from and v_to group by center_id,center_name,kind)x),'[]')
   into total_count,records,totals,chart,category_stats,center_stats;
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'unitId',c.unit_id,'active',c.active,'balanceCents',coalesce(b.balance,0)::text) order by c.name),'[]') into accounts
  from private.finance_catalog c join private.finance_account_links m on m.catalog_id=c.id and m.unit_id=c.unit_id
  left join lateral(select sum(l.delta_cents) balance from public.church_ledger_lines l join public.church_ledger_journals j on j.id=l.journal_id where l.account_id=m.ledger_id and j.effective_date<=least(v_to,current_date))b on true
  where c.organization_id=p_org and c.unit_id=any(p_units) and c.kind='account' and (nullif(p_data->>'account','') is null or c.id=(p_data->>'account')::uuid);
  return jsonb_build_object('catalog',catalogs,'entries',records,'summary',totals,'monthly',chart,'categories',category_stats,'centers',center_stats,'accounts',accounts,'total',total_count,'page',page,'units',p_units,'from',v_from,'to',v_to,'currency','BRL');
 end if;
 if cardinality(p_units)<>1 then raise exception 'select_one_unit' using errcode='22023';end if;
 -- Serialize catalog changes and posting; recheck authority after waiting.
 perform 1 from public.organizations where id=p_org for update;
 perform 1 from public.organization_units where id=uid and organization_id=p_org for update;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,uid) then raise exception 'finance_access_denied' using errcode='42501';end if;
 v_id:=(p_data->>'id')::uuid;
 if v_id is null then raise exception 'missing_id' using errcode='22023';end if;
 if p_action='catalog' then
  if jsonb_typeof(coalesce(p_data->'details','{}'))<>'object' then raise exception 'invalid_catalog_details' using errcode='22023';end if;
  if exists(select 1 from jsonb_each(coalesce(p_data->'details','{}')) as d(key,value) where d.key not in('document','email','phone','bank','number','description') or jsonb_typeof(d.value)<>'string' or length(d.value#>>'{}')>200) then raise exception 'invalid_catalog_details' using errcode='22023';end if;
  k:=p_data->>'kind';n:=btrim(p_data->>'name');v_direction:=nullif(p_data->>'direction','');parent:=nullif(p_data->>'parent','')::uuid;shared:=coalesce((p_data->>'shared')::boolean,false);
  if k is null or k not in('account','category','center','supplier') or n is null or length(n) not between 2 and 120 or (k='category') is distinct from (v_direction is not null) or (v_direction is not null and v_direction not in('income','expense')) or (shared and k='account') then raise exception 'invalid_catalog' using errcode='22023';end if;
  if shared and not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) then raise exception 'shared_catalog_denied' using errcode='42501';end if;
  if parent is not null and (k<>'category' or not exists(select 1 from private.finance_catalog c where c.id=parent and c.organization_id=p_org and c.kind='category' and c.parent_id is null and c.active and c.direction=v_direction and (c.unit_id is null or (not shared and c.unit_id=uid)))) then raise exception 'invalid_parent' using errcode='22023';end if;
  select * into old from private.finance_catalog where id=v_id;
  if found then
   if old.organization_id<>p_org or old.unit_id is distinct from (case when shared then null else uid end) or old.kind<>k or old.direction is distinct from v_direction or old.parent_id is distinct from parent then raise exception 'catalog_identity_immutable' using errcode='42501';end if;
   if coalesce((p_data->>'version')::integer,0)=0 and old.name=n and old.details=coalesce(p_data->'details','{}') and old.active then return jsonb_build_object('id',v_id,'ok',true);end if;
   if old.version is distinct from (p_data->>'version')::integer then raise exception 'catalog_conflict' using errcode='40001';end if;
   if k='category' and not coalesce((p_data->>'active')::boolean,true) and exists(select 1 from private.finance_catalog where parent_id=v_id and active) then raise exception 'archive_children_first' using errcode='22023';end if;
   update private.finance_catalog set name=n,active=coalesce((p_data->>'active')::boolean,true),version=version+1,details=coalesce(p_data->'details','{}') where id=v_id;
  else
   if coalesce((p_data->>'version')::integer,0)<>0 then raise exception 'catalog_not_found' using errcode='40001';end if;
   insert into private.finance_catalog(id,organization_id,unit_id,kind,name,direction,parent_id,details) values(v_id,p_org,case when shared then null else uid end,k,n,v_direction,parent,coalesce(p_data->'details','{}'));
   if k='account' then
    link:=public.create_church_ledger_account(p_org,uid,'F1 · '||left(n,45)||' · '||left(v_id::text,8),'asset');
    insert into private.finance_account_links values(v_id,p_org,uid,link);
   end if;
  end if;
 elsif p_action='entry' then
  v_fingerprint:=encode(extensions.digest(p_data::text,'sha256'),'hex');
  select * into ent from private.finance_entries where id=v_id;
  if found then
   if ent.organization_id<>p_org or ent.unit_id<>uid or ent.fingerprint<>v_fingerprint then raise exception 'request_conflict' using errcode='22023';end if;
   return jsonb_build_object('id',v_id,'ok',true);
  end if;
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
  if effective is not null then
   select ledger_id into link from private.finance_account_links where catalog_id=account and unit_id=uid;
   if k='transfer' then select ledger_id into other_link from private.finance_account_links where catalog_id=destination and unit_id=uid;
   elsif k='opening' then
    if exists(select 1 from private.finance_entries where account_id=account and kind='opening' and reversal_id is null and status='posted') then raise exception 'opening_already_exists' using errcode='23505';end if;
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
  insert into private.finance_entries(id,organization_id,unit_id,kind,amount_cents,description,account_id,destination_id,category_id,center_id,supplier_id,person_id,party_name,method,notes,competence_date,due_date,paid_date,status,journal_id,fingerprint,created_by)
  values(v_id,p_org,uid,k,amount,memo,account,destination,category,center,supplier,person,party,method,notes,competence,due,effective,v_status,case when effective is not null then v_id end,v_fingerprint,auth.uid());
 elsif p_action='void' then
  select * into ent from private.finance_entries where id=v_id and organization_id=p_org and unit_id=uid for update;
  if not found then raise exception 'entry_not_found' using errcode='42501';end if;
  v_fingerprint:=encode(extensions.digest(p_data::text,'sha256'),'hex');
  if ent.void_request=(p_data->>'requestId')::uuid and ent.void_fingerprint=v_fingerprint then return jsonb_build_object('id',v_id,'ok',true);end if;
  if ent.version is distinct from (p_data->>'version')::integer or ent.status='cancelled' or ent.reversal_id is not null then raise exception 'entry_conflict' using errcode='40001';end if;
  memo:=btrim(p_data->>'reason');effective:=(p_data->>'date')::date;
  if memo is null or length(memo) not between 2 and 300 or effective is null or effective>current_date or effective<ent.paid_date then raise exception 'invalid_reversal' using errcode='22023';end if;
  if ent.status='posted' then
   link:=(p_data->>'requestId')::uuid;
   if link is null then raise exception 'missing_request' using errcode='22023';end if;
   perform private.post_church_journal(p_org,uid,link,effective,memo,'[]',ent.journal_id);
   update private.finance_entries set reversal_id=link,reversed_date=effective,void_request=(p_data->>'requestId')::uuid,void_fingerprint=v_fingerprint,version=version+1 where id=v_id;
  else update private.finance_entries set status='cancelled',void_request=(p_data->>'requestId')::uuid,void_fingerprint=v_fingerprint,version=version+1 where id=v_id;end if;
 else raise exception 'invalid_action' using errcode='22023';end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'finance.'||p_action,'finance_f1',v_id::text,jsonb_build_object('unit_id',uid,'reason',case when p_action='void' then memo end));
 return jsonb_build_object('id',v_id,'ok',true);
end $$;
revoke all on function private.finance_f1(uuid,uuid[],text,jsonb) from public,anon,authenticated,service_role;
create function public.finance_f1(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_f1(p_org,p_units,p_action,p_data)$$;
grant execute on function private.finance_f1(uuid,uuid[],text,jsonb) to authenticated;
revoke all on function public.finance_f1(uuid,uuid[],text,jsonb) from public,anon,service_role;
grant execute on function public.finance_f1(uuid,uuid[],text,jsonb) to authenticated;

-- Keep the old isolated ledger API compatible, but it cannot bypass F1 metadata.
alter function public.post_church_journal(uuid,uuid,uuid,date,text,jsonb,uuid) set schema private;
revoke all on function private.post_church_journal(uuid,uuid,uuid,date,text,jsonb,uuid) from public,anon,authenticated,service_role;
create function private.legacy_finance_post(p_org uuid,p_unit uuid,p_request uuid,p_date date,p_memo text,p_lines jsonb,p_reversal uuid) returns uuid
language plpgsql security definer set search_path='' as $$
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org for update;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'ledger_access_denied' using errcode='42501';end if;
 if exists(select 1 from private.finance_account_links l where l.organization_id=p_org and l.unit_id=p_unit and exists(select 1 from jsonb_array_elements(p_lines)x where (x->>'accountId')::uuid=l.ledger_id))
 or exists(select 1 from private.finance_entries where organization_id=p_org and unit_id=p_unit and (id=p_request or journal_id=p_reversal or reversal_id=p_reversal)) then raise exception 'use_finance_operational_command' using errcode='42501';end if;
 return private.post_church_journal(p_org,p_unit,p_request,p_date,p_memo,p_lines,p_reversal);
end $$;
revoke all on function private.legacy_finance_post(uuid,uuid,uuid,date,text,jsonb,uuid) from public,anon,service_role;
grant execute on function private.legacy_finance_post(uuid,uuid,uuid,date,text,jsonb,uuid) to authenticated;
create function public.post_church_journal(p_org uuid,p_unit uuid,p_request uuid,p_date date,p_memo text,p_lines jsonb,p_reversal uuid default null) returns uuid
language sql security invoker set search_path='' as $$select private.legacy_finance_post(p_org,p_unit,p_request,p_date,p_memo,p_lines,p_reversal)$$;
revoke all on function public.post_church_journal(uuid,uuid,uuid,date,text,jsonb,uuid) from public,anon,service_role;
grant execute on function public.post_church_journal(uuid,uuid,uuid,date,text,jsonb,uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('finance-documents-private','finance-documents-private',false,4194304,array['application/pdf','image/png','image/jpeg']) on conflict(id) do nothing;
create function private.finance_file_allowed(p_path text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare parts text[]:=string_to_array(p_path,'/');org uuid;unit uuid;entry uuid;
begin
 if cardinality(parts)<>4 or parts[1]!~'^[a-f0-9-]{36}$' or parts[2]!~'^[a-f0-9-]{36}$' or parts[3]!~'^[a-f0-9-]{36}$' or parts[4]!~'^[a-f0-9-]{36}\.(pdf|png|jpg)$' then return false;end if;
 org:=parts[1]::uuid;unit:=parts[2]::uuid;entry:=parts[3]::uuid;
 return exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and not coalesce(is_anonymous,false) and deleted_at is null and (banned_until is null or banned_until<=now())) and private.church_ledger_allowed(org,unit)
 and exists(select 1 from private.finance_entries where id=entry and organization_id=org and unit_id=unit);
exception when invalid_text_representation then return false;
end $$;
revoke all on function private.finance_file_allowed(text) from public,anon,service_role;
grant execute on function private.finance_file_allowed(text) to authenticated;
create policy finance_documents_read on storage.objects for select to authenticated using(bucket_id='finance-documents-private' and private.finance_file_allowed(name));
create policy finance_documents_insert on storage.objects for insert to authenticated with check(bucket_id='finance-documents-private' and private.finance_file_allowed(name));
