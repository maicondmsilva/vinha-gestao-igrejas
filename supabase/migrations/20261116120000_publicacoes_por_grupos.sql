-- Comunicação · aviso, banner ou arquivo só para pessoas de Grupos escolhidos (Configurações › Grupos).
-- Sem grupo = todos da igreja (como hoje). Com grupo = só quem entrou no app e está em algum dos grupos.

alter table private.publishing_items add column if not exists people_groups uuid[] not null default '{}';

create or replace function private.publishing_audience(p_org uuid,p_item uuid,p_groups uuid[]) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare i private.publishing_items; g uuid[];
begin
 if auth.uid() is null then raise exception 'publishing_denied' using errcode='42501';end if;
 select * into i from private.publishing_items where id=p_item and organization_id=p_org for update;
 if not found then raise exception 'publishing_changed' using errcode='40001';end if;
 if i.kind not in('notice','banner','file') then raise exception 'invalid_publishing' using errcode='22023';end if;
 if exists(select 1 from unnest(i.targets) u where not private.publisher_unit(p_org,u,i.kind)) then raise exception 'publishing_denied' using errcode='42501';end if;
 g:=array(select distinct x from unnest(coalesce(p_groups,'{}')) x where x is not null order by 1);
 if cardinality(g)>20 or exists(select 1 from unnest(g) x where not exists(select 1 from private.people_groups pg where pg.id=x and pg.organization_id=p_org)) then raise exception 'invalid_publishing' using errcode='22023';end if;
 update private.publishing_items set people_groups=g where id=i.id;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'publishing.audience','publishing_item',i.id::text,jsonb_build_object('groups',to_jsonb(g)));
 return jsonb_build_object('ok',true,'groups',to_jsonb(g));
end $$;
revoke all on function private.publishing_audience(uuid,uuid,uuid[]) from public,anon,authenticated;

create or replace function public.publishing_audience(p_org uuid,p_item uuid,p_groups uuid[]) returns jsonb
language sql security definer set search_path to '' as $$select private.publishing_audience(p_org,p_item,p_groups)$$;
revoke all on function public.publishing_audience(uuid,uuid,uuid[]) from public,anon;
grant execute on function public.publishing_audience(uuid,uuid,uuid[]) to authenticated;

-- Pessoa logada está em algum dos grupos?
create or replace function private.viewer_in_groups(p_org uuid,p_groups uuid[]) returns boolean
language sql stable security definer set search_path to '' as $$
 select cardinality(p_groups)=0 or exists(select 1 from private.people_group_members gm join public.people p on p.id=gm.person_id
  where gm.group_id=any(p_groups) and gm.organization_id=p_org and p.organization_id=p_org and p.auth_user_id=auth.uid() and auth.uid() is not null)
$$;
revoke all on function private.viewer_in_groups(uuid,uuid[]) from public,anon,authenticated;

do $$ declare d text; begin
 d:=pg_get_functiondef('member_app_api.feed(uuid,uuid)'::regprocedure);
 if position('viewer_in_groups' in d)=0 then
  if position('   and (i.id is null or ((i.starts_at is null or i.starts_at<=now()) and (i.ends_at is null or i.ends_at>now())))' in d)=0 then raise exception 'feed: trecho não encontrado';end if;
  d:=replace(d,'   and (i.id is null or ((i.starts_at is null or i.starts_at<=now()) and (i.ends_at is null or i.ends_at>now())))',
   '   and (i.id is null or ((i.starts_at is null or i.starts_at<=now()) and (i.ends_at is null or i.ends_at>now())))
   and (i.id is null or private.viewer_in_groups(p_org,i.people_groups))');
  execute d;
 end if;
end $$;
