-- Kids · número da etiqueta (por encontro) e telão pelo Holyrics.
-- O telão mostra só o número, nunca o nome da criança. A chave da API e o token do Holyrics ficam no Vault
-- e o envio sai do próprio banco (pg_net) para https://api.holyrics.com.br/send/SetAlert.

alter table private.kids_attendance add column if not exists tag_number integer;
create unique index if not exists kids_attendance_tag on private.kids_attendance(session_id,tag_number) where tag_number is not null;

create or replace function private.kids_attendance_tag() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
 if new.tag_number is null then
  perform pg_advisory_xact_lock(hashtextextended('kids-tag:'||new.session_id::text,0));
  select coalesce(max(tag_number),0)+1 into new.tag_number from private.kids_attendance where session_id=new.session_id;
 end if;
 return new;
end $$;
revoke all on function private.kids_attendance_tag() from public,anon,authenticated;
drop trigger if exists kids_attendance_tag on private.kids_attendance;
create trigger kids_attendance_tag before insert on private.kids_attendance for each row execute function private.kids_attendance_tag();

-- Presenças antigas ganham número na ordem de entrada.
update private.kids_attendance a set tag_number=x.n from (select id,row_number() over(partition by session_id order by checked_in_at,id) n from private.kids_attendance) x where x.id=a.id and a.tag_number is null;

