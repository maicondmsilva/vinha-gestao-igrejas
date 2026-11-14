-- Termos de consentimento com autenticação (assinatura eletrônica simples, Lei 14.063/2020 art. 4º, I).
-- Tipos: adult_data (dados pessoais), adult_image (imagem e voz do membro),
--        kids_guardian (responsável pela criança) e kids_image (imagem da criança).
-- Cada aceite guarda o texto exato da versão, as escolhas, quem assinou (conta, cadastro e nome digitado),
-- data/hora, aparelho, um código de verificação (VNH-XXXX-XXXX) e a impressão digital SHA-256 do documento.

create table if not exists private.consent_templates(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 kind text not null check(kind in('adult_data','adult_image','kids_guardian','kids_image')),
 version integer not null check(version>0),
 title text not null check(length(btrim(title)) between 3 and 120),
 body text not null check(length(btrim(body)) between 20 and 8000),
 active boolean not null default true,
 created_by uuid,created_at timestamptz not null default now(),
 unique(organization_id,kind,version)
);
create unique index if not exists consent_templates_active on private.consent_templates(organization_id,kind) where active;

create table if not exists private.consent_records(
 id uuid primary key,
 code text not null unique check(code ~ '^VNH-[A-Z2-9]{4}-[A-Z2-9]{4}$'),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid references public.organization_units(id) on delete set null,
 kind text not null check(kind in('adult_data','adult_image','kids_guardian','kids_image')),
 version integer not null,
 title text not null,
 body text not null,
 choices jsonb not null default '{}'::jsonb check(jsonb_typeof(choices)='object'),
 signer_user uuid references auth.users(id) on delete set null,
 signer_person uuid references public.people(id) on delete set null,
 signer_name text not null check(length(btrim(signer_name)) between 5 and 160),
 subject_person uuid references public.people(id) on delete set null,
 subject_name text not null,
 kids_profile uuid,
 church_name text not null,
 device text not null default '' check(length(device)<=120),
 accepted_at timestamptz not null default now(),
 sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),
 revoked_at timestamptz,
 revoked_reason text check(revoked_reason is null or length(revoked_reason)<=200)
);
create index if not exists consent_records_signer on private.consent_records(signer_user,organization_id);
create index if not exists consent_records_subject on private.consent_records(subject_person);
create index if not exists consent_records_kids on private.consent_records(kids_profile);
create table if not exists private.consent_links(
 token uuid primary key default gen_random_uuid(),
 record_id uuid not null references private.consent_records(id) on delete cascade,
 expires_at timestamptz not null default now()+interval '10 minutes'
);
alter table private.consent_templates enable row level security;
alter table private.consent_records enable row level security;
alter table private.consent_links enable row level security;
revoke all on private.consent_templates,private.consent_records,private.consent_links from public,anon,authenticated;

-- Textos padrão, usados até a igreja publicar a própria versão no painel.
create or replace function private.consent_default(p_kind text) returns table(title text, body text)
language sql immutable set search_path to '' as $$
 select d.title,d.body from (values
  ('adult_data','Termo de consentimento para tratamento de dados pessoais',
   E'Autorizo a igreja identificada neste documento a tratar meus dados pessoais (nome, contatos, data de nascimento, documento, endereço, vínculos familiares e participação em atividades) para:\n• manter meu cadastro de membro;\n• cuidado pastoral, células, ministérios e eventos;\n• comunicação institucional pelo aplicativo, e-mail ou WhatsApp.\n\nOs dados são acessados apenas por pessoas autorizadas pela igreja, guardados enquanto durar meu vínculo e pelo tempo exigido em lei, e não são vendidos a terceiros.\n\nSei que posso pedir acesso, correção, portabilidade ou exclusão dos meus dados, e revogar este consentimento, falando com a secretaria da igreja (Lei 13.709/2018 — LGPD).'),
  ('adult_image','Termo de autorização de uso de imagem e voz',
   E'Autorizo, de forma gratuita e por prazo indeterminado, o uso da minha imagem e voz captadas em cultos, eventos e atividades da igreja, nas formas marcadas abaixo, para divulgação institucional e evangelística.\n\nA igreja não usará minha imagem de forma que prejudique minha honra ou reputação, nem para fins comerciais.\n\nPosso revogar esta autorização a qualquer momento para usos futuros, pelo aplicativo ou na secretaria. Materiais já publicados antes da revogação não precisam ser retirados.'),
  ('kids_guardian','Termo do responsável pela criança — Área Kids',
   E'Declaro ser responsável legal ou pessoa autorizada pela criança identificada neste documento e consinto com:\n• o cadastro da criança na Área Kids da igreja;\n• o tratamento dos dados necessários à segurança dela, inclusive alergias, restrições alimentares e informações de saúde informadas por mim;\n• os registros de entrada e saída das salas.\n\nEntendo que a criança só será entregue a pessoas autorizadas e conferidas pela equipe, e que devo manter os dados atualizados.\n\nPosso pedir acesso, correção ou exclusão dos dados e revogar este consentimento na secretaria da igreja (LGPD, art. 14).'),
  ('kids_image','Termo de autorização de uso de imagem da criança',
   E'Na condição de responsável, autorizo, de forma gratuita, o uso da imagem e voz da criança identificada neste documento, captadas em atividades da igreja, nas formas marcadas abaixo, para divulgação institucional.\n\nA igreja não divulgará nome completo, escola ou endereço da criança junto das imagens e não as usará para fins comerciais.\n\nPosso revogar esta autorização a qualquer momento para usos futuros, pelo aplicativo ou na secretaria.')
 ) d(kind,title,body) where d.kind=p_kind
