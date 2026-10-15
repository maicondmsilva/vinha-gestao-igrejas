create table public.saas_trial_registrations(
 organization_id uuid primary key references public.organizations(id),
 user_id uuid not null unique references auth.users(id), full_name text not null, email text not null, phone text not null,
 city text not null, state text not null, units_estimate integer not null check(units_estimate between 1 and 10000),
 terms_version text not null, accepted_at timestamptz not null default now(), source text not null default 'website',
 created_at timestamptz not null default now()
);
alter table public.saas_trial_registrations enable row level security;
grant select,insert on public.saas_trial_registrations to authenticated;
create policy trial_read on public.saas_trial_registrations for select to authenticated using(
 user_id=(select auth.uid()) or ((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]))));
create policy trial_insert on public.saas_trial_registrations for insert to authenticated with check(
 user_id=(select auth.uid()) and private.has_organization_role(organization_id,array['owner']::public.membership_role[]));
create index trial_registrations_created_idx on public.saas_trial_registrations(created_at);

create function public.register_organization_trial(p_data jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare oid uuid; slug text; email text:=auth.jwt()->>'email'; existing public.saas_trial_registrations; begin
 if auth.uid() is null or email is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'authentication_required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtext('trial:'||auth.uid()::text));
 select * into existing from public.saas_trial_registrations where user_id=auth.uid();
 if existing.organization_id is not null then
  select o.slug into slug from public.organizations o where o.id=existing.organization_id;
  return jsonb_build_object('ok',true,'slug',slug,'alreadyCreated',true);
 end if;
 if coalesce(p_data->>'accepted','')<>'true' or char_length(trim(coalesce(p_data->>'fullName','')))<3 or
  char_length(trim(coalesce(p_data->>'pastor','')))<3 or length(regexp_replace(coalesce(p_data->>'phone',''),'[^0-9]','','g')) not between 10 and 15 or
  char_length(trim(coalesce(p_data->>'city','')))<2 or coalesce(p_data->>'state','') !~ '^[A-Z]{2}$' or
  coalesce(p_data->>'units','') !~ '^[0-9]{1,4}$' or (p_data->>'units')::integer<1 then raise exception 'invalid_trial_data' using errcode='22023'; end if;
 slug:=trim(both '-' from regexp_replace(translate(lower(trim(p_data->>'ministry')),'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc'),'[^a-z0-9]+','-','g'));
 slug:=left(slug,85)||'-'||substr(replace(auth.uid()::text,'-',''),1,8);
 oid:=public.bootstrap_organization(p_data->>'ministry',slug,p_data->>'headquarters',p_data->>'fullName');
 perform public.save_organization_onboarding(oid,jsonb_build_object('step','identity','name',p_data->>'ministry','appName',p_data->>'ministry','seniorPastorName',p_data->>'pastor','primaryColor','#285c45','accentColor','#d9b960'));
 perform public.save_organization_onboarding(oid,jsonb_build_object('step','headquarters','name',p_data->>'headquarters','pastorName',p_data->>'pastor','email',email,'phone',p_data->>'phone','city',p_data->>'city','state',p_data->>'state'));
 perform public.save_organization_onboarding(oid,'{"step":"structure"}');
 perform public.save_organization_onboarding(oid,'{"step":"people"}');
 perform public.save_organization_onboarding(oid,'{"step":"completed"}');
 insert into public.saas_trial_registrations(organization_id,user_id,full_name,email,phone,city,state,units_estimate,terms_version)
 values(oid,auth.uid(),trim(p_data->>'fullName'),email,p_data->>'phone',trim(p_data->>'city'),p_data->>'state',(p_data->>'units')::integer,'teste-2026-10-14');
 return jsonb_build_object('ok',true,'slug',slug,'alreadyCreated',false);
end $$;
revoke all on function public.register_organization_trial(jsonb) from public,anon;
grant execute on function public.register_organization_trial(jsonb) to authenticated;

create table public.saas_chat_conversations(
 id uuid primary key default extensions.gen_random_uuid(), organization_id uuid references public.organizations(id),
 owner_user_id uuid references auth.users(id), guest_secret_hash text, contact_name text not null, contact_email text not null,
 source text not null check(source in ('website','customer')), status text not null default 'open' check(status in ('open','closed')),
 assigned_operator_id uuid references public.platform_operators(user_id),
 visitor_last_read_at timestamptz not null default now(), operator_last_read_at timestamptz not null default now(),
 last_message_at timestamptz not null default now(), last_sender text not null default 'visitor',
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '30 days',
 check(owner_user_id is not null or length(guest_secret_hash)=64)
);
create table public.saas_chat_messages(
 id uuid primary key default extensions.gen_random_uuid(), conversation_id uuid not null references public.saas_chat_conversations(id) on delete cascade,
 sender text not null check(sender in ('visitor','team')), author_name text not null, body text not null check(char_length(trim(body)) between 1 and 2000),
 author_user_id uuid references auth.users(id), created_at timestamptz not null default now()
);
create index chat_conversations_queue_idx on public.saas_chat_conversations(status,last_message_at desc);
create index chat_conversations_owner_idx on public.saas_chat_conversations(owner_user_id);
create index chat_conversations_org_idx on public.saas_chat_conversations(organization_id);
create index chat_conversations_operator_idx on public.saas_chat_conversations(assigned_operator_id);
create index chat_messages_conversation_idx on public.saas_chat_messages(conversation_id,created_at);
create index chat_messages_author_idx on public.saas_chat_messages(author_user_id);
alter table public.saas_chat_conversations enable row level security;
alter table public.saas_chat_messages enable row level security;
grant select,insert,update on public.saas_chat_conversations,public.saas_chat_messages to authenticated;
create policy chat_conversations_operator_read on public.saas_chat_conversations for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[])));
create policy chat_conversations_operator_write on public.saas_chat_conversations for all to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin','support']::public.platform_operator_role[]))) with check((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin','support']::public.platform_operator_role[])));
create policy chat_messages_operator_read on public.saas_chat_messages for select to authenticated using((select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[])));
create policy chat_messages_operator_write on public.saas_chat_messages for insert to authenticated with check(sender='team' and author_user_id=(select auth.uid()) and (select private.has_aal2()) and (select private.is_platform_operator(array['owner','admin','support']::public.platform_operator_role[])));

