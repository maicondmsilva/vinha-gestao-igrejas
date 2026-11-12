-- Permissões · Fase P5 · Perfis pendentes (Pessoas) e vínculo app ↔ membro.
--  · O cadastro feito no aplicativo procura o membro por e-mail ou CPF. Com um único candidato
--    sem conta, o pedido já aponta para ele; com mais de um, o cadastro não é mais recusado:
--    fica provisório e quem analisa escolhe o membro certo, com os candidatos lado a lado.
--  · Na análise: aprovar campo a campo, escolher o "Tipo de perfil" (Membro, Frequentador ou
--    Visitante) e, em novos cadastros, ligar a conta ao membro existente ou criar o membro.
--    Ligar a um membro existente exige que e-mail ou CPF confiram; "e-mail e CPF" é indicado
--    como vínculo automático sugerido.
--  · Quem analisa: dono, administrador e pastor (como hoje) ou quem recebeu "Perfis pendentes"
--    (aprovar) na igreja do pedido.

-- 1. Cadastro no aplicativo: só candidatos sem conta; ambiguidade vira análise, não erro.
do $self$
declare d text;a text;b text;
begin
 d:=pg_get_functiondef('private.member_self_service(uuid,text,uuid,jsonb)'::regprocedure);
 a:=$a$  if (select count(*) from public.people where organization_id=p_org and (lower(btrim(email))=account_email or nullif(p_data->>'cpf','') is not null and regexp_replace(coalesce(cpf,''),'[^0-9]','','g')=p_data->>'cpf') and status not in ('rejected','deceased'))>1 then raise exception 'member_identity_ambiguous' using errcode='40001'; end if;
  select * into person from public.people where organization_id=p_org and (lower(btrim(email))=account_email or nullif(p_data->>'cpf','') is not null and regexp_replace(coalesce(cpf,''),'[^0-9]','','g')=p_data->>'cpf') and status not in ('rejected','deceased') for update;$a$;
 b:=$b$  if (select count(*) from public.people where organization_id=p_org and auth_user_id is null and (lower(btrim(email))=account_email or nullif(p_data->>'cpf','') is not null and regexp_replace(coalesce(cpf,''),'[^0-9]','','g')=p_data->>'cpf') and status not in ('rejected','deceased'))=1 then
  select * into person from public.people where organization_id=p_org and auth_user_id is null and (lower(btrim(email))=account_email or nullif(p_data->>'cpf','') is not null and regexp_replace(coalesce(cpf,''),'[^0-9]','','g')=p_data->>'cpf') and status not in ('rejected','deceased') for update;
  end if;$b$;
 if (length(d)-length(replace(d,a,'')))/length(a)<>1 then raise exception 'member_self_service_changed';end if;
 d:=replace(d,a,b);
 -- Cadastro provisório sem e-mail quando o e-mail já é de outro membro (o e-mail é único).
 a:=$a$values(p_org,p_unit,auth.uid(),trim(p_data->>'full_name'),account_email,'pending')$a$;
 b:=$b$values(p_org,p_unit,auth.uid(),trim(p_data->>'full_name'),case when exists(select 1 from public.people x where x.organization_id=p_org and lower(btrim(x.email))=account_email) then null else account_email end,'pending')$b$;
 if (length(d)-length(replace(d,a,'')))/length(a)<>1 then raise exception 'member_self_service_insert_changed';end if;
 execute replace(d,a,b);
end $self$;

-- 2. Quem analisa na igreja do pedido.
create function private.member_review_allowed(p_org uuid,p_unit uuid,p_action text) returns boolean
language sql stable security definer set search_path='' as $$
 select private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[])
  or private.can(p_org,p_unit,'people.pending_profiles',p_action)
$$;
revoke all on function private.member_review_allowed(uuid,uuid,text) from public,anon,authenticated,service_role;

