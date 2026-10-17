-- Experimental ledger. No provider transfers, fiscal issuance, or customer UI release.
set local lock_timeout='5s';
set local statement_timeout='30s';
create table public.church_ledger_accounts(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 unit_id uuid not null,
 name text not null check(char_length(trim(name)) between 2 and 100),
 kind text not null check(kind in('asset','income','expense')),
 created_at timestamptz not null default clock_timestamp(),
 unique(id,organization_id,unit_id),unique(organization_id,unit_id,name),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create table public.church_ledger_periods(
 organization_id uuid not null,
 unit_id uuid not null,
 closed_through date not null default '-infinity',
 generation bigint not null default 0,
 primary key(organization_id,unit_id),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create table public.church_ledger_journals(
 id uuid primary key,
 organization_id uuid not null references public.organizations(id),
 unit_id uuid not null,
 effective_date date not null,
 memo text not null check(char_length(trim(memo)) between 2 and 300),
 fingerprint text not null,
 reversal_of uuid unique,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),
 unique(id,organization_id,unit_id),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id),
 foreign key(reversal_of,organization_id,unit_id) references public.church_ledger_journals(id,organization_id,unit_id)
);
create table public.church_ledger_lines(
 journal_id uuid not null,
 organization_id uuid not null,
 unit_id uuid not null,
 account_id uuid not null,
 delta_cents bigint not null check(delta_cents<>0 and delta_cents between -9007199254740991 and 9007199254740991),
 primary key(journal_id,account_id),
 foreign key(journal_id,organization_id,unit_id) references public.church_ledger_journals(id,organization_id,unit_id),
 foreign key(account_id,organization_id,unit_id) references public.church_ledger_accounts(id,organization_id,unit_id)
);
create index church_ledger_journals_page on public.church_ledger_journals(organization_id,unit_id,effective_date,id);
create index church_ledger_lines_account on public.church_ledger_lines(account_id,journal_id);

create function private.church_ledger_allowed(p_org uuid,p_unit uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null
 and private.has_organization_role(p_org,array['owner','admin','finance']::public.membership_role[])
 and private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[])
 and private.target_unit_module_enabled(p_org,p_unit,'finance')
 and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial'));
$$;
revoke all on function private.church_ledger_allowed(uuid,uuid) from public,anon;
grant execute on function private.church_ledger_allowed(uuid,uuid) to authenticated;
alter table public.church_ledger_accounts enable row level security;
alter table public.church_ledger_periods enable row level security;
alter table public.church_ledger_journals enable row level security;
alter table public.church_ledger_lines enable row level security;
revoke all on public.church_ledger_accounts,public.church_ledger_periods,public.church_ledger_journals,public.church_ledger_lines from public,anon,authenticated,service_role;
grant select on public.church_ledger_accounts,public.church_ledger_periods,public.church_ledger_journals,public.church_ledger_lines to authenticated;
create policy church_ledger_accounts_read on public.church_ledger_accounts for select to authenticated using(private.church_ledger_allowed(organization_id,unit_id));
create policy church_ledger_periods_read on public.church_ledger_periods for select to authenticated using(private.church_ledger_allowed(organization_id,unit_id));
create policy church_ledger_journals_read on public.church_ledger_journals for select to authenticated using(private.church_ledger_allowed(organization_id,unit_id));
create policy church_ledger_lines_read on public.church_ledger_lines for select to authenticated using(private.church_ledger_allowed(organization_id,unit_id));

create function public.create_church_ledger_account(p_org uuid,p_unit uuid,p_name text,p_kind text) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 if not found or not private.church_ledger_allowed(p_org,p_unit) then raise exception 'ledger_access_denied' using errcode='42501';end if;
 insert into public.church_ledger_periods(organization_id,unit_id) values(p_org,p_unit) on conflict do nothing;
 update public.church_ledger_periods set generation=generation+1 where organization_id=p_org and unit_id=p_unit;
 insert into public.church_ledger_accounts(organization_id,unit_id,name,kind) values(p_org,p_unit,trim(p_name),p_kind) returning id into result;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'ledger.account_created','church_ledger_account',result::text,jsonb_build_object('unit_id',p_unit));
 return result;
end $$;

