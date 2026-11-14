-- Comunicação · séries de mensagens: um tipo novo de publicação ("série") que agrupa vídeos como episódios, em ordem definida no painel.
-- O vídeo entra na série pelo mesmo campo da categoria (category_id apontando para a série). A ordem fica em publishing_items.episode.

do $$ begin
 alter table private.publishing_items drop constraint if exists publishing_items_kind_check;
 alter table private.publishing_items add constraint publishing_items_kind_check check (kind in ('notice','video','live','channel','category','banner','file','page','series'));
end $$;
alter table private.publishing_items add column if not exists episode smallint;
do $$ begin
 alter table private.publishing_items drop constraint if exists publishing_items_episode_check;
 alter table private.publishing_items add constraint publishing_items_episode_check check (episode is null or episode between 1 and 999);
end $$;
create index if not exists publishing_items_series_idx on private.publishing_items(category_id,episode) where kind='video';

do $$
declare d text; n int; a text; b text;
begin
 d:=pg_get_functiondef('private.publishing_admin'::regproc);
 if position('publishing_series_kind' in d)=0 then
  -- 1. tipo novo nas duas listas de tipos aceitos
  a:='''banner'',''file'',''page'')';b:='''banner'',''file'',''page'',''series'')';
  n:=(length(d)-length(replace(d,a,'')))/length(a);if n<>2 then raise exception 'publishing_admin: listas de tipos (%)',n;end if;d:=replace(d,a,b);
  -- 2. série não tem link, como a categoria
  a:='if kind_name<>''category'' and (source_url<>''''';b:='if kind_name not in(''category'',''series'') and (source_url<>''''';
  n:=(length(d)-length(replace(d,a,'')))/length(a);if n<>1 then raise exception 'publishing_admin: regra do link (%)',n;end if;d:=replace(d,a,b);
  a:='or kind_name=''category'' and source_url<>''''';b:='or kind_name in(''category'',''series'') and source_url<>''''';
  n:=(length(d)-length(replace(d,a,'')))/length(a);if n<>1 then raise exception 'publishing_admin: link da categoria (%)',n;end if;d:=replace(d,a,b);
  -- 3. não arquiva/edita série com episódios publicados (mesma proteção da categoria)
  a:='kind_name in(''category'',''channel'') and exists';b:='kind_name in(''category'',''channel'',''series'') and exists';
  n:=(length(d)-length(replace(d,a,'')))/length(a);if n<>1 then raise exception 'publishing_admin: proteção de vínculos (%)',n;end if;d:=replace(d,a,b);
  -- 4. vídeo pode apontar para uma série publicada no lugar da categoria
  a:='where id=cat and organization_id=p_org and kind=''category'' and status=''published''';
  b:='where id=cat and organization_id=p_org and (kind=''category'' or kind=''series'' and kind_name=''video'') and status=''published''';
  n:=(length(d)-length(replace(d,a,'')))/length(a);if n<>1 then raise exception 'publishing_admin: vínculo da categoria (%)',n;end if;d:=replace(d,a,b);
  -- 5. a lista do painel traz as séries publicadas para o seletor do vídeo
  a:='''categories'',coalesce(';
  b:='''series'',coalesce((select jsonb_agg(jsonb_build_object(''id'',i.id,''title'',i.title,''targets'',array(select unnest(i.targets) intersect select unnest(eligible))) order by i.title) from private.publishing_items i where i.organization_id=p_org and i.kind=''series'' and i.status=''published'' and i.targets&&eligible),''[]''),/* publishing_series_kind */
    ''categories'',coalesce(';
  n:=(length(d)-length(replace(d,a,'')))/length(a);if n<>1 then raise exception 'publishing_admin: lista de categorias (%)',n;end if;d:=replace(d,a,b);
  execute d;
 end if;
end $$;

-- Episódios de uma série: listar (p_items nulo) ou gravar a ordem (lista completa dos vídeos da série).
create or replace function private.publishing_series_episodes(p_org uuid, p_unit uuid, p_series uuid, p_items uuid[])
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare s private.publishing_items; n integer;
begin
 if not private.publisher_unit(p_org,p_unit) then raise exception 'publishing_denied' using errcode='42501';end if;
 select * into s from private.publishing_items where id=p_series and organization_id=p_org and kind='series';
 if s.id is null or not p_unit=any(s.targets) then raise exception 'publishing_denied' using errcode='42501';end if;
 if p_items is not null then
  perform pg_advisory_xact_lock(hashtextextended('vinha-publishing:'||p_series::text,0));
  if cardinality(p_items)>500 or cardinality(p_items)<>(select count(distinct x) from unnest(p_items)x)
   or (select count(*) from private.publishing_items v where v.organization_id=p_org and v.kind='video' and v.category_id=p_series and v.status<>'archived')<>cardinality(p_items)
   or exists(select 1 from unnest(p_items)x where not exists(select 1 from private.publishing_items v where v.id=x and v.organization_id=p_org and v.kind='video' and v.category_id=p_series and v.status<>'archived'))
  then raise exception 'publishing_changed' using errcode='40001';end if;
  update private.publishing_items v set episode=o.n from unnest(p_items) with ordinality o(id,n) where v.id=o.id;
  get diagnostics n=row_count;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,auth.uid(),'publishing.series_order','publishing_item',p_series::text,jsonb_build_object('unit_id',p_unit,'episodes',n));
 end if;
 return jsonb_build_object('ok',true,'series',jsonb_build_object('id',s.id,'title',s.title,'status',s.status),'items',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'title',v.title,'status',v.status,'episode',v.episode,'poster',coalesce(v.poster,'')) order by v.episode nulls last,v.updated_at,v.id)
  from private.publishing_items v where v.organization_id=p_org and v.kind='video' and v.category_id=p_series and v.status<>'archived'),'[]'::jsonb));
