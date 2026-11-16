-- Pessoas v2
-- 1. Etapa "Criança": quem ganha ficha no Kids deixa de aparecer como "Visitante".
-- 2. Família pelo app: o responsável informa o grau (pai/mãe, avô/avó, tio(a), irmão(ã), padrasto/madrasta, responsável legal ou "outro").
--    Se for parentesco, a criança entra automaticamente na família dele (vínculos nos dois sentidos, visíveis no cadastro de ambos).
--    "Outro" (amigo da família, vizinho…) só autoriza buscar; não cria vínculo familiar.
-- 3. Termos: a igreja cria quantos termos quiser (para adultos ou para crianças), além dos quatro padrão.
--    A assinatura usa o cadastro de quem assina (nome e CPF mascarado no documento), sem digitar o nome.

-- ===== 1. Criança =====
create or replace function private.kids_child_journey() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
 if new.status='active' then
  update public.people set journey_status='Criança' where id=new.person_id and coalesce(journey_status,'Visitante')='Visitante';
 end if;
 return null;
end $$;
revoke all on function private.kids_child_journey() from public,anon,authenticated;
drop trigger if exists kids_child_journey on private.kids_profiles;
create trigger kids_child_journey after insert or update of status on private.kids_profiles for each row execute function private.kids_child_journey();
update public.people p set journey_status='Criança' from private.kids_profiles k where k.person_id=p.id and k.status='active' and coalesce(p.journey_status,'Visitante')='Visitante';

-- Filtros, ações em lote e cadastro rápido aceitam a nova etapa.
do $$ declare f text; d text; begin
 foreach f in array array['private.people_search(uuid,uuid,jsonb,integer,integer)','private.people_bulk(uuid,uuid,text,jsonb)','private.person_family(uuid,text,jsonb)','private.member_relatives_admin(uuid,text,jsonb)'] loop
  if to_regprocedure(f) is null then continue;end if;
  d:=pg_get_functiondef(f::regprocedure);
  if position('''Criança''' in d)>0 then continue;end if;
  d:=replace(d,'not in (''Membro'',''Em integração'',''Visitante'')','not in (''Membro'',''Em integração'',''Visitante'',''Criança'')');
  d:=replace(d,'not in (''Visitante'',''Em integração'',''Membro'')','not in (''Visitante'',''Em integração'',''Membro'',''Criança'')');
  execute d;
 end loop;
end $$;

-- ===== 2. Família pelo app =====
-- Grau informado pelo responsável (o que ELE é da criança) → vínculo familiar.
create or replace function private.kids_relation_label(p_relation text) returns text
language sql immutable set search_path to '' as $$
 select case p_relation when 'pai_mae' then 'Pai/Mãe' when 'avo' then 'Avô/Avó' when 'tio' then 'Tio(a)' when 'irmao' then 'Irmão(ã)'
  when 'padrasto_madrasta' then 'Padrasto/Madrasta' when 'responsavel_legal' then 'Responsável legal' when 'outro' then 'Pessoa autorizada' else 'Responsável' end
$$;
create or replace function private.kids_family_link(p_org uuid,p_child uuid,p_guardian uuid,p_relation text,p_actor uuid) returns boolean
language plpgsql security definer set search_path to '' as $$
declare inv text;
begin
 if p_relation is null or p_relation not in('pai_mae','avo','tio','irmao','padrasto_madrasta','responsavel_legal') or p_child=p_guardian then return false;end if;
 inv:=private.relation_inverse(p_relation);
 if exists(select 1 from private.person_relationships where (person_id,related_person_id) in((p_child,p_guardian),(p_guardian,p_child))) then return false;end if;
 -- Na ficha da criança: "<responsável> é Pai/Mãe"; na ficha do responsável: "<criança> é Filho(a)".
 insert into private.person_relationships(organization_id,person_id,related_person_id,relation,same_household,created_by)
  values(p_org,p_child,p_guardian,p_relation,p_relation in('pai_mae','padrasto_madrasta','responsavel_legal'),p_actor);
 insert into private.person_relationships(organization_id,person_id,related_person_id,relation,same_household,created_by)
  values(p_org,p_guardian,p_child,inv,p_relation in('pai_mae','padrasto_madrasta','responsavel_legal'),p_actor);
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_org,p_actor,'people.family.linked_by_kids','person',p_child::text,jsonb_build_object('guardian',p_guardian,'relation',p_relation));
 return true;
