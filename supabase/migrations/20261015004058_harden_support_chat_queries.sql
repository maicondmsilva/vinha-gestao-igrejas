create or replace function private.support_chat(p_action text,p_id uuid default null,p_secret text default null,p_data jsonb default '{}')
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
  select m.id,m.sender,m.author_name,m.body,m.created_at from public.saas_chat_messages m where m.conversation_id=c.id order by m.created_at desc limit 100
 ) q;
 return jsonb_build_object('conversation',jsonb_build_object('id',c.id,'status',c.status,'source',c.source),'messages',messages);
end $$;