-- Quadro do encontro (painel e Vinha Equipe) passa a trazer o número.
do $$ declare d text; begin
 d:=pg_get_functiondef('private.kids_operations_page(uuid,uuid,uuid,uuid,text,text)'::regprocedure);
 if position('''tag'',a.tag_number' in d)=0 then
  if (length(d)-length(replace(d,'''inAt'',a.checked_in_at','')))/length('''inAt'',a.checked_in_at')<>1 then raise exception 'kids_operations_page: item não encontrado';end if;
  execute replace(d,'''inAt'',a.checked_in_at','''tag'',a.tag_number,''inAt'',a.checked_in_at');
 end if;
end $$;

-- Configuração do telão por igreja local.
create table if not exists private.kids_projectors(
 unit_id uuid primary key references public.organization_units(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 enabled boolean not null default false,
 secret_id uuid,
 updated_by uuid,
 updated_at timestamptz not null default now()
);
alter table private.kids_projectors enable row level security;
revoke all on private.kids_projectors from public,anon,authenticated;

create table if not exists private.kids_projector_log(
 id bigint generated always as identity primary key,
 organization_id uuid not null,
 unit_id uuid not null,
 call_id uuid,
 action text not null check(action in('alert','hide','test')),
 request_id bigint,
 created_at timestamptz not null default now()
);
create index if not exists kids_projector_log_unit on private.kids_projector_log(unit_id,created_at desc);
alter table private.kids_projector_log enable row level security;
revoke all on private.kids_projector_log from public,anon,authenticated;

alter table private.kids_guardian_calls add column if not exists projector boolean not null default false;

-- Envia ao Holyrics (quando a igreja ligou o telão) e registra. Sem pg_net, só registra.
create or replace function private.kids_projector_send(p_org uuid, p_unit uuid, p_call uuid, p_action text, p_body jsonb) returns boolean
language plpgsql security definer set search_path to '' as $function$
declare cfg private.kids_projectors; sec jsonb; req bigint;
begin
 select * into cfg from private.kids_projectors where unit_id=p_unit and organization_id=p_org;
 if cfg.unit_id is null or cfg.secret_id is null or (not cfg.enabled and p_action<>'test') then return false;end if;
 select decrypted_secret::jsonb into sec from vault.decrypted_secrets where id=cfg.secret_id;
 if coalesce(sec->>'apiKey','')='' or coalesce(sec->>'token','')='' then return false;end if;
 if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null then
  execute 'select net.http_post(url:=$1,body:=$2,headers:=$3,timeout_milliseconds:=8000)' into req
   using 'https://api.holyrics.com.br/send/SetAlert',p_body,jsonb_build_object('Content-Type','application/json','api_key',sec->>'apiKey','token',sec->>'token');
 end if;
 insert into private.kids_projector_log(organization_id,unit_id,call_id,action,request_id) values(p_org,p_unit,p_call,p_action,req);
 return true;
end $function$;
revoke all on function private.kids_projector_send(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;

create or replace function private.kids_call_projector() returns trigger
language plpgsql security definer set search_path to '' as $function$
declare tag int; room text;
begin
 if tg_op='INSERT' and new.projector then
  select a.tag_number,r.name into tag,room from private.kids_attendance a left join private.kids_session_rooms g on g.id=a.group_id left join private.kids_rooms r on r.id=g.room_id where a.id=new.attendance_id;
  perform private.kids_projector_send(new.organization_id,new.unit_id,new.id,'alert',jsonb_build_object(
   'text','Kids: responsável pela criança nº '||coalesce(tag::text,'?')||', compareça à '||coalesce(nullif(room,''),'sala Kids'),'show',true,'close_after_seconds',60));
 elsif tg_op='UPDATE' and new.projector and old.answer is null and new.answer is not null then
  perform private.kids_projector_send(new.organization_id,new.unit_id,new.id,'hide',jsonb_build_object('text','','show',false));
 end if;
 return new;
end $function$;
revoke all on function private.kids_call_projector() from public,anon,authenticated;
drop trigger if exists kids_call_projector on private.kids_guardian_calls;
create trigger kids_call_projector after insert or update of answer on private.kids_guardian_calls for each row execute function private.kids_call_projector();

-- Coordenação Kids e administração: ver se está configurado, salvar e testar.
create or replace function private.kids_projector(p_org uuid, p_unit uuid, p_action text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare cfg private.kids_projectors; sec jsonb; sid uuid;
begin
 if auth.uid() is null or not private.kids_allowed(p_org,p_unit,'approve') then raise exception 'kids_access_denied' using errcode='42501';end if;
 if not exists(select 1 from public.organization_units where id=p_unit and organization_id=p_org) then raise exception 'kids_access_denied' using errcode='42501';end if;
 select * into cfg from private.kids_projectors where unit_id=p_unit and organization_id=p_org;
 if p_action='get' then
  return jsonb_build_object('enabled',coalesce(cfg.enabled,false),'configured',cfg.secret_id is not null,'updatedAt',cfg.updated_at);
 elsif p_action='save' then
  if p_data is null or jsonb_typeof(p_data)<>'object' or jsonb_typeof(p_data->'enabled')<>'boolean'
   or length(coalesce(p_data->>'apiKey',''))>200 or length(coalesce(p_data->>'token',''))>200 then raise exception 'invalid_kids_projector' using errcode='22023';end if;
  sid:=cfg.secret_id;
  if coalesce(p_data->>'apiKey','')<>'' or coalesce(p_data->>'token','')<>'' then
   if sid is not null then select decrypted_secret::jsonb into sec from vault.decrypted_secrets where id=sid;end if;
   sec:=coalesce(sec,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object('apiKey',nullif(btrim(p_data->>'apiKey'),''),'token',nullif(btrim(p_data->>'token'),'')));
   if sid is null then sid:=vault.create_secret(sec::text,'holyrics:'||p_unit::text,'Telão Kids (Holyrics)');
   else perform vault.update_secret(sid,sec::text);end if;
  end if;
  if (p_data->>'enabled')::boolean and sid is null then raise exception 'kids_projector_missing' using errcode='22023';end if;
  insert into private.kids_projectors(unit_id,organization_id,enabled,secret_id,updated_by) values(p_unit,p_org,(p_data->>'enabled')::boolean,sid,auth.uid())
   on conflict(unit_id) do update set enabled=excluded.enabled,secret_id=excluded.secret_id,updated_by=excluded.updated_by,updated_at=clock_timestamp();
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'kids.projector_saved','organization_unit',p_unit::text,jsonb_build_object('enabled',(p_data->>'enabled')::boolean));
  return jsonb_build_object('ok',true,'enabled',(p_data->>'enabled')::boolean,'configured',sid is not null);
 elsif p_action='test' then
  if cfg.secret_id is null then raise exception 'kids_projector_missing' using errcode='22023';end if;
  return jsonb_build_object('ok',private.kids_projector_send(p_org,p_unit,null,'test',jsonb_build_object('text','Teste do telão Kids pela Vinha','show',true,'close_after_seconds',10)));
 end if;
 raise exception 'invalid_kids_projector' using errcode='22023';
end $function$;
revoke all on function private.kids_projector(uuid,uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.kids_projector(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.kids_projector(p_org,p_unit,p_action,p_data) $$;
revoke all on function public.kids_projector(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.kids_projector(uuid,uuid,text,jsonb) to authenticated;

-- Chamados: a lista traz número e sala; o chamado aceita "projector" (padrão: ligado quando a igreja tem telão).
do $$ declare d text; begin
 d:=pg_get_functiondef('private.kids_call(uuid,uuid,text,jsonb)'::regprocedure);
 if position('''tag'',ka.tag_number' in d)=0 then
  d:=replace(d,'''answeredAt'',k.answered_at) order by k.created_at desc)','''answeredAt'',k.answered_at,''tag'',ka.tag_number) order by k.created_at desc)');
  d:=replace(d,'from private.kids_guardian_calls k join private.kids_profiles kp on kp.id=k.profile_id join public.people p on p.id=kp.person_id
   where k.organization_id=p_org and k.unit_id=p_unit and k.session_id=v_session and k.created_at>now()-interval ''12 hours''),''[]''::jsonb));',
   'from private.kids_guardian_calls k join private.kids_profiles kp on kp.id=k.profile_id join public.people p on p.id=kp.person_id left join private.kids_attendance ka on ka.id=k.attendance_id
   where k.organization_id=p_org and k.unit_id=p_unit and k.session_id=v_session and k.created_at>now()-interval ''12 hours''),''[]''::jsonb),
   ''tags'',coalesce((select jsonb_object_agg(x.id,x.tag_number) from private.kids_attendance x where x.session_id=v_session and x.checked_out_at is null and x.tag_number is not null),''{}''::jsonb),
   ''projector'',exists(select 1 from private.kids_projectors pj where pj.unit_id=p_unit and pj.organization_id=p_org and pj.enabled and pj.secret_id is not null));');
  d:=replace(d,'insert into private.kids_guardian_calls(id,organization_id,unit_id,attendance_id,profile_id,session_id,group_id,reason,message,created_by)
  values((p_data->>''id'')::uuid,p_org,p_unit,a.id,a.profile_id,a.session_id,a.group_id,p_data->>''reason'',btrim(coalesce(p_data->>''message'','''')),auth.uid());',
   'insert into private.kids_guardian_calls(id,organization_id,unit_id,attendance_id,profile_id,session_id,group_id,reason,message,created_by,projector)
  values((p_data->>''id'')::uuid,p_org,p_unit,a.id,a.profile_id,a.session_id,a.group_id,p_data->>''reason'',btrim(coalesce(p_data->>''message'','''')),auth.uid(),coalesce((p_data->>''projector'')::boolean,true));');
  if position('''tag'',ka.tag_number' in d)=0 or position('''projector'',exists' in d)=0 or position('auth.uid(),coalesce((p_data->>''projector'')' in d)=0 then raise exception 'kids_call: trechos não encontrados';end if;
  execute d;
 end if;
end $$;

-- Responsável: crianças presentes agora, com número e sala.
create or replace function private.member_kids_present(p_org uuid) returns jsonb
language sql stable security definer set search_path to '' as $$
 select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('profile',a.profile_id,'child',split_part(p.full_name,' ',1),'tag',a.tag_number,'room',coalesce(r.name,''),'inAt',a.checked_in_at) order by a.checked_in_at),'[]'::jsonb))
 from private.kids_attendance a join private.kids_profiles kp on kp.id=a.profile_id join public.people p on p.id=kp.person_id
  left join private.kids_session_rooms g on g.id=a.group_id left join private.kids_rooms r on r.id=g.room_id
 where auth.uid() is not null and a.organization_id=p_org and a.checked_out_at is null and a.checked_in_at>now()-interval '12 hours'
  and exists(select 1 from private.kids_guardians kg join public.people gp on gp.id=kg.person_id where kg.profile_id=a.profile_id and kg.status='approved' and gp.auth_user_id=auth.uid())
$$;
revoke all on function private.member_kids_present(uuid) from public,anon,authenticated;
create or replace function public.member_kids_present(p_org uuid) returns jsonb
language sql security definer set search_path to '' as $$ select private.member_kids_present(p_org) $$;
revoke all on function public.member_kids_present(uuid) from public,anon;
grant execute on function public.member_kids_present(uuid) to authenticated;
