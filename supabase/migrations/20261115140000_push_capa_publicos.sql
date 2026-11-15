-- Push: imagem de capa (do banco de imagens de Comunicação) e públicos salvos (ex.: "Pastores", "Líderes de jovens").
-- A capa vai no link da campanha ({screen, id?, image}); só imagens prontas do mesmo ministério são aceitas,
-- e a imagem fica pública enquanto a campanha estiver agendada, enviando ou enviada.

create or replace function private.push_link_check(p jsonb) returns void language plpgsql immutable set search_path='' as $$
begin
 if jsonb_typeof(p) is distinct from 'object' or p-array['screen','id','image']<>'{}'::jsonb
  or p->>'screen' not in('inbox','agenda','event','notice','media','live','giving','services')
  or (p ? 'id' and coalesce(p->>'id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or (p ? 'image' and coalesce(p->>'image','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or (p->>'screen' in('event','notice','media','live') and not p ? 'id') then raise exception 'invalid_push_link' using errcode='22023';end if;
end $$;
revoke all on function private.push_link_check(jsonb) from public,anon,authenticated,service_role;

create or replace function private.push_campaign_image_check() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.link ? 'image' and not exists(select 1 from private.publishing_images i where i.id=(new.link->>'image')::uuid and i.organization_id=new.organization_id and i.ready and i.archived_at is null) then
  raise exception 'invalid_push_image' using errcode='22023';end if;
 return new;
end $$;
revoke all on function private.push_campaign_image_check() from public,anon,authenticated;
drop trigger if exists push_campaign_image_check on private.push_campaigns;
create trigger push_campaign_image_check before insert or update of link on private.push_campaigns for each row execute function private.push_campaign_image_check();

create or replace function private.publishing_image_file(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare img private.publishing_images;used boolean;
begin
 select * into img from private.publishing_images where id=p_id and ready;
 if not found then return null;end if;
 used:=exists(select 1 from private.publishing_items p where p.organization_id=img.organization_id and p.status='published'
  and (strpos(p.body,'img:'||img.id::text)>0 or strpos(p.poster,'/api/publishing-images/'||img.id::text)>0))
  or exists(select 1 from private.push_campaigns c where c.organization_id=img.organization_id and c.link->>'image'=img.id::text and c.status in('scheduled','sending','sent'));
 if not used and (auth.uid() is null or not private.publisher_unit(img.organization_id,img.unit_id,'')) then return null;end if;
 if not used and img.archived_at is not null then return null;end if;
 return jsonb_build_object('path',img.path,'mime',img.mime,'public',used);
end $$;
revoke all on function private.publishing_image_file(uuid) from public,anon,authenticated,service_role;

-- Públicos salvos: um nome e o mesmo filtro de público das campanhas, reutilizável no painel e no Vinha Equipe.
create table if not exists private.push_segments(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 name text not null check(length(btrim(name)) between 2 and 60),
 audience jsonb not null check(jsonb_typeof(audience)='object' and octet_length(audience::text)<=6000),
 created_by uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists push_segments_name on private.push_segments(organization_id,lower(name));
alter table private.push_segments enable row level security;
revoke all on private.push_segments from public,anon,authenticated;

create or replace function private.push_segments(p_org uuid, p_unit uuid, p_action text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare sid uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.organization_units where id=p_unit and organization_id=p_org) or not private.push_unit(p_org,p_unit) then
  raise exception 'push_denied' using errcode='42501';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid_push_segment' using errcode='22023';end if;
 if p_action='list' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'audience',s.audience) order by lower(s.name)) from private.push_segments s where s.organization_id=p_org),'[]'::jsonb));
 elsif p_action='save' then
  if length(btrim(coalesce(p_data->>'name',''))) not between 2 and 60 or jsonb_typeof(p_data->'audience')<>'object' or p_data->'audience'='{}'::jsonb
   or (p_data->'audience')-array['roles','cells','groups','ageMin','ageMax','gender','journey','tags','baptized','event','birthdayToday','people']<>'{}'::jsonb
   or (select count(*) from private.push_segments where organization_id=p_org)>=100 then raise exception 'invalid_push_segment' using errcode='22023';end if;
  sid:=nullif(p_data->>'id','')::uuid;
  if sid is null then
   insert into private.push_segments(organization_id,name,audience,created_by) values(p_org,btrim(p_data->>'name'),p_data->'audience',auth.uid())
    on conflict(organization_id,lower(name)) do update set audience=excluded.audience,updated_at=clock_timestamp() returning id into sid;
  else
   update private.push_segments set name=btrim(p_data->>'name'),audience=p_data->'audience',updated_at=clock_timestamp() where id=sid and organization_id=p_org returning id into sid;
   if sid is null then raise exception 'invalid_push_segment' using errcode='22023';end if;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'push.segment_saved','push_segment',sid::text,jsonb_build_object('name',btrim(p_data->>'name')));
  return jsonb_build_object('ok',true,'id',sid);
 elsif p_action='delete' then
  delete from private.push_segments where id=nullif(p_data->>'id','')::uuid and organization_id=p_org;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'invalid_push_segment' using errcode='22023';
end $function$;
revoke all on function private.push_segments(uuid,uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.push_segments(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.push_segments(p_org,p_unit,p_action,p_data) $$;
revoke all on function public.push_segments(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.push_segments(uuid,uuid,text,jsonb) to authenticated;