create function public.post_church_journal(p_org uuid,p_unit uuid,p_request uuid,p_date date,p_memo text,p_lines jsonb,p_reversal uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare lines jsonb:=p_lines;item jsonb;total numeric:=0;v_delta bigint;v_account uuid;fingerprint text;previous public.church_ledger_journals;
begin
 perform private.require_confirmed_self_service_email();
 -- Same lock for postings and closing: no post can cross a concurrent close.
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 if not found or not private.church_ledger_allowed(p_org,p_unit) then raise exception 'ledger_access_denied' using errcode='42501';end if;
 insert into public.church_ledger_periods(organization_id,unit_id) values(p_org,p_unit) on conflict do nothing;
 -- A row version change also rejects stale REPEATABLE READ/SERIALIZABLE snapshots.
 update public.church_ledger_periods set generation=generation+1 where organization_id=p_org and unit_id=p_unit;
 if p_request is null or p_date is null or p_date>current_date or p_memo is null or char_length(trim(p_memo)) not between 2 and 300 then raise exception 'invalid_ledger_input' using errcode='22023';end if;
 if p_reversal is not null then
  if p_lines is distinct from '[]'::jsonb or not exists(select 1 from public.church_ledger_journals where id=p_reversal and organization_id=p_org and unit_id=p_unit and reversal_of is null) then raise exception 'invalid_ledger_reversal' using errcode='22023';end if;
  select jsonb_agg(jsonb_build_object('accountId',account_id,'deltaCents',-delta_cents) order by account_id) into lines from public.church_ledger_lines where journal_id=p_reversal and organization_id=p_org and unit_id=p_unit;
 end if;
 if lines is null or jsonb_typeof(lines)<>'array' or jsonb_array_length(lines) not between 2 and 100 then raise exception 'invalid_ledger_lines' using errcode='22023';end if;
 fingerprint:=encode(extensions.digest(jsonb_build_object('org',p_org,'unit',p_unit,'date',p_date,'memo',trim(p_memo),'lines',lines,'reversal',p_reversal)::text,'sha256'),'hex');
 select * into previous from public.church_ledger_journals where id=p_request;
 if found then
  if previous.organization_id<>p_org or previous.unit_id<>p_unit or previous.fingerprint<>fingerprint then raise exception 'ledger_idempotency_conflict' using errcode='22023';end if;
  return previous.id;
 end if;
 if exists(select 1 from public.church_ledger_periods where organization_id=p_org and unit_id=p_unit and closed_through>=p_date) then raise exception 'ledger_period_closed' using errcode='22023';end if;
 for item in select value from jsonb_array_elements(lines) loop
  if jsonb_typeof(item)<>'object' or jsonb_typeof(item->'deltaCents')<>'number' or (item->>'deltaCents') !~ '^-?[0-9]+$' or jsonb_typeof(item->'accountId')<>'string' then raise exception 'invalid_ledger_line' using errcode='22023';end if;
  v_delta:=(item->>'deltaCents')::bigint;v_account:=(item->>'accountId')::uuid;
  if v_delta=0 or v_delta not between -9007199254740991 and 9007199254740991 or not exists(select 1 from public.church_ledger_accounts where id=v_account and organization_id=p_org and unit_id=p_unit) then raise exception 'invalid_ledger_line' using errcode='22023';end if;
  total:=total+v_delta;
 end loop;
 if total<>0 then raise exception 'ledger_not_balanced' using errcode='22023';end if;
 insert into public.church_ledger_journals(id,organization_id,unit_id,effective_date,memo,fingerprint,reversal_of,created_by) values(p_request,p_org,p_unit,p_date,trim(p_memo),fingerprint,p_reversal,auth.uid());
 insert into public.church_ledger_lines(journal_id,organization_id,unit_id,account_id,delta_cents) select p_request,p_org,p_unit,(value->>'accountId')::uuid,(value->>'deltaCents')::bigint from jsonb_array_elements(lines);
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),case when p_reversal is null then 'ledger.posted' else 'ledger.reversed' end,'church_ledger_journal',p_request::text,jsonb_build_object('unit_id',p_unit,'reversal_of',p_reversal));
 return p_request;
end $$;

create function public.close_church_ledger_period(p_org uuid,p_unit uuid,p_through date) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 if not found or not private.church_ledger_allowed(p_org,p_unit) then raise exception 'ledger_access_denied' using errcode='42501';end if;
 insert into public.church_ledger_periods(organization_id,unit_id) values(p_org,p_unit) on conflict do nothing;
 update public.church_ledger_periods set generation=generation+1 where organization_id=p_org and unit_id=p_unit;
 if p_through is null or p_through>=current_date then raise exception 'invalid_ledger_close' using errcode='22023';end if;
 if exists(select 1 from public.church_ledger_periods where organization_id=p_org and unit_id=p_unit and closed_through>=p_through) then raise exception 'ledger_already_closed' using errcode='22023';end if;
 update public.church_ledger_periods set closed_through=p_through where organization_id=p_org and unit_id=p_unit;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'ledger.period_closed','organization_unit',p_unit::text,jsonb_build_object('closed_through',p_through));
end $$;
revoke all on function public.create_church_ledger_account(uuid,uuid,text,text),public.post_church_journal(uuid,uuid,uuid,date,text,jsonb,uuid),public.close_church_ledger_period(uuid,uuid,date) from public,anon,service_role;
grant execute on function public.create_church_ledger_account(uuid,uuid,text,text),public.post_church_journal(uuid,uuid,uuid,date,text,jsonb,uuid),public.close_church_ledger_period(uuid,uuid,date) to authenticated;

-- Text cents preserve exact totals even if a sum exceeds the JS safe integer range.
create function public.church_ledger_balances(p_org uuid,p_unit uuid,p_through date) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
begin
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'ledger_access_denied' using errcode='42501';end if;
 if p_through is null or p_through>current_date then raise exception 'invalid_ledger_date' using errcode='22023';end if;
 if (select count(*) from public.church_ledger_accounts where organization_id=p_org and unit_id=p_unit)>500 then raise exception 'ledger_report_requires_pagination' using errcode='22023';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('accountId',a.id,'name',a.name,'kind',a.kind,'balanceCents',coalesce(b.total,0)::text) order by a.name,a.id)
 from public.church_ledger_accounts a left join (
 select l.account_id,sum(l.delta_cents) total from public.church_ledger_lines l join public.church_ledger_journals j on j.id=l.journal_id and j.organization_id=l.organization_id and j.unit_id=l.unit_id
 where j.organization_id=p_org and j.unit_id=p_unit and j.effective_date<=p_through group by l.account_id) b on b.account_id=a.id
 where a.organization_id=p_org and a.unit_id=p_unit),'[]'::jsonb);
end $$;
revoke all on function public.church_ledger_balances(uuid,uuid,date) from public,anon,service_role;
grant execute on function public.church_ledger_balances(uuid,uuid,date) to authenticated;
