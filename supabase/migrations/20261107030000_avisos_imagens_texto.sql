begin;
set local lock_timeout='5s';
-- Etapa 4 · PR 2: banco de imagens do ministério para avisos e banners.
-- Arquivos ficam em bucket privado; a leitura pública passa pela API e só libera imagens usadas
-- em publicações publicadas do mesmo ministério (ou para quem publica naquela igreja).

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('vinha-publishing-images','vinha-publishing-images',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;

create table private.publishing_images(
 id uuid primary key,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 path text not null unique,
 mime text not null check(mime in('image/jpeg','image/png','image/webp')),
 bytes integer not null check(bytes between 1 and 5242880),
 name text not null check(length(btrim(name)) between 1 and 120),
 alt text not null default '' check(length(alt)<=240),
 ready boolean not null default false,
 archived_at timestamptz,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default clock_timestamp()
);
create index publishing_images_list on private.publishing_images(organization_id,unit_id,created_at desc) where ready and archived_at is null;
create index publishing_images_unit on private.publishing_images(unit_id);
create index publishing_images_created_by on private.publishing_images(created_by);
alter table private.publishing_images enable row level security;
revoke all on private.publishing_images from public,anon,authenticated,service_role;

create function private.publishing_image(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare img private.publishing_images;page_no integer;q text;
begin
 perform private.community_identity(p_org,p_unit,false);
 if not private.publisher_unit(p_org,p_unit,'') or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'publishing_denied' using errcode='42501';end if;
 if p_action='prepare' then
  if p_id is null or p_data-array['mime','bytes','name']<>'{}'::jsonb or p_data->>'mime' not in('image/jpeg','image/png','image/webp')
   or jsonb_typeof(p_data->'bytes')<>'number' or (p_data->>'bytes')::numeric not between 1 and 5242880 or length(btrim(coalesce(p_data->>'name',''))) not between 1 and 120 then raise exception 'invalid_publishing_image' using errcode='22023';end if;
  perform 1 from public.organizations where id=p_org for no key update;
  if (select count(*) from private.publishing_images where organization_id=p_org and archived_at is null)>=5000 then raise exception 'publishing_image_limit' using errcode='22023';end if;
  insert into private.publishing_images(id,organization_id,unit_id,path,mime,bytes,name,created_by)
   values(p_id,p_org,p_unit,p_org::text||'/'||p_unit::text||'/'||p_id::text,p_data->>'mime',(p_data->>'bytes')::integer,btrim(p_data->>'name'),auth.uid());
  return jsonb_build_object('ok',true,'path',p_org::text||'/'||p_unit::text||'/'||p_id::text);
 elsif p_action='finish' then
  update private.publishing_images set ready=true where id=p_id and organization_id=p_org and unit_id=p_unit and created_by=auth.uid() and not ready returning * into img;
  if not found then raise exception 'publishing_denied' using errcode='42501';end if;
  return jsonb_build_object('ok',true,'id',img.id);
 elsif p_action in('update','archive') then
  select * into img from private.publishing_images where id=p_id and organization_id=p_org and ready and archived_at is null for update;
  if not found or not private.publisher_unit(p_org,img.unit_id,'') then raise exception 'publishing_denied' using errcode='42501';end if;
  if p_action='update' then
   if p_data-array['name','alt']<>'{}'::jsonb or length(btrim(coalesce(p_data->>'name',img.name))) not between 1 and 120 or length(coalesce(p_data->>'alt',img.alt))>240 then raise exception 'invalid_publishing_image' using errcode='22023';end if;
   update private.publishing_images set name=btrim(coalesce(p_data->>'name',name)),alt=btrim(coalesce(p_data->>'alt',alt)) where id=img.id;
  else
   -- Arquivar tira do banco de imagens; avisos já publicados continuam mostrando a imagem.
   update private.publishing_images set archived_at=clock_timestamp() where id=img.id;
  end if;
 elsif p_action<>'list' then raise exception 'invalid_publishing_image' using errcode='22023';
 end if;
 if p_data-array['page','search']<>'{}'::jsonb and p_action='list' then raise exception 'invalid_publishing_image' using errcode='22023';end if;
 page_no:=coalesce(nullif(p_data->>'page','')::integer,1);q:=btrim(coalesce(p_data->>'search',''));
 if page_no not between 1 and 200 or length(q)>80 then raise exception 'invalid_publishing_image' using errcode='22023';end if;
 return jsonb_build_object('ok',true,'page',page_no,
  'items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'alt',x.alt,'mime',x.mime,'bytes',x.bytes,'unit',x.unit_id,'createdAt',x.created_at) order by x.created_at desc) from(
   select * from private.publishing_images i where i.organization_id=p_org and i.ready and i.archived_at is null
    and (i.unit_id=p_unit or private.publisher_unit(p_org,i.unit_id,''))
    and (q='' or i.name ilike '%'||replace(replace(replace(q,'\','\\'),'%','\%'),'_','\_')||'%' or i.alt ilike '%'||replace(replace(replace(q,'\','\\'),'%','\%'),'_','\_')||'%')
   order by i.created_at desc offset (page_no-1)*30 limit 31)x),'[]'));
end $$;
revoke all on function private.publishing_image(uuid,uuid,text,uuid,jsonb) from public,anon,authenticated,service_role;
create function public.publishing_image(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_data jsonb default '{}') returns jsonb language sql security definer set search_path='' as $$select private.publishing_image(p_org,p_unit,p_action,p_id,p_data)$$;
revoke all on function public.publishing_image(uuid,uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.publishing_image(uuid,uuid,text,uuid,jsonb) to authenticated;

-- Leitura do arquivo: imagem usada em publicação publicada do mesmo ministério (texto `img:<id>` ou capa),
-- ou quem publica naquela igreja (prévia no editor).
create function private.publishing_image_file(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare img private.publishing_images;used boolean;
begin
 select * into img from private.publishing_images where id=p_id and ready;
 if not found then return null;end if;
 used:=exists(select 1 from private.publishing_items p where p.organization_id=img.organization_id and p.status='published'
  and (strpos(p.body,'img:'||img.id::text)>0 or strpos(p.poster,'/api/publishing-images/'||img.id::text)>0));
 if not used and (auth.uid() is null or not private.publisher_unit(img.organization_id,img.unit_id,'')) then return null;end if;
 if not used and img.archived_at is not null then return null;end if;
 return jsonb_build_object('path',img.path,'mime',img.mime,'public',used);
end $$;
revoke all on function private.publishing_image_file(uuid) from public,anon,authenticated,service_role;
create function public.publishing_image_file(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$select private.publishing_image_file(p_id)$$;
revoke all on function public.publishing_image_file(uuid) from public;
grant execute on function public.publishing_image_file(uuid) to anon,authenticated;

notify pgrst,'reload schema';
commit;
