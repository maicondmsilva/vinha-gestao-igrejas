-- Aplicativo: "Minha família" (só nome e parentesco) e pedido de inclusão de familiar.
-- O pedido usa private.member_family_requests com o tipo novo 'relative' e é analisado em Pessoas › Perfis pendentes.
-- As funções de Kids e células filtram pelo próprio tipo; não enxergam estes pedidos.

alter table private.member_family_requests drop constraint if exists member_family_requests_kind_check;
alter table private.member_family_requests add constraint member_family_requests_kind_check
 check (kind = any (array['kids.create','kids.edit','cell.leave','relative']));

-- Lado do membro.
create or replace function private.member_relatives(p_org uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare person public.people; v_name text; v_id uuid; v_relation text;
begin
 perform private.require_confirmed_self_service_email();
 p_data:=coalesce(p_data,'{}'::jsonb);
 perform 1 from public.organizations where id=p_org and status in ('active','trial');
 if not found then raise exception 'member_app_denied' using errcode='42501'; end if;
 perform 1 from public.organization_memberships where organization_id=p_org and user_id=auth.uid() and status='active';
 if not found then raise exception 'member_app_denied' using errcode='42501'; end if;
 select * into person from public.people where organization_id=p_org and auth_user_id=auth.uid() and status not in ('rejected','deceased') order by created_at limit 1;
 if person.id is null then raise exception 'member_profile_required' using errcode='42501'; end if;

 if p_action='list' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('name',p.full_name,'relation',r.relation) order by p.full_name)
   from private.person_relationships r join public.people p on p.id=r.related_person_id
   where r.person_id=person.id and p.status not in ('rejected')),'[]'::jsonb));
 end if;
 if p_action='requests' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'name',q.data->>'name','relation',q.data->>'relation','status',q.status,'reason',q.reason,'createdAt',q.created_at) order by q.created_at desc)
   from (select * from private.member_family_requests where organization_id=p_org and user_id=auth.uid() and kind='relative' order by created_at desc limit 20) q),'[]'::jsonb));
 end if;
 if p_action<>'request' then raise exception 'invalid_action' using errcode='22023'; end if;

 v_name:=btrim(coalesce(p_data->>'name',''));
 v_relation:=p_data->>'relation';
 if char_length(v_name) not between 2 and 160 or private.relation_inverse(v_relation) is null
  or coalesce(p_data->>'birth_date','')<>'' and (p_data->>'birth_date' !~ '^\d{4}-\d{2}-\d{2}$' or (p_data->>'birth_date')::date>current_date)
  or char_length(coalesce(p_data->>'nonce','')) not between 1 and 80 then
  raise exception 'invalid_relative' using errcode='22023';
 end if;
 select id into v_id from private.member_family_requests where organization_id=p_org and user_id=auth.uid() and nonce=p_data->>'nonce';
 if v_id is not null then return jsonb_build_object('ok',true,'id',v_id); end if;
 if (select count(*) from private.member_family_requests where organization_id=p_org and user_id=auth.uid() and kind='relative' and status='pending')>=10 then
  raise exception 'member_daily_limit' using errcode='54000';
 end if;
 insert into private.member_family_requests(organization_id,unit_id,user_id,person_id,kind,data,nonce)
  values(p_org,person.unit_id,auth.uid(),person.id,'relative',
   jsonb_build_object('name',v_name,'birth_date',nullif(p_data->>'birth_date',''),'relation',v_relation,'same_household',coalesce((p_data->>'same_household')::boolean,false)),
   p_data->>'nonce') returning id into v_id;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_org,auth.uid(),'member.relative.requested','member_family_request',v_id::text,jsonb_build_object('relation',v_relation));
 return jsonb_build_object('ok',true,'id',v_id);
end $$;

