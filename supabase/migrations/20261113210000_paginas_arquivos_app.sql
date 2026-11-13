-- Comunicação · "Página da igreja" (história, células, ministérios…) e arquivos com categoria no app do membro.

-- Novo tipo de publicação: página institucional, com texto formatado maior (até 12.000 caracteres) e imagem de capa.
do $$ begin
 alter table private.publishing_items drop constraint if exists publishing_items_kind_check;
 alter table private.publishing_items add constraint publishing_items_kind_check check (kind in ('notice','video','live','channel','category','banner','file','page'));
 alter table private.publishing_items drop constraint if exists publishing_items_body_check;
 alter table private.publishing_items add constraint publishing_items_body_check check (length(body)<=case when kind='page' then 12000 else 4000 end);
end $$;

do $$
declare d text; n int;
begin
 d:=pg_get_functiondef('private.publishing_admin'::regproc);
 if position('''file'',''page'')' in d)=0 then
  n:=(length(d)-length(replace(d,'kind_name not in(''notice'',''video'',''live'',''channel'',''category'',''banner'',''file'')','')))/length('kind_name not in(''notice'',''video'',''live'',''channel'',''category'',''banner'',''file'')');
  if n<>2 then raise exception 'publishing_admin: lista de tipos não encontrada (%)',n; end if;
  d:=replace(d,'kind_name not in(''notice'',''video'',''live'',''channel'',''category'',''banner'',''file'')','kind_name not in(''notice'',''video'',''live'',''channel'',''category'',''banner'',''file'',''page'')');
  n:=(length(d)-length(replace(d,'(source_url<>'''' or kind_name<>''notice'')','')))/length('(source_url<>'''' or kind_name<>''notice'')');
  if n<>1 then raise exception 'publishing_admin: regra do link não encontrada (%)',n; end if;
  d:=replace(d,'(source_url<>'''' or kind_name<>''notice'')','(source_url<>'''' or kind_name not in(''notice'',''page''))');
  n:=(length(d)-length(replace(d,'length(p_data->>''body'')>4000','')))/length('length(p_data->>''body'')>4000');
  if n<>1 then raise exception 'publishing_admin: limite do texto não encontrado (%)',n; end if;
  d:=replace(d,'length(p_data->>''body'')>4000','length(p_data->>''body'')>(case when kind_name=''page'' then 12000 else 4000 end)');
  execute d;
 end if;
end $$;

-- Feed do app: arquivos e avisos trazem também o nome da categoria.
create or replace function member_app_api.feed(p_org uuid, p_unit uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 -- app_feed_images app_feed_category
 return jsonb_build_object('unitId',p_unit,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(
  select m.id,case when i.kind in('banner','file') then i.kind else m.kind end as kind,m.title,m.body,m.url,m.created_at,coalesce(i.poster,'') as image,
   coalesce(i.share_allowed,true) as share,coalesce(c.title,'') as category
  from private.member_publications m left join private.publishing_items i on i.id=m.publishing_id and i.organization_id=m.organization_id
   left join private.publishing_items c on c.id=i.category_id and c.organization_id=m.organization_id
  where m.organization_id=p_org and m.unit_id=p_unit and m.published
   and (i.id is null or ((i.starts_at is null or i.starts_at<=now()) and (i.ends_at is null or i.ends_at>now())))
  order by m.created_at desc limit 100)x),'[]'));
end $function$;

-- Páginas da igreja publicadas para a igreja local (públicas, como o feed).
create or replace function member_app_api.pages(p_org uuid, p_unit uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 if not private.ministry_module_public(p_org,p_unit,'communication') then return jsonb_build_object('items','[]'::jsonb);end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'title',i.title,'body',i.body,'image',coalesce(i.poster,''),'updatedAt',i.updated_at) order by i.title)
  from private.publishing_items i where i.organization_id=p_org and p_unit=any(i.targets) and i.kind='page' and i.status='published'),'[]'::jsonb));
end $function$;
create or replace function public.member_church_pages(p_org uuid, p_unit uuid) returns jsonb
language sql stable security invoker set search_path to '' as $$ select member_app_api.pages(p_org,p_unit) $$;
revoke all on function member_app_api.pages(uuid,uuid) from public;
revoke all on function public.member_church_pages(uuid,uuid) from public;
grant execute on function member_app_api.pages(uuid,uuid) to anon,authenticated;
grant execute on function public.member_church_pages(uuid,uuid) to anon,authenticated;