end $$;
revoke all on function private.kids_relation_label(text) from public,anon,authenticated;
revoke all on function private.kids_family_link(uuid,uuid,uuid,text,uuid) from public,anon,authenticated;

-- O app envia o grau junto com o cadastro da criança.
do $$ declare d text; begin
 d:=pg_get_functiondef('private.member_family(uuid,uuid,text,uuid,integer,jsonb,integer)'::regprocedure);
 if position('kids_relation_ok' in d)=0 then
  if position('if p_data-array[''nonce'',''name'',''birth'',''care'']<>''{}'' or' in d)=0 then raise exception 'member_family: trecho não encontrado';end if;
  d:=replace(d,'if p_data-array[''nonce'',''name'',''birth'',''care'']<>''{}'' or',
   'if p_data-array[''nonce'',''name'',''birth'',''care'',''relation'']<>''{}'' /* kids_relation_ok */ or coalesce(p_data->>''relation'',''pai_mae'') not in(''pai_mae'',''avo'',''tio'',''irmao'',''padrasto_madrasta'',''responsavel_legal'',''outro'') or');
  execute d;
 end if;
end $$;

-- Cadastro imediato: guarda o grau no vínculo Kids e liga a criança à família quando é parentesco.
create or replace function private.kids_app_create(p_request uuid) returns uuid
language plpgsql security definer set search_path to '' as $function$
declare r private.member_family_requests; child uuid; profile uuid; rel text;
begin
 select * into r from private.member_family_requests where id=p_request for update;
 if r.id is null or r.kind<>'kids.create' or r.status<>'pending' or r.profile_id is not null then return r.profile_id;end if;
 rel:=coalesce(nullif(r.data->>'relation',''),'pai_mae');
 child:=extensions.gen_random_uuid();profile:=extensions.gen_random_uuid();
 insert into public.people(id,organization_id,unit_id,full_name,birth_date,status,journey_status) values(child,r.organization_id,r.unit_id,btrim(r.data->>'name'),(r.data->>'birth')::date,'active','Criança');
 insert into private.kids_profiles(id,organization_id,unit_id,person_id,review_status,created_by) values(profile,r.organization_id,r.unit_id,child,'approved',r.user_id);
 insert into private.kids_guardians(organization_id,unit_id,profile_id,person_id,relationship,verification_note,can_pickup,can_edit,status,approved_by,approved_at,created_by)
  values(r.organization_id,r.unit_id,profile,r.person_id,private.kids_relation_label(rel)||' (a conferir)','Cadastrado pelo responsável no app; aguarda a conferência da secretaria.',true,true,'approved',r.user_id,clock_timestamp(),r.user_id)
  on conflict(profile_id,person_id) do nothing;
 perform private.kids_family_link(r.organization_id,child,r.person_id,rel,r.user_id);
 if length(btrim(coalesce(r.data->>'care','')))>0 then
  insert into private.kids_care(profile_id,organization_id,unit_id,instructions,source) values(profile,r.organization_id,r.unit_id,r.data->>'care','Informado pelo responsável no app')
   on conflict(profile_id) do update set instructions=excluded.instructions,source=excluded.source;
 end if;
 insert into private.kids_history(organization_id,unit_id,profile_id,person_id,actor_id,action,changed_fields) values(r.organization_id,r.unit_id,profile,child,r.user_id,'kids.app.created',array['profile','guardian','care','family']);
 update private.member_family_requests set profile_id=profile,updated_at=clock_timestamp() where id=r.id;
 return profile;
end $function$;
revoke all on function private.kids_app_create(uuid) from public,anon,authenticated;

