-- Central da Vinha › Aplicativos: liberação e personalização do app de cada ministério que contrata o aplicativo.
-- Um código único para todos; cada ministério tem um perfil (nome no celular, tema, ícone, identificadores de loja).
-- A Central define o tema (claro/escuro) junto com o ministério. Atualizações chegam a todos os apps pelo canal de
-- cada perfil, preservando a personalização (o app lê nome, cores, logo e tema da Vinha).
begin;
set local lock_timeout='5s';

create table if not exists private.ministry_apps(
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 profile text not null unique check(profile ~ '^[a-z][a-z0-9]{1,23}$'),
 display_name text not null check(length(btrim(display_name)) between 2 and 30),
 status text not null default 'contracted' check(status in('contracted','configuring','testing','store_review','published','paused')),
 android_application_id text check(android_application_id is null or android_application_id ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
 ios_bundle_id text check(ios_bundle_id is null or ios_bundle_id ~ '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$'),
 notes text not null default '' check(length(notes)<=2000),
 last_build_at timestamptz,
 last_update_at timestamptz,
 version integer not null default 1,
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default clock_timestamp()
);
create index if not exists ministry_apps_updated_by_idx on private.ministry_apps(updated_by);
alter table private.ministry_apps enable row level security;
revoke all on private.ministry_apps from public,anon,authenticated;

-- Perfil sugerido: letras do nome (sem acento), até 20, e número se já existir.
create or replace function private.ministry_app_profile(p_name text) returns text
language plpgsql stable security definer set search_path to '' as $$
declare base text; candidate text; n int:=1;
begin
 base:=left(regexp_replace(lower(translate(coalesce(p_name,''),'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ','aaaaaeeeeiiiiooooouuuucaaaaaeeeeiiiiooooouuuuc')),'[^a-z0-9]','','g'),20);
 if base !~ '^[a-z]' then base:='app'||base; end if;
 if length(base)<2 then base:='app'; end if;
 candidate:=base;
 while exists(select 1 from private.ministry_apps where profile=candidate) loop n:=n+1; candidate:=left(base,20)||n; end loop;
 return candidate;
end $$;
revoke all on function private.ministry_app_profile(text) from public,anon,authenticated;

create or replace function private.ministry_app_json(o public.organizations, a private.ministry_apps, contracted boolean) returns jsonb
language sql stable security definer set search_path to '' as $$
 select jsonb_build_object('organizationId',o.id,'ministry',o.name,'ministrySlug',o.slug,'registrationCode',o.registration_code,
  'appName',coalesce(o.app_name,o.name),'primaryColor',coalesce(o.primary_color,'#285c45'),'accentColor',coalesce(o.accent_color,'#d8b769'),
  'theme',coalesce(o.app_theme,'dark'),'contracted',contracted,'configured',a.organization_id is not null,
  'profile',a.profile,'displayName',coalesce(a.display_name,left(coalesce(o.app_name,o.name),30)),'status',coalesce(a.status,'contracted'),
  'androidApplicationId',a.android_application_id,'iosBundleId',a.ios_bundle_id,'notes',coalesce(a.notes,''),
  'lastBuildAt',a.last_build_at,'lastUpdateAt',a.last_update_at,'version',coalesce(a.version,0),'updatedAt',a.updated_at,
  'pushReady',exists(select 1 from private.member_push_apps p where p.organization_id=o.id and p.enabled))
$$;
revoke all on function private.ministry_app_json(public.organizations,private.ministry_apps,boolean) from public,anon,authenticated;

-- Ações: list (operador), save (administração), manifest (operador ou servidor de build).
create or replace function public.platform_apps(p_action text, p_org uuid default null, p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path to '' as $$
declare a private.ministry_apps; o public.organizations; v int; prof text; nm text; st text; th text; aid text; ios text;
begin
 if p_action='manifest' then
  -- Lista para gerar e atualizar os apps: perfis em configuração, teste, loja ou publicados.
  if coalesce(auth.role(),'')<>'service_role' and not (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[])) then
   raise exception 'platform_operator_required' using errcode='42501';
  end if;
  return jsonb_build_object('apps',coalesce((select jsonb_agg(jsonb_build_object('profile',x.profile,'name',x.display_name,'ministryId',x.organization_id,'ministrySlug',g.slug,
    'status',x.status,'theme',coalesce(g.app_theme,'dark'),'primaryColor',coalesce(g.primary_color,'#285c45'),
    'androidApplicationId',x.android_application_id,'iosBundleId',x.ios_bundle_id) order by x.profile)
   from private.ministry_apps x join public.organizations g on g.id=x.organization_id
   where x.status in('configuring','testing','store_review','published') and g.status in('active','trial')),'[]'::jsonb));
 end if;
 if not private.has_aal2() or not private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]) then
  raise exception 'platform_operator_required' using errcode='42501';
 end if;
 if p_action='list' then
  return jsonb_build_object('apps',coalesce((select jsonb_agg(private.ministry_app_json(g,x,coalesce(s.app_addon,false)) order by (x.organization_id is null), g.name)
   from public.organizations g
   left join private.ministry_apps x on x.organization_id=g.id
   left join lateral (select bool_or(ss.app_addon) app_addon from public.saas_subscriptions ss where ss.organization_id=g.id) s on true
   where x.organization_id is not null or coalesce(s.app_addon,false)),'[]'::jsonb),
   'canEdit',private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
 end if;
 if p_action<>'save' then raise exception 'invalid_platform_apps' using errcode='22023'; end if;
 if not private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]) then raise exception 'platform_operator_required' using errcode='42501'; end if;
 select * into o from public.organizations where id=p_org for update;
 if not found then raise exception 'organization_not_found' using errcode='P0002'; end if;
 if jsonb_typeof(p_data)<>'object' or p_data - array['version','displayName','status','theme','androidApplicationId','iosBundleId','notes','profile','built','updated'] <> '{}'::jsonb then
  raise exception 'invalid_platform_apps' using errcode='22023';
 end if;
 select * into a from private.ministry_apps where organization_id=p_org for update;
 v:=coalesce((p_data->>'version')::int,0);
 if coalesce(a.version,0)<>v then raise exception 'platform_apps_conflict' using errcode='40001'; end if;
 nm:=btrim(coalesce(p_data->>'displayName',a.display_name,left(coalesce(o.app_name,o.name),30)));
 st:=coalesce(p_data->>'status',a.status,'configuring');
 th:=coalesce(p_data->>'theme',o.app_theme,'dark');
 aid:=nullif(btrim(coalesce(p_data->>'androidApplicationId',a.android_application_id,'')),'');
 ios:=nullif(btrim(coalesce(p_data->>'iosBundleId',a.ios_bundle_id,'')),'');
 if th not in('light','dark') then raise exception 'invalid_platform_apps' using errcode='22023'; end if;
 if st in('store_review','published') and aid is null and ios is null then raise exception 'platform_apps_store_ids' using errcode='22023'; end if;
 prof:=coalesce(a.profile,nullif(p_data->>'profile',''),private.ministry_app_profile(coalesce(o.app_name,o.name)));
 if a.organization_id is null then
  insert into private.ministry_apps(organization_id,profile,display_name,status,android_application_id,ios_bundle_id,notes,updated_by)
   values(p_org,prof,nm,st,aid,ios,coalesce(p_data->>'notes',''),auth.uid()) returning * into a;
 else
  update private.ministry_apps set display_name=nm,status=st,android_application_id=aid,ios_bundle_id=ios,notes=coalesce(p_data->>'notes',notes),
   last_build_at=case when (p_data->>'built')::boolean then clock_timestamp() else last_build_at end,
   last_update_at=case when (p_data->>'updated')::boolean then clock_timestamp() else last_update_at end,
   version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where organization_id=p_org returning * into a;
 end if;
 -- O tema é escolhido com a equipe da Vinha e vale para todos os membros no app.
 if o.app_theme is distinct from th then update public.organizations set app_theme=th,updated_at=clock_timestamp() where id=p_org returning * into o; end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_org,auth.uid(),'platform.app_saved','ministry_app',p_org::text,jsonb_build_object('status',a.status,'theme',th,'profile',a.profile));
 return jsonb_build_object('ok',true,'app',private.ministry_app_json(o,a,true));
end $$;
revoke all on function public.platform_apps(text,uuid,jsonb) from public,anon;
grant execute on function public.platform_apps(text,uuid,jsonb) to authenticated,service_role;

-- O app do MPR já existe (perfil "mpr"): registra como em teste para não gerar outro perfil.
insert into private.ministry_apps(organization_id,profile,display_name,status)
select id,'mpr','MPR-Igreja','testing' from public.organizations where id='c84066a5-6c7d-4a8f-ba51-6185c9a1f602'
on conflict do nothing;
commit;