$$;

create or replace function private.consent_template(p_org uuid, p_kind text) returns table(version integer, title text, body text)
language sql stable security definer set search_path to '' as $$
 select t.version,t.title,t.body from private.consent_templates t where t.organization_id=p_org and t.kind=p_kind and t.active
 union all
 select 0,d.title,d.body from private.consent_default(p_kind) d where not exists(select 1 from private.consent_templates t where t.organization_id=p_org and t.kind=p_kind and t.active)
 limit 1
$$;
revoke all on function private.consent_template(uuid,text) from public,anon,authenticated;

-- Texto canônico que é assinado (e recalculado na verificação).
create or replace function private.consent_canonical(r private.consent_records) returns text
language sql immutable set search_path to '' as $$
 select concat_ws(E'\n','VINHA-TERMO-V1',r.code,r.organization_id::text,r.kind,r.version::text,r.title,r.body,r.choices::text,
  coalesce(r.signer_user::text,''),r.signer_name,r.subject_name,coalesce(r.kids_profile::text,''),r.church_name,
  to_char(r.accepted_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
$$;

create or replace function private.consent_new_code() returns text language plpgsql volatile set search_path to '' as $$
declare a constant text='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea; c text; i int;
begin
 loop
  b:=extensions.gen_random_bytes(8);c:='';
  for i in 0..7 loop c:=c||substr(a,(get_byte(b,i)%32)+1,1);end loop;
  c:='VNH-'||substr(c,1,4)||'-'||substr(c,5,4);
  exit when not exists(select 1 from private.consent_records where code=c);
 end loop;
 return c;
end $$;

create or replace function private.consent_row(r private.consent_records) returns jsonb
language sql stable set search_path to '' as $$
 select jsonb_build_object('id',r.id,'code',r.code,'kind',r.kind,'version',r.version,'title',r.title,'choices',r.choices,'signerName',r.signer_name,
  'subjectName',r.subject_name,'kidsProfile',r.kids_profile,'acceptedAt',r.accepted_at,'sha256',r.sha256,'revokedAt',r.revoked_at,'revokedReason',r.revoked_reason)
$$;

-- ===== Membro (app) =====
create or replace function private.member_consent(p_org uuid, p_unit uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare uid uuid=auth.uid(); me public.people; tok uuid; kid uuid; child public.people; t record; r private.consent_records; ch jsonb; nm text; church text; v_kind text;
begin
 if uid is null then raise exception 'member_login_required' using errcode='42501';end if;
 if p_action not in('list','sign','revoke','link') or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_consent' using errcode='22023';end if;
 if not exists(select 1 from public.organizations where id=p_org and status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 select * into me from public.people where organization_id=p_org and auth_user_id=uid and status='active' order by created_at limit 1;

 if p_action='list' then
  return jsonb_build_object(
   'templates',(select jsonb_object_agg(k,(select jsonb_build_object('version',x.version,'title',x.title,'body',x.body) from private.consent_template(p_org,k) x)) from unnest(array['adult_data','adult_image','kids_guardian','kids_image']) k),
   'items',coalesce((select jsonb_agg(private.consent_row(c) order by c.accepted_at desc) from private.consent_records c where c.organization_id=p_org and c.signer_user=uid and c.revoked_at is null),'[]'::jsonb));
 end if;

 if p_action='sign' then
  v_kind:=p_data->>'kind';
  if v_kind not in('adult_data','adult_image','kids_guardian','kids_image') or length(btrim(coalesce(p_data->>'signerName','')))<5 or position(' ' in btrim(p_data->>'signerName'))=0
   or length(coalesce(p_data->>'device',''))>120 or coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' then raise exception 'invalid_consent' using errcode='22023';end if;
  select * into r from private.consent_records where id=(p_data->>'id')::uuid;
  if r.id is not null then if r.signer_user=uid then return jsonb_build_object('ok',true,'item',private.consent_row(r));end if;raise exception 'invalid_consent' using errcode='22023';end if;
  -- Escolhas de imagem: fotos, vídeos, redes sociais e transmissões ao vivo.
  ch:='{}'::jsonb;
  if v_kind in('adult_image','kids_image') then
   if jsonb_typeof(p_data->'choices')<>'object' or exists(select 1 from jsonb_each(p_data->'choices') e where e.key not in('photos','videos','social','live') or jsonb_typeof(e.value)<>'boolean') then raise exception 'invalid_consent' using errcode='22023';end if;
   ch:=jsonb_build_object('photos',coalesce((p_data->'choices'->>'photos')::boolean,false),'videos',coalesce((p_data->'choices'->>'videos')::boolean,false),'social',coalesce((p_data->'choices'->>'social')::boolean,false),'live',coalesce((p_data->'choices'->>'live')::boolean,false));
  end if;
  if v_kind like 'kids_%' then
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
  r:=row((p_data->>'id')::uuid,private.consent_new_code(),p_org,p_unit,v_kind,t.version,t.title,t.body,ch,uid,me.id,btrim(p_data->>'signerName'),
   case when v_kind like 'kids_%' then child.id else me.id end,nm,kid,church,coalesce(p_data->>'device',''),date_trunc('milliseconds',clock_timestamp()),repeat('0',64),null,null)::private.consent_records;
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
revoke all on function private.member_consent(uuid,uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.member_consent(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.member_consent(p_org,p_unit,p_action,p_data) $$;
revoke all on function public.member_consent(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.member_consent(uuid,uuid,text,jsonb) to authenticated;

-- ===== Verificação pública (vinhaigrejas.com.br/verificar/CÓDIGO) =====
-- Mostra só o necessário para provar a autenticidade: nada de CPF, contatos ou texto completo.
create or replace function private.consent_verify(p_code text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare r private.consent_records; ini text;
begin
 if coalesce(p_code,'') !~ '^VNH-[A-Z2-9]{4}-[A-Z2-9]{4}$' then return jsonb_build_object('found',false);end if;
 select * into r from private.consent_records where code=upper(p_code);
 if r.id is null then return jsonb_build_object('found',false);end if;
 return jsonb_build_object('found',true,'code',r.code,'title',r.title,'version',r.version,'church',r.church_name,'acceptedAt',r.accepted_at,
  'signer',split_part(r.signer_name,' ',1)||' '||left(split_part(btrim(r.signer_name),' ',array_length(regexp_split_to_array(btrim(r.signer_name),'\s+'),1)),1)||'.',
  'subject',case when r.kind like 'kids_%' then split_part(r.subject_name,' ',1) else null end,
  'choices',r.choices,'sha256',r.sha256,'intact',encode(extensions.digest(private.consent_canonical(r),'sha256'),'hex')=r.sha256,
  'revokedAt',r.revoked_at,'revokedReason',case when r.revoked_reason like 'Substituído%' then r.revoked_reason else case when r.revoked_at is null then null else 'Revogado' end end);
end $function$;
revoke all on function private.consent_verify(text) from public,anon,authenticated;
create or replace function public.consent_verify(p_code text) returns jsonb
language sql stable security definer set search_path to '' as $$ select private.consent_verify(p_code) $$;
revoke all on function public.consent_verify(text) from public;
grant execute on function public.consent_verify(text) to anon,authenticated;

-- ===== Documento completo para o PDF =====
-- Por código, com a sessão: quem assinou ou quem pode ver o cadastro na igreja. Por token: link de uso único (só o servidor).
create or replace function private.consent_document(p_code text, p_token uuid) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare r private.consent_records;
begin
 if p_token is not null then
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'consent_denied' using errcode='42501';end if;
  select c.* into r from private.consent_links l join private.consent_records c on c.id=l.record_id where l.token=p_token and l.expires_at>now();
  delete from private.consent_links where token=p_token;
 else
  select * into r from private.consent_records where code=upper(coalesce(p_code,''));
  if r.id is not null and not(r.signer_user=auth.uid() or (r.subject_person is not null and private.can_view_person(r.subject_person))
   or (r.signer_person is not null and private.can_view_person(r.signer_person))) then r:=null;end if;
 end if;
 if r.id is null then raise exception 'consent_denied' using errcode='42501';end if;
 return private.consent_row(r)||jsonb_build_object('body',r.body,'church',r.church_name,'device',r.device,'intact',encode(extensions.digest(private.consent_canonical(r),'sha256'),'hex')=r.sha256);
end $function$;
revoke all on function private.consent_document(text,uuid) from public,anon,authenticated;
create or replace function public.consent_document(p_code text, p_token uuid default null) returns jsonb
language sql security definer set search_path to '' as $$ select private.consent_document(p_code,p_token) $$;
revoke all on function public.consent_document(text,uuid) from public,anon;
grant execute on function public.consent_document(text,uuid) to authenticated,service_role;

-- ===== Ficha da pessoa no painel =====
create or replace function private.people_consents(p_org uuid, p_person uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
begin
 if not exists(select 1 from public.people where id=p_person and organization_id=p_org) or not private.can_view_person(p_person) then raise exception 'consent_denied' using errcode='42501';end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(private.consent_row(c) order by c.accepted_at desc) from private.consent_records c
  where c.organization_id=p_org and (c.subject_person=p_person or c.signer_person=p_person)),'[]'::jsonb));
end $function$;
revoke all on function private.people_consents(uuid,uuid) from public,anon,authenticated;
create or replace function public.people_consents(p_org uuid, p_person uuid) returns jsonb
language sql stable security definer set search_path to '' as $$ select private.people_consents(p_org,p_person) $$;
revoke all on function public.people_consents(uuid,uuid) from public,anon;
grant execute on function public.people_consents(uuid,uuid) to authenticated;

-- ===== Modelos no painel (dono, administração e pastores) =====
create or replace function private.consent_templates_admin(p_org uuid, p_action text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v integer;
begin
 if not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) then raise exception 'consent_denied' using errcode='42501';end if;
 if p_action='list' then
  return jsonb_build_object('items',(select jsonb_agg(jsonb_build_object('kind',k,'version',x.version,'title',x.title,'body',x.body,'custom',x.version>0) order by k) from unnest(array['adult_data','adult_image','kids_guardian','kids_image']) k cross join lateral private.consent_template(p_org,k) x));
 elsif p_action='save' then
  if p_data->>'kind' not in('adult_data','adult_image','kids_guardian','kids_image') or length(btrim(coalesce(p_data->>'title','')))<3 or length(btrim(coalesce(p_data->>'body','')))<20 or length(p_data->>'body')>8000 or length(p_data->>'title')>120 then raise exception 'invalid_consent' using errcode='22023';end if;
  perform pg_advisory_xact_lock(hashtextextended('consent:'||p_org::text||(p_data->>'kind'),0));
  select coalesce(max(version),0)+1 into v from private.consent_templates where organization_id=p_org and kind=p_data->>'kind';
  update private.consent_templates set active=false where organization_id=p_org and kind=p_data->>'kind' and active;
  insert into private.consent_templates(organization_id,kind,version,title,body,created_by) values(p_org,p_data->>'kind',v,btrim(p_data->>'title'),btrim(p_data->>'body'),auth.uid());
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'consent.template_saved','consent_template',p_data->>'kind',jsonb_build_object('version',v));
  return jsonb_build_object('ok',true,'version',v);
 end if;
 raise exception 'invalid_consent' using errcode='22023';
end $function$;
revoke all on function private.consent_templates_admin(uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.consent_templates_admin(p_org uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.consent_templates_admin(p_org,p_action,p_data) $$;
revoke all on function public.consent_templates_admin(uuid,text,jsonb) from public,anon;
grant execute on function public.consent_templates_admin(uuid,text,jsonb) to authenticated;

-- Termo assinado antes da aprovação do cadastro passa a apontar para o membro quando a conta é vinculada.
create or replace function private.people_consents_link() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
 if new.auth_user_id is not null and (tg_op='INSERT' or old.auth_user_id is distinct from new.auth_user_id) then
  update private.consent_records set signer_person=new.id,subject_person=case when kind like 'adult_%' then new.id else subject_person end
   where organization_id=new.organization_id and signer_user=new.auth_user_id and signer_person is null;
 end if;
 return new;
end $$;
revoke all on function private.people_consents_link() from public,anon,authenticated;
drop trigger if exists people_consents_link on public.people;
create trigger people_consents_link after insert or update of auth_user_id on public.people for each row execute function private.people_consents_link();