-- Outros responsáveis (fixo ou temporário) com grau: parente entra na família da criança; "outro" só busca.
do $$ declare d text; begin
 d:=pg_get_functiondef('private.member_kids_temporary(uuid,text,jsonb)'::regprocedure);
 if position('kids_family_link' in d)=0 then
  if position('case when days=0 then ''Responsável (a conferir)'' else ''Responsável temporário'' end' in d)=0
   or position('  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,uid,''kids.temporary_guardian''' in d)=0
   or position('  days:=coalesce(nullif(p_data->>''days'','''')::int,1);' in d)=0 then raise exception 'member_kids_temporary: trechos não encontrados';end if;
  d:=replace(d,'  days:=coalesce(nullif(p_data->>''days'','''')::int,1);','  days:=coalesce(nullif(p_data->>''days'','''')::int,1);
  if coalesce(p_data->>''relation'',''outro'') not in(''pai_mae'',''avo'',''tio'',''irmao'',''padrasto_madrasta'',''responsavel_legal'',''outro'') then raise exception ''kids_invalid'' using errcode=''22023'';end if;');
  d:=replace(d,'case when days=0 then ''Responsável (a conferir)'' else ''Responsável temporário'' end',
   'private.kids_relation_label(coalesce(nullif(p_data->>''relation'',''''),''outro''))||case when days=0 then '' (a conferir)'' else '' · temporário'' end');
  d:=replace(d,'  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,uid,''kids.temporary_guardian''',
   '  perform private.kids_family_link(p_org,k.person_id,target.id,nullif(p_data->>''relation'',''''),uid);
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,uid,''kids.temporary_guardian''');
  execute d;
 end if;
end $$;