-- Candidatos do pedido: membros da organização com o mesmo e-mail da conta ou o mesmo CPF.
create function private.member_review_candidates(p_org uuid,p_request uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'unit',u.name,'journey',p.journey_status,'status',p.status,
   'email',lower(btrim(coalesce(p.email,'')))=lower(a.email),'cpf',nullif(r.payload->>'cpf','') is not null and regexp_replace(coalesce(p.cpf,''),'[^0-9]','','g')=r.payload->>'cpf',
   'current',p.id=r.person_id) order by p.full_name),'[]')
 from private.member_profile_requests r join auth.users a on a.id=r.user_id
 join public.people p on p.organization_id=r.organization_id and p.status not in('rejected','deceased')
  and (p.auth_user_id is null or p.auth_user_id=r.user_id)
  and (p.id=r.person_id or lower(btrim(coalesce(p.email,'')))=lower(a.email) or nullif(r.payload->>'cpf','') is not null and regexp_replace(coalesce(p.cpf,''),'[^0-9]','','g')=r.payload->>'cpf')
 left join public.organization_units u on u.id=p.unit_id
 where r.id=p_request and r.organization_id=p_org
$$;
revoke all on function private.member_review_candidates(uuid,uuid) from public,anon,authenticated,service_role;

-- 3. Análise (lista e decisão).
create function private.member_profile_review2(p_org uuid,p_action text,p_id uuid,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.member_profile_requests;person public.people;prov public.people;current_profile jsonb;k text;account_email text;m public.organization_memberships;
 v_fields text[];v_reason text;v_target uuid;v_journey text;merged boolean:=false;cand jsonb;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_org and status in ('active','trial') for update;
 if not found then raise exception 'member_review_denied' using errcode='42501'; end if;
 perform 1 from public.organization_memberships where organization_id=p_org and user_id=auth.uid() and status='active' for share;
 if not found then raise exception 'member_review_denied' using errcode='42501'; end if;
 if p_action='list' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(q.item order by q.created_at) from (
   select req.created_at,to_jsonb(req)||jsonb_build_object('unit_name',u.name,'person_name',p.full_name,'journey',p.journey_status,
    'can_approve',private.member_review_allowed(p_org,req.unit_id,'approve'),
    'identity_match',jsonb_build_object('email',exists(select 1 from auth.users account where account.id=req.user_id and lower(account.email)=lower(p.email)),'cpf',nullif(req.payload->>'cpf','') is not null and regexp_replace(coalesce(p.cpf,''),'[^0-9]','','g')=req.payload->>'cpf','linked',p.auth_user_id=req.user_id),
    'candidates',case when req.kind='registration' then private.member_review_candidates(p_org,req.id) else '[]'::jsonb end) item
   from private.member_profile_requests req join public.organization_units u on u.id=req.unit_id left join public.people p on p.id=req.person_id
   where req.organization_id=p_org and req.status='pending' and (private.member_review_allowed(p_org,req.unit_id,'view') or private.member_review_allowed(p_org,req.unit_id,'approve'))
   order by req.created_at limit 200) q),'[]'));
 end if;
 if p_action is distinct from 'review' or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_member_review' using errcode='22023'; end if;
 select coalesce(array_agg(x),'{}') into v_fields from jsonb_array_elements_text(coalesce(p_data->'fields','[]')) x;
 v_reason:=trim(coalesce(p_data->>'reason',''));
 v_target:=nullif(p_data->>'person','')::uuid;
 v_journey:=nullif(p_data->>'journey','');
 if length(v_reason) not between 5 and 1000 or v_journey is not null and v_journey not in('Membro','Em integração','Visitante') then raise exception 'invalid_member_review' using errcode='22023'; end if;
 select * into r from private.member_profile_requests where organization_id=p_org and id=p_id for update;
 if not found or r.status<>'pending' then raise exception 'member_request_changed' using errcode='40001'; end if;
 if not private.member_review_allowed(p_org,r.unit_id,'approve') then raise exception 'member_review_denied' using errcode='42501'; end if;
 if cardinality(v_fields)<>(select count(distinct f) from unnest(v_fields) f) or exists(select 1 from unnest(v_fields) f where f is null or not r.payload ? f) then raise exception 'invalid_member_review' using errcode='22023'; end if;
 if cardinality(v_fields)>0 then
  select email into account_email from auth.users where id=r.user_id and email_confirmed_at is not null and deleted_at is null and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<=clock_timestamp()) for share;
  if not found then raise exception 'member_review_denied' using errcode='42501'; end if;
  select * into m from public.organization_memberships where organization_id=p_org and user_id=r.user_id for update;
  if not found or m.status in ('suspended','revoked') then raise exception 'member_review_denied' using errcode='42501'; end if;
  -- Vínculo com outro membro existente (só em novos cadastros, só candidatos que conferem).
  if v_target is not null and v_target is distinct from r.person_id then
   if r.kind<>'registration' then raise exception 'invalid_member_review' using errcode='22023'; end if;
   select c into cand from jsonb_array_elements(private.member_review_candidates(p_org,r.id)) c where (c->>'id')::uuid=v_target;
   if cand is null or not ((cand->>'email')::boolean or (cand->>'cpf')::boolean) then raise exception 'member_identity_conflict' using errcode='40001'; end if;
   select * into prov from public.people where id=r.person_id and organization_id=p_org for update;
   if prov.id is not null and prov.status='pending' and prov.auth_user_id=r.user_id then
    update public.people set auth_user_id=null,status='rejected' where id=prov.id;
   elsif prov.id is not null and prov.auth_user_id=r.user_id then raise exception 'member_identity_conflict' using errcode='40001';
   end if;
   update private.member_profile_requests set person_id=v_target where id=r.id returning * into r;
   merged:=true;
  end if;
  select * into person from public.people where id=r.person_id and organization_id=p_org for update;
  if not found or person.status in ('rejected','deceased','inactive') or person.auth_user_id is not null and person.auth_user_id<>r.user_id
   or (not merged and person.auth_user_id is null and (lower(person.email) is distinct from lower(account_email) and not (nullif(r.payload->>'cpf','') is not null and regexp_replace(coalesce(person.cpf,''),'[^0-9]','','g')=r.payload->>'cpf')))
   or exists(select 1 from public.people where organization_id=p_org and auth_user_id=r.user_id and id<>person.id and status<>'rejected') then raise exception 'member_identity_conflict' using errcode='40001'; end if;
  if r.kind='registration' and not 'full_name'=any(v_fields) then raise exception 'invalid_member_review' using errcode='22023'; end if;
  current_profile:=private.member_profile_snapshot(person.id);
  foreach k in array v_fields loop
   if not merged and (current_profile->k) is distinct from (r.baseline->k) then raise exception 'member_profile_changed' using errcode='40001'; end if;
   if k in ('full_name','phone','gender','marital_status','cpf') then execute format('update public.people set %I=$1 where id=$2 and organization_id=$3',k) using nullif(trim(r.payload->>k),''),person.id,p_org;
   elsif k='birth_date' then update public.people set birth_date=nullif(r.payload->>k,'')::date where id=person.id and organization_id=p_org;
   else
    insert into public.person_addresses(organization_id,person_id) values(p_org,person.id) on conflict(organization_id,person_id) do nothing;
    execute format('update public.person_addresses set %I=$1 where person_id=$2 and organization_id=$3',k) using nullif(trim(r.payload->>k),''),person.id,p_org;
   end if;
  end loop;
  if v_journey is not null then update public.people set journey_status=v_journey where id=person.id and organization_id=p_org;end if;
  if r.kind='registration' then
   update public.people set auth_user_id=r.user_id,status=case when status='pending' then 'active' else status end,email=case when nullif(btrim(email),'') is null and not exists(select 1 from public.people x where x.organization_id=p_org and x.id<>person.id and lower(btrim(x.email))=lower(account_email)) then account_email else email end where id=person.id and organization_id=p_org;
   update public.organization_memberships set status='active' where id=m.id and status='pending' and role='member';
  end if;
 end if;
 update private.member_profile_requests set status=case when cardinality(v_fields)=0 then 'rejected' when cardinality(v_fields)=(select count(*) from jsonb_object_keys(r.payload)) then 'approved' else 'partial' end,accepted_fields=v_fields,reason=v_reason,reviewed_by=auth.uid(),reviewed_at=clock_timestamp() where id=r.id;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'member.profile.reviewed','member_profile_request',r.id,
  jsonb_build_object('acceptedFields',v_fields,'person',r.person_id,'linkedToExisting',merged,'journey',v_journey));
 return jsonb_build_object('ok',true,'id',r.id,'person',r.person_id);
end $$;
revoke all on function private.member_profile_review2(uuid,text,uuid,jsonb) from public,anon,service_role;
grant execute on function private.member_profile_review2(uuid,text,uuid,jsonb) to authenticated;
create function public.member_profile_review2(p_org uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$ select private.member_profile_review2(p_org,p_action,p_id,p_data) $$;
revoke all on function public.member_profile_review2(uuid,text,uuid,jsonb) from public,anon,service_role;
grant execute on function public.member_profile_review2(uuid,text,uuid,jsonb) to authenticated;