-- Lado da gestão (mesma regra de quem analisa perfis pendentes).
create or replace function private.member_relatives_admin(p_org uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare req private.member_family_requests; requester public.people; target public.people; v_reason text; v_journey text;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 p_data:=coalesce(p_data,'{}'::jsonb);
 perform 1 from public.organizations where id=p_org and status in ('active','trial');
 if not found then raise exception 'member_review_denied' using errcode='42501'; end if;

 if p_action='list' then
  if not exists(select 1 from public.organization_units u where u.organization_id=p_org and (private.member_review_allowed(p_org,u.id,'view') or private.member_review_allowed(p_org,u.id,'approve'))) then
   raise exception 'member_review_denied' using errcode='42501';
  end if;
  return jsonb_build_object('items',coalesce((select jsonb_agg(x.item order by x.created_at) from (
   select r.created_at,jsonb_build_object('id',r.id,'version',r.version,'requester',p.full_name,'requesterId',p.id,'unit',u.name,
     'name',r.data->>'name','birth_date',r.data->>'birth_date','relation',r.data->>'relation','same_household',coalesce((r.data->>'same_household')::boolean,false),
     'createdAt',r.created_at,'canApprove',private.member_review_allowed(p_org,r.unit_id,'approve'),
     'candidates',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.full_name,'birth_date',c.birth_date,'journey',c.journey_status)) from (
       select c.* from public.people c where c.organization_id=p_org and c.status not in ('rejected','deceased') and c.id<>p.id
        and lower(btrim(c.full_name))=lower(btrim(r.data->>'name'))
        and (nullif(r.data->>'birth_date','') is null or c.birth_date=(r.data->>'birth_date')::date)
       order by c.created_at limit 5) c),'[]'::jsonb)) item
   from private.member_family_requests r join public.people p on p.id=r.person_id join public.organization_units u on u.id=r.unit_id
   where r.organization_id=p_org and r.kind='relative' and r.status='pending'
    and (private.member_review_allowed(p_org,r.unit_id,'view') or private.member_review_allowed(p_org,r.unit_id,'approve'))
   order by r.created_at limit 200) x),'[]'::jsonb));
 end if;
 if p_action<>'review' then raise exception 'invalid_action' using errcode='22023'; end if;

 select * into req from private.member_family_requests where id=nullif(p_data->>'id','')::uuid and organization_id=p_org and kind='relative' for update;
 if req.id is null or req.status<>'pending' then raise exception 'member_request_changed' using errcode='40001'; end if;
 if not private.member_review_allowed(p_org,req.unit_id,'approve') then raise exception 'member_review_denied' using errcode='42501'; end if;
 select * into requester from public.people where id=req.person_id and organization_id=p_org and status not in ('rejected','deceased') for update;
 if requester.id is null then raise exception 'member_request_changed' using errcode='40001'; end if;

 if p_data->>'decision'='reject' then
  v_reason:=btrim(coalesce(p_data->>'reason',''));
  if char_length(v_reason) not between 5 and 500 then raise exception 'invalid_member_review' using errcode='22023'; end if;
  update private.member_family_requests set status='rejected',reason=v_reason,reviewed_by=auth.uid(),version=version+1,updated_at=clock_timestamp() where id=req.id;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,auth.uid(),'member.relative.rejected','member_family_request',req.id::text,'{}'::jsonb);
  return jsonb_build_object('ok',true);
 end if;
 if p_data->>'decision' is distinct from 'approve' then raise exception 'invalid_member_review' using errcode='22023'; end if;

 if nullif(p_data->>'person','') is not null then
  select * into target from public.people where id=(p_data->>'person')::uuid and organization_id=p_org and status not in ('rejected','deceased') for update;
  if target.id is null or target.id=requester.id then raise exception 'member_identity_conflict' using errcode='40001'; end if;
 else
  v_journey:=coalesce(nullif(p_data->>'journey',''),'Visitante');
  if v_journey not in ('Membro','Em integração','Visitante') then raise exception 'invalid_member_review' using errcode='22023'; end if;
  insert into public.people(organization_id,unit_id,full_name,birth_date,journey_status,status)
   values(p_org,requester.unit_id,req.data->>'name',nullif(req.data->>'birth_date','')::date,v_journey,'active') returning * into target;
 end if;
 if exists(select 1 from private.person_relationships where person_id=requester.id and related_person_id=target.id) then
  raise exception 'family_link_exists' using errcode='23505';
 end if;
 insert into private.person_relationships(organization_id,person_id,related_person_id,relation,same_household,created_by) values
  (p_org,requester.id,target.id,req.data->>'relation',coalesce((req.data->>'same_household')::boolean,false),auth.uid()),
  (p_org,target.id,requester.id,private.relation_inverse(req.data->>'relation'),coalesce((req.data->>'same_household')::boolean,false),auth.uid());
 update private.member_family_requests set status='approved',reviewed_by=auth.uid(),version=version+1,updated_at=clock_timestamp(),
  data=data||jsonb_build_object('linkedPerson',target.id) where id=req.id;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_org,auth.uid(),'people.family.saved','person',requester.id::text,jsonb_build_object('related',target.id,'relation',req.data->>'relation','fromApp',true));
 return jsonb_build_object('ok',true,'person',target.id);