-- Conferência da secretaria mantém o grau: "Pai/Mãe (a conferir)" vira "Pai/Mãe".
do $$ declare d text; begin
 d:=pg_get_functiondef('private.member_family_admin(uuid,uuid,text,uuid,integer,jsonb,integer)'::regprocedure);
 if position('kids_keep_degree' in d)=0 then
  if position('on conflict(profile_id,person_id) do update set relationship=excluded.relationship,' in d)=0 then raise exception 'member_family_admin: trecho não encontrado';end if;
  d:=replace(d,'on conflict(profile_id,person_id) do update set relationship=excluded.relationship,',
   'on conflict(profile_id,person_id) do update set /* kids_keep_degree */ relationship=case when private.kids_guardians.relationship like ''% (a conferir)'' and private.kids_guardians.relationship<>''Responsável (a conferir)'' then replace(private.kids_guardians.relationship,'' (a conferir)'','''') else excluded.relationship end,');
  execute d;
 end if;
end $$;

-- ===== 3. Termos criados pela igreja =====
alter table private.consent_templates drop constraint if exists consent_templates_kind_check;
alter table private.consent_templates add constraint consent_templates_kind_check check(kind ~ '^(adult_data|adult_image|kids_guardian|kids_image|custom_[a-z0-9]{6,40})$');
alter table private.consent_records drop constraint if exists consent_records_kind_check;
alter table private.consent_records add constraint consent_records_kind_check check(kind ~ '^(adult_data|adult_image|kids_guardian|kids_image|custom_[a-z0-9]{6,40})$');
alter table private.consent_templates add column if not exists audience text not null default 'adult' check(audience in('adult','kids'));
update private.consent_templates set audience='kids' where kind like 'kids_%' and audience<>'kids';

-- Tipos em uso: os quatro padrão + os criados pela igreja que estão ativos.
create or replace function private.consent_kinds(p_org uuid) returns text[]
language sql stable security definer set search_path to '' as $$
 select array['adult_data','adult_image','kids_guardian','kids_image']||coalesce((select array_agg(distinct t.kind order by t.kind) from private.consent_templates t where t.organization_id=p_org and t.kind like 'custom_%' and t.active),'{}')
$$;
create or replace function private.consent_is_kids(p_org uuid,p_kind text) returns boolean
language sql stable security definer set search_path to '' as $$
 select p_kind like 'kids_%' or exists(select 1 from private.consent_templates t where t.organization_id=p_org and t.kind=p_kind and t.active and t.audience='kids')
$$;
create or replace function private.consent_custom_list(p_org uuid) returns jsonb
language sql stable security definer set search_path to '' as $$
 select coalesce(jsonb_agg(jsonb_build_object('kind',t.kind,'title',t.title,'audience',t.audience,'version',t.version) order by t.created_at),'[]'::jsonb)
 from private.consent_templates t where t.organization_id=p_org and t.kind like 'custom_%' and t.active
$$;
revoke all on function private.consent_kinds(uuid) from public,anon,authenticated;
revoke all on function private.consent_is_kids(uuid,text) from public,anon,authenticated;
revoke all on function private.consent_custom_list(uuid) from public,anon,authenticated;

create or replace function private.member_consent(p_org uuid, p_unit uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare uid uuid=auth.uid(); me public.people; tok uuid; kid uuid; child public.people; t record; r private.consent_records; ch jsonb; nm text; church text; v_kind text; v_kids boolean;
begin
 if uid is null then raise exception 'member_login_required' using errcode='42501';end if;
 if p_action not in('list','sign','revoke','link') or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_consent' using errcode='22023';end if;
 if not exists(select 1 from public.organizations where id=p_org and status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 select * into me from public.people where organization_id=p_org and auth_user_id=uid and status='active' order by created_at limit 1;

 if p_action='list' then
  return jsonb_build_object(
   'templates',(select jsonb_object_agg(k,(select jsonb_build_object('version',x.version,'title',x.title,'body',x.body) from private.consent_template(p_org,k) x)) from unnest(private.consent_kinds(p_org)) k),
   'custom',private.consent_custom_list(p_org),
   'signer',case when me.id is null then null else jsonb_build_object('name',me.full_name,'cpf',case when length(regexp_replace(coalesce(me.cpf,''),'\D','','g'))=11 then '***.'||substr(regexp_replace(me.cpf,'\D','','g'),4,3)||'.'||substr(regexp_replace(me.cpf,'\D','','g'),7,3)||'-**' else '' end) end,
   'items',coalesce((select jsonb_agg(private.consent_row(c) order by c.accepted_at desc) from private.consent_records c where c.organization_id=p_org and c.signer_user=uid and c.revoked_at is null),'[]'::jsonb));
 end if;

 if p_action='sign' then
  v_kind:=p_data->>'kind';
  -- Quem tem cadastro assina com os dados do cadastro (nome e CPF); sem cadastro ainda, digita o nome.
  if not (v_kind=any(private.consent_kinds(p_org))) or (me.id is null and (length(btrim(coalesce(p_data->>'signerName','')))<5 or position(' ' in btrim(p_data->>'signerName'))=0))
   or length(coalesce(p_data->>'device',''))>120 or coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' then raise exception 'invalid_consent' using errcode='22023';end if;
  select * into r from private.consent_records where id=(p_data->>'id')::uuid;
  if r.id is not null then if r.signer_user=uid then return jsonb_build_object('ok',true,'item',private.consent_row(r));end if;raise exception 'invalid_consent' using errcode='22023';end if;
  -- Escolhas de imagem: fotos, vídeos, redes sociais e transmissões ao vivo.
  ch:='{}'::jsonb;
  if v_kind in('adult_image','kids_image') then
   if jsonb_typeof(p_data->'choices')<>'object' or exists(select 1 from jsonb_each(p_data->'choices') e where e.key not in('photos','videos','social','live') or jsonb_typeof(e.value)<>'boolean') then raise exception 'invalid_consent' using errcode='22023';end if;
   ch:=jsonb_build_object('photos',coalesce((p_data->'choices'->>'photos')::boolean,false),'videos',coalesce((p_data->'choices'->>'videos')::boolean,false),'social',coalesce((p_data->'choices'->>'social')::boolean,false),'live',coalesce((p_data->'choices'->>'live')::boolean,false));
  end if;
  v_kids:=private.consent_is_kids(p_org,v_kind);
  if v_kids then
   kid:=nullif(p_data->>'child','')::uuid;
   select p.* into child from private.kids_profiles k join public.people p on p.id=k.person_id join private.kids_guardians g on g.profile_id=k.id and g.organization_id=k.organization_id
    where k.id=kid and k.organization_id=p_org and g.person_id=me.id and g.status='approved' and (g.valid_until is null or g.valid_until>now()) limit 1;
   if me.id is null or child.id is null then raise exception 'consent_denied' using errcode='42501';end if;
   nm:=child.full_name;
  else
   nm:=coalesce(me.full_name,btrim(p_data->>'signerName'));
  end if;
  select o.name into church from public.organizations o where o.id=p_org;
  if p_unit is not null then select coalesce(u.name,church) into church from public.organization_units u where u.id=p_unit and u.organization_id=p_org;end if;
  select * into t from private.consent_template(p_org,v_kind);
  if t.version is null then raise exception 'invalid_consent' using errcode='22023';end if;
  r:=row((p_data->>'id')::uuid,private.consent_new_code(),p_org,p_unit,v_kind,t.version,t.title,t.body,ch||case when length(regexp_replace(coalesce(me.cpf,''),'\D','','g'))=11 then jsonb_build_object('signerCpf','***.'||substr(regexp_replace(me.cpf,'\D','','g'),4,3)||'.'||substr(regexp_replace(me.cpf,'\D','','g'),7,3)||'-**') else '{}'::jsonb end,uid,me.id,coalesce(nullif(btrim(me.full_name),''),btrim(p_data->>'signerName')),
   case when v_kids then child.id else me.id end,nm,kid,church,coalesce(p_data->>'device',''),date_trunc('milliseconds',clock_timestamp()),repeat('0',64),null,null)::private.consent_records;
  r.sha256:=encode(extensions.digest(private.consent_canonical(r),'sha256'),'hex');
  -- O novo aceite substitui o anterior do mesmo tipo e da mesma pessoa.
  update private.consent_records set revoked_at=clock_timestamp(),revoked_reason='Substituído por '||r.code
   where organization_id=p_org and signer_user=uid and kind=v_kind and coalesce(kids_profile,'00000000-0000-0000-0000-000000000000')=coalesce(kid,'00000000-0000-0000-0000-000000000000') and revoked_at is null;
  insert into private.consent_records select (r).*;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,uid,'consent.signed','consent_record',r.id::text,jsonb_build_object('kind',v_kind,'code',r.code));
  return jsonb_build_object('ok',true,'item',private.consent_row(r));
 end if;

 select * into r from private.consent_records where id=nullif(p_data->>'id','')::uuid and organization_id=p_org and signer_user=uid;
 if r.id is null then raise exception 'consent_denied' using errcode='42501';end if;
 if p_action='revoke' then
  if r.revoked_at is not null then return jsonb_build_object('ok',true);end if;
  update private.consent_records set revoked_at=clock_timestamp(),revoked_reason='Revogado pelo titular no aplicativo' where id=r.id;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,uid,'consent.revoked','consent_record',r.id::text,jsonb_build_object('kind',r.kind,'code',r.code));
  return jsonb_build_object('ok',true);
 end if;
 -- link: endereço de uso único (10 min) para abrir o PDF no navegador.
 delete from private.consent_links where expires_at<now();
 insert into private.consent_links(record_id) values(r.id) returning token into tok;
 return jsonb_build_object('token',tok);
end $function$;

create or replace function private.consent_templates_admin(p_org uuid, p_action text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v integer; v_kind text; v_aud text;
begin
 if not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'consent_denied' using errcode='42501';end if;
 if p_action='list' then
  return jsonb_build_object('items',(select jsonb_agg(jsonb_build_object('kind',k,'version',x.version,'title',x.title,'body',x.body,'custom',x.version>0) order by k) from unnest(private.consent_kinds(p_org)) k cross join lateral private.consent_template(p_org,k) x),
   'custom',private.consent_custom_list(p_org));
 elsif p_action='save' then
  v_kind:=p_data->>'kind';
  v_aud:=case when v_kind like 'custom_%' then coalesce(nullif(p_data->>'audience',''),'adult') when v_kind like 'kids_%' then 'kids' else 'adult' end;
  if coalesce(v_kind,'') !~ '^(adult_data|adult_image|kids_guardian|kids_image|custom_[a-z0-9]{6,40})$' or v_aud not in('adult','kids') or length(btrim(coalesce(p_data->>'title','')))<3 or length(btrim(coalesce(p_data->>'body','')))<20 or length(p_data->>'body')>8000 or length(p_data->>'title')>120 then raise exception 'invalid_consent' using errcode='22023';end if;
  perform pg_advisory_xact_lock(hashtextextended('consent:'||p_org::text||(p_data->>'kind'),0));
  select coalesce(max(version),0)+1 into v from private.consent_templates where organization_id=p_org and kind=p_data->>'kind';
  update private.consent_templates set active=false where organization_id=p_org and kind=p_data->>'kind' and active;
  insert into private.consent_templates(organization_id,kind,version,title,body,created_by,audience) values(p_org,p_data->>'kind',v,btrim(p_data->>'title'),btrim(p_data->>'body'),auth.uid(),v_aud);
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'consent.template_saved','consent_template',p_data->>'kind',jsonb_build_object('version',v));
  return jsonb_build_object('ok',true,'version',v);
 elsif p_action='archive' then
  -- Só termos criados pela igreja podem sair do app; aceites já assinados continuam válidos e consultáveis.
  if coalesce(p_data->>'kind','') !~ '^custom_[a-z0-9]{6,40}$' then raise exception 'invalid_consent' using errcode='22023';end if;
  update private.consent_templates set active=false where organization_id=p_org and kind=p_data->>'kind' and active;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'consent.template_archived','consent_template',p_data->>'kind');
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'invalid_consent' using errcode='22023';
end $function$;

