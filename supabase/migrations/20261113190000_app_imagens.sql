-- App do membro · imagens: o feed traz o tipo verdadeiro (aviso, banner, arquivo) e a capa da publicação da Comunicação;
-- a agenda e os tickets trazem o banner do evento. Respeita a janela de exibição da publicação.

create or replace function member_app_api.feed(p_org uuid, p_unit uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
begin
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 -- app_feed_images
 return jsonb_build_object('unitId',p_unit,'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from(
  select m.id,case when i.kind in('banner','file') then i.kind else m.kind end as kind,m.title,m.body,m.url,m.created_at,coalesce(i.poster,'') as image,
   coalesce(i.share_allowed,true) as share
  from private.member_publications m left join private.publishing_items i on i.id=m.publishing_id and i.organization_id=m.organization_id
  where m.organization_id=p_org and m.unit_id=p_unit and m.published
   and (i.id is null or ((i.starts_at is null or i.starts_at<=now()) and (i.ends_at is null or i.ends_at>now())))
  order by m.created_at desc limit 100)x),'[]'));
end $function$;

do $$
declare d text; n int;
begin
 d:=pg_get_functiondef('member_app_api.agenda(uuid,uuid,boolean)'::regprocedure);
 if position('e.cover_url as cover' in d)=0 then
  n:=(length(d)-length(replace(d,'''/eventos/e-''||e.id::text as public_path,','')))/length('''/eventos/e-''||e.id::text as public_path,');
  if n<>1 then raise exception 'agenda: trecho esperado não encontrado (%)',n; end if;
  execute replace(d,'''/eventos/e-''||e.id::text as public_path,','''/eventos/e-''||e.id::text as public_path,e.cover_url as cover,');
 end if;
 d:=pg_get_functiondef('private.member_agenda_self'::regproc);
 if position('evt.cover_url as cover' in d)=0 then
  n:=(length(d)-length(replace(d,'evt.status as event_status,','')))/length('evt.status as event_status,');
  if n<>1 then raise exception 'member_agenda_self: trecho esperado não encontrado (%)',n; end if;
  execute replace(d,'evt.status as event_status,','evt.status as event_status,evt.cover_url as cover,');
 end if;
end $$;