-- Guests have no direct table access. A 256-bit capability grants access only
-- to one expiring conversation. Authenticated customers must own that conversation.
create function private.support_chat(p_action text,p_id uuid default null,p_secret text default null,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.saas_chat_conversations; cid uuid; oid uuid; display_name text; email text; body text; messages jsonb; stamp timestamptz:=now(); begin
 if p_action='start' then
  perform pg_advisory_xact_lock(hashtext('public-chat-admission'));
  if (select count(*) from public.saas_chat_conversations where created_at>stamp-interval '1 hour')>=100 then raise exception 'chat_rate_limit' using errcode='P0001'; end if;
  body:=trim(coalesce(p_data->>'body','')); display_name:=left(trim(coalesce(p_data->>'name','')),100); email:=left(lower(trim(coalesce(p_data->>'email',''))),254);
  if length(display_name)<2 or email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(body) not between 1 and 2000 then raise exception 'invalid_chat_data'; end if;
  if auth.uid() is null then
   if p_secret is null or p_secret !~ '^[0-9a-f]{64}$' then raise exception 'invalid_chat_secret'; end if;
  else
   email:=coalesce(auth.jwt()->>'email',email);
   if (select count(*) from public.saas_chat_conversations where owner_user_id=auth.uid() and status='open')>=3 then raise exception 'chat_rate_limit'; end if;
   if nullif(p_data->>'organizationId','') is not null then
    oid:=(p_data->>'organizationId')::uuid;
    if not exists(select 1 from public.organization_memberships where user_id=auth.uid() and organization_id=oid and status='active') then raise exception 'chat_access_denied' using errcode='42501'; end if;
   end if;
  end if;
  insert into public.saas_chat_conversations(organization_id,owner_user_id,guest_secret_hash,contact_name,contact_email,source)
  values(oid,auth.uid(),case when auth.uid() is null then encode(extensions.digest(p_secret,'sha256'),'hex') end,display_name,email,case when oid is null then 'website' else 'customer' end) returning id into cid;
  insert into public.saas_chat_messages(conversation_id,sender,author_name,body,author_user_id) values(cid,'visitor',display_name,body,auth.uid());
  return jsonb_build_object('id',cid);
 end if;
 if p_id is null then raise exception 'chat_access_denied' using errcode='42501'; end if;
 select * into c from public.saas_chat_conversations where id=p_id for update;
 if c.id is null then raise exception 'chat_access_denied' using errcode='42501'; end if;
 if c.owner_user_id is not null then
  if auth.uid() is distinct from c.owner_user_id then raise exception 'chat_access_denied' using errcode='42501'; end if;
 elsif c.expires_at<stamp or p_secret is null or p_secret !~ '^[0-9a-f]{64}$' or c.guest_secret_hash is distinct from encode(extensions.digest(p_secret,'sha256'),'hex') then
  raise exception 'chat_access_denied' using errcode='42501';
 end if;
 if p_action='send' then
  body:=trim(coalesce(p_data->>'body',''));
  if c.status='closed' then raise exception 'chat_closed'; end if;
  if length(body) not between 1 and 2000 then raise exception 'invalid_chat_data'; end if;
  if (select count(*) from public.saas_chat_messages where conversation_id=c.id and sender='visitor' and created_at>stamp-interval '1 minute')>=12 or
   (select count(*) from public.saas_chat_messages where conversation_id=c.id)>=500 then raise exception 'chat_rate_limit'; end if;
  insert into public.saas_chat_messages(conversation_id,sender,author_name,body,author_user_id) values(c.id,'visitor',c.contact_name,body,auth.uid());
  update public.saas_chat_conversations set last_message_at=stamp,last_sender='visitor',visitor_last_read_at=stamp where id=c.id;
 elsif p_action='read' then
  update public.saas_chat_conversations set visitor_last_read_at=stamp where id=c.id;
 else raise exception 'invalid_chat_action';
 end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at),'[]') into messages from (
  select id,sender,author_name,body,created_at from public.saas_chat_messages where conversation_id=c.id order by created_at desc limit 100
 ) q;
 return jsonb_build_object('conversation',jsonb_build_object('id',c.id,'status',c.status,'source',c.source),'messages',messages);
end $$;
revoke all on function private.support_chat(text,uuid,text,jsonb) from public;
revoke all on function private.support_chat(text,uuid,text,jsonb) from anon,authenticated;
create function public.support_chat(p_action text,p_id uuid default null,p_secret text default null,p_data jsonb default '{}')
returns jsonb language sql security definer set search_path='' as $$ select private.support_chat(p_action,p_id,p_secret,p_data) $$;
revoke all on function public.support_chat(text,uuid,text,jsonb) from public;
grant execute on function public.support_chat(text,uuid,text,jsonb) to anon,authenticated;
