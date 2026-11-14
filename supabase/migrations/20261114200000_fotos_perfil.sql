-- Fotos de perfil: o membro envia a própria foto pelo app (inclusive antes da aprovação do cadastro) e a foto
-- das crianças que ele pode editar no Kids. Arquivos privados no bucket member-photos:
--   <organização>/<conta>/profile.jpg     foto do membro
--   <organização>/<conta>/kids/<criança>.jpg  foto da criança (pessoa do Kids)
-- O cadastro de pessoas (people.photo_path) guarda o caminho; ao aprovar o vínculo, a foto da conta migra para o membro.

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('member-photos','member-photos',false,2097152,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=2097152,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

-- Cada conta mexe só na sua pasta.
drop policy if exists member_photo_own_read on storage.objects;
drop policy if exists member_photo_own_insert on storage.objects;
drop policy if exists member_photo_own_update on storage.objects;
drop policy if exists member_photo_own_delete on storage.objects;
create policy member_photo_own_read on storage.objects for select to authenticated using(bucket_id='member-photos' and (storage.foldername(name))[2]=auth.uid()::text);
create policy member_photo_own_insert on storage.objects for insert to authenticated with check(bucket_id='member-photos' and (storage.foldername(name))[2]=auth.uid()::text and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/(profile|kids/[0-9a-f-]{36})\.jpg$');
create policy member_photo_own_update on storage.objects for update to authenticated using(bucket_id='member-photos' and (storage.foldername(name))[2]=auth.uid()::text) with check(bucket_id='member-photos' and (storage.foldername(name))[2]=auth.uid()::text);
create policy member_photo_own_delete on storage.objects for delete to authenticated using(bucket_id='member-photos' and (storage.foldername(name))[2]=auth.uid()::text);

create table if not exists private.member_account_photos(
 user_id uuid not null references auth.users(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 path text not null check(length(path)<=200),
 updated_at timestamptz not null default now(),
 primary key(user_id,organization_id)
);
alter table private.member_account_photos enable row level security;
revoke all on private.member_account_photos from public,anon,authenticated;

-- Ação do membro: get (caminho da própria foto), set (depois do upload) e clear.
create or replace function private.member_photo(p_org uuid, p_action text, p_child uuid default null)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare uid uuid=auth.uid(); me uuid; path text; child_person uuid;
begin
 if uid is null then raise exception 'member_login_required' using errcode='42501';end if;
 if p_action not in('get','set','clear','child_set') then raise exception 'invalid_member_photo' using errcode='22023';end if;
 if not exists(select 1 from public.organizations where id=p_org and status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 select id into me from public.people where organization_id=p_org and auth_user_id=uid and status='active' order by created_at limit 1;
 if p_action='get' then
  return jsonb_build_object('path',coalesce((select photo_path from public.people where id=me),(select a.path from private.member_account_photos a where a.user_id=uid and a.organization_id=p_org),''));
 elsif p_action='clear' then
  delete from private.member_account_photos where user_id=uid and organization_id=p_org;
  update public.people set photo_path=null,updated_at=clock_timestamp() where id=me and photo_path like 'member-photos/'||p_org||'/'||uid||'/%';
  return jsonb_build_object('ok',true,'path','');
 elsif p_action='set' then
  path:=p_org||'/'||uid||'/profile.jpg';
  if not exists(select 1 from storage.objects where bucket_id='member-photos' and name=path) then raise exception 'member_photo_missing' using errcode='22023';end if;
  insert into private.member_account_photos(user_id,organization_id,path) values(uid,p_org,'member-photos/'||path)
   on conflict(user_id,organization_id) do update set path=excluded.path,updated_at=clock_timestamp();
  update public.people set photo_path='member-photos/'||path,updated_at=clock_timestamp() where id=me;
  return jsonb_build_object('ok',true,'path','member-photos/'||path);
 else
  -- Foto da criança: só quem é responsável aprovado com permissão de editar o cadastro dela.
  select k.person_id into child_person from private.kids_profiles k join private.kids_guardians g on g.profile_id=k.id and g.organization_id=k.organization_id
   where k.id=p_child and k.organization_id=p_org and g.person_id=me and g.status='approved' and g.can_edit and (g.valid_until is null or g.valid_until>now()) limit 1;
  if me is null or child_person is null then raise exception 'member_photo_denied' using errcode='42501';end if;
  path:=p_org||'/'||uid||'/kids/'||p_child||'.jpg';
  if not exists(select 1 from storage.objects where bucket_id='member-photos' and name=path) then raise exception 'member_photo_missing' using errcode='22023';end if;
  update public.people set photo_path='member-photos/'||path,updated_at=clock_timestamp() where id=child_person;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,uid,'kids.child_photo','kids_profile',p_child::text,'{}'::jsonb);
  return jsonb_build_object('ok',true,'path','member-photos/'||path);
 end if;
end $function$;
revoke all on function private.member_photo(uuid,text,uuid) from public,anon,authenticated;
create or replace function public.member_photo(p_org uuid, p_action text, p_child uuid default null) returns jsonb
language sql security definer set search_path to '' as $$ select private.member_photo(p_org,p_action,p_child) $$;
revoke all on function public.member_photo(uuid,text,uuid) from public,anon;
grant execute on function public.member_photo(uuid,text,uuid) to authenticated;

-- Quando o cadastro de membro é vinculado à conta (aprovação), a foto enviada pelo app migra para ele.
create or replace function private.people_photo_from_account() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
 if new.auth_user_id is not null and new.photo_path is null and (tg_op='INSERT' or old.auth_user_id is distinct from new.auth_user_id) then
  select a.path into new.photo_path from private.member_account_photos a where a.user_id=new.auth_user_id and a.organization_id=new.organization_id;
 end if;
 return new;
end $$;
revoke all on function private.people_photo_from_account() from public,anon,authenticated;
drop trigger if exists people_photo_from_account on public.people;
create trigger people_photo_from_account before insert or update of auth_user_id on public.people for each row execute function private.people_photo_from_account();

-- Kids no app: a lista de crianças do responsável traz o caminho da foto.
do $$
declare d text; a text; n int;
begin
 d:=pg_get_functiondef('private.member_family(uuid,uuid,text,uuid,integer,jsonb,integer)'::regprocedure);
 if position('p.photo_path,'''') photo' in d)=0 then
  a:='select k.id,p.full_name name,p.birth_date birth,k.version,';
  n:=(length(d)-length(replace(d,a,'')))/length(a);
  if n<>1 then raise exception 'member_family: lista de crianças não encontrada (%)',n;end if;
  execute replace(d,a,'select k.id,p.full_name name,p.birth_date birth,coalesce(p.photo_path,'''') photo,k.version,');
 end if;
end $$;