end $$;

create or replace function public.member_relatives(p_org uuid, p_action text, p_data jsonb) returns jsonb
language sql security invoker set search_path to '' as $$ select private.member_relatives(p_org,p_action,p_data) $$;
create or replace function public.member_relatives_admin(p_org uuid, p_action text, p_data jsonb) returns jsonb
language sql security invoker set search_path to '' as $$ select private.member_relatives_admin(p_org,p_action,p_data) $$;
revoke all on function private.member_relatives(uuid,text,jsonb) from public,anon,service_role;
revoke all on function private.member_relatives_admin(uuid,text,jsonb) from public,anon,service_role;
revoke all on function public.member_relatives(uuid,text,jsonb) from public,anon,service_role;
revoke all on function public.member_relatives_admin(uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.member_relatives(uuid,text,jsonb) to authenticated;
grant execute on function private.member_relatives_admin(uuid,text,jsonb) to authenticated;
grant execute on function public.member_relatives(uuid,text,jsonb) to authenticated;
grant execute on function public.member_relatives_admin(uuid,text,jsonb) to authenticated;

-- Caixa de avisos: pedido de familiar recusado aparece para quem pediu.
do $mig$
declare def text;
begin
 if to_regprocedure('private.member_inbox_before_relative_review(uuid,uuid)') is null then
  def:=pg_get_functiondef('private.member_inbox_rows(uuid,uuid)'::regprocedure);
  def:=replace(def,'FUNCTION private.member_inbox_rows(','FUNCTION private.member_inbox_before_relative_review(');
  execute def;
  revoke all on function private.member_inbox_before_relative_review(uuid,uuid) from public,anon,authenticated,service_role;
 end if;
end $mig$;

create or replace function private.member_inbox_rows(p_org uuid, p_unit uuid)
returns table(message_key text, title text, body text, occurred_at timestamptz, target text, target_id uuid)
language sql stable security definer set search_path to '' as $$
 select * from (
  select * from private.member_inbox_before_relative_review(p_org,p_unit)
  union all
  select 'relative-review:'||r.id::text,'Pedido de familiar não aprovado'::text,
   'O pedido para incluir '||coalesce(r.data->>'name','um familiar')||' não foi aprovado. Motivo: '||coalesce(r.reason,'')||'. Você pode enviar um novo pedido.',
   r.updated_at,'profile'::text,r.id
  from private.member_family_requests r
  where r.organization_id=p_org and r.user_id=auth.uid() and r.kind='relative' and r.status='rejected' and r.updated_at>now()-interval '90 days'
 ) x order by occurred_at desc nulls last, message_key limit 100
$$;