end $function$;
revoke all on function private.publishing_series_episodes(uuid,uuid,uuid,uuid[]) from public,anon,authenticated;
create or replace function public.publishing_series_episodes(p_org uuid, p_unit uuid, p_series uuid, p_items uuid[] default null)
returns jsonb language sql security definer set search_path to '' as $$ select private.publishing_series_episodes(p_org,p_unit,p_series,p_items) $$;
revoke all on function public.publishing_series_episodes(uuid,uuid,uuid,uuid[]) from public,anon;
grant execute on function public.publishing_series_episodes(uuid,uuid,uuid,uuid[]) to authenticated;

-- Biblioteca do app: cada vídeo informa a série e o número do episódio.
create or replace function member_app_api.media(p_org uuid, p_unit uuid, p_kind text default 'video', p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
 if p_kind not in('video','live') or p_offset is null or p_offset not between 0 and 100000 then raise exception 'invalid_media' using errcode='22023';end if;
 if not private.ministry_module_public(p_org,p_unit,case when p_kind='live' then 'broadcasts' else 'communication' end) then return jsonb_build_object('items','[]'::jsonb,'available',false);end if;
 return jsonb_build_object('available',true,'items',coalesce((select jsonb_agg(to_jsonb(q)) from(
  select m.id,m.unit_id,m.kind,m.title,m.description,m.source,m.poster,m.live_state,m.starts_at,m.ends_at,m.download_allowed,m.version,
   case when s.id is not null then s.id end as series_id,coalesce(s.title,'') as series_title,case when s.id is not null then i.episode end as episode
  from private.ministry_media m left join private.publishing_items i on i.id=m.publishing_id and i.organization_id=m.organization_id
   left join private.publishing_items s on s.id=i.category_id and s.organization_id=m.organization_id and s.kind='series' and s.status='published' and p_unit=any(s.targets)
  where m.organization_id=p_org and m.unit_id=p_unit and m.kind=p_kind and m.status='published'
  order by case m.live_state when 'live' then 0 when 'scheduled' then 1 else 2 end,m.updated_at desc,m.id limit 20 offset p_offset)q),'[]'));
end $function$;

-- Séries publicadas para a igreja local, com os episódios publicados em ordem.
create or replace function member_app_api.series(p_org uuid, p_unit uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 if not private.ministry_module_public(p_org,p_unit,'communication') then return jsonb_build_object('items','[]'::jsonb);end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(x order by x->>'latest' desc) from(
  select jsonb_build_object('id',s.id,'title',s.title,'description',s.body,'poster',coalesce(s.poster,''),'latest',max(m.updated_at),
   'episodes',jsonb_agg(jsonb_build_object('id',m.id,'title',m.title,'description',m.description,'source',m.source,'poster',coalesce(m.poster,''),'episode',i.episode,'download_allowed',m.download_allowed,'version',m.version)
    order by i.episode nulls last,m.updated_at,m.id)) x
  from private.publishing_items s
   join private.publishing_items i on i.category_id=s.id and i.organization_id=p_org and i.kind='video'
   join private.ministry_media m on m.publishing_id=i.id and m.organization_id=p_org and m.unit_id=p_unit and m.kind='video' and m.status='published'
  where s.organization_id=p_org and s.kind='series' and s.status='published' and p_unit=any(s.targets)
  group by s.id,s.title,s.body,s.poster) q),'[]'::jsonb));
end $function$;
create or replace function public.member_series(p_org uuid, p_unit uuid) returns jsonb
language sql stable security invoker set search_path to '' as $$ select member_app_api.series(p_org,p_unit) $$;
revoke all on function member_app_api.series(uuid,uuid) from public;
revoke all on function public.member_series(uuid,uuid) from public;
grant execute on function member_app_api.series(uuid,uuid) to anon,authenticated;
grant execute on function public.member_series(uuid,uuid) to anon,authenticated;
