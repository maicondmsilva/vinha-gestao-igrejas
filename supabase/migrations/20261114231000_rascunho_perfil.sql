-- Rascunho do perfil no app: fica na plataforma, só a própria conta lê e grava. Não entra na fila da secretaria;
-- vira pedido só quando a pessoa toca em Enviar (member_self_service submit), e aí o rascunho é apagado.
-- Rascunhos parados há mais de 30 dias são descartados.

create table if not exists private.member_profile_drafts(
 user_id uuid not null references auth.users(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 data jsonb not null check(jsonb_typeof(data)='object' and length(data::text)<=4096),
 updated_at timestamptz not null default now(),
 primary key(user_id,organization_id)
);
alter table private.member_profile_drafts enable row level security;
revoke all on private.member_profile_drafts from public,anon,authenticated;

create or replace function private.member_profile_draft(p_org uuid, p_action text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare uid uuid=auth.uid(); d private.member_profile_drafts; clean jsonb;
begin
 if uid is null then raise exception 'member_login_required' using errcode='42501';end if;
 if not exists(select 1 from public.organizations where id=p_org and status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 delete from private.member_profile_drafts where user_id=uid and organization_id=p_org and updated_at<now()-interval '30 days';
 if p_action='get' then
  select * into d from private.member_profile_drafts where user_id=uid and organization_id=p_org;
  return jsonb_build_object('data',coalesce(d.data,'{}'::jsonb),'updatedAt',d.updated_at);
 elsif p_action='clear' then
  delete from private.member_profile_drafts where user_id=uid and organization_id=p_org;
  return jsonb_build_object('ok',true);
 elsif p_action='save' then
  if p_data is null or jsonb_typeof(p_data)<>'object' or length(p_data::text)>4096
   or exists(select 1 from jsonb_each(p_data) e where jsonb_typeof(e.value)<>'string' or length(e.key)>40 or length(e.value#>>'{}')>500) then
   raise exception 'invalid_member_draft' using errcode='22023';end if;
  select coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb) into clean from jsonb_each(p_data) e where btrim(e.value#>>'{}')<>'';
  if clean='{}'::jsonb then delete from private.member_profile_drafts where user_id=uid and organization_id=p_org;
  else insert into private.member_profile_drafts(user_id,organization_id,data) values(uid,p_org,clean)
   on conflict(user_id,organization_id) do update set data=excluded.data,updated_at=clock_timestamp();end if;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'invalid_member_draft' using errcode='22023';
end $function$;
revoke all on function private.member_profile_draft(uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.member_profile_draft(p_org uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.member_profile_draft(p_org,p_action,p_data) $$;
revoke all on function public.member_profile_draft(uuid,text,jsonb) from public,anon;
grant execute on function public.member_profile_draft(uuid,text,jsonb) to authenticated;

-- Enviou para a igreja: o rascunho deixa de existir.
create or replace function private.member_profile_draft_sent() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
 delete from private.member_profile_drafts where user_id=new.user_id and organization_id=new.organization_id;
 return new;
end $$;
revoke all on function private.member_profile_draft_sent() from public,anon,authenticated;
drop trigger if exists member_profile_draft_sent on private.member_profile_requests;
create trigger member_profile_draft_sent after insert on private.member_profile_requests for each row execute function private.member_profile_draft_sent();
