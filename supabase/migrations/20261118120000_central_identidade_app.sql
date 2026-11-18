-- Identidade do aplicativo passa a ser feita SOMENTE pela equipe da Vinha (Central › Aplicativos):
-- nome no app, cores, logo do ministério, tema, abertura (foto/vídeo) e ícone do celular.
-- O painel e o cadastro inicial do ministério deixam de alterar esses dados (travas no banco, não só na tela).
-- Logos de cada igreja (unidades) não aparecem no app e continuam com o ministério (relatórios e painel).
begin;
set local lock_timeout='5s';

-- Troca um trecho exato da definição atual de uma função (falha se o trecho não existir).
create function pg_temp.swap(p regprocedure, a text, b text) returns void language plpgsql as $f$
declare d text:=pg_get_functiondef(p);
begin
 if position(a in d)=0 then raise exception 'trecho não encontrado em %: %', p, left(a,90); end if;
 execute replace(d,a,b);
end $f$;

-- 1) Configurações do painel: sem nome do app, cores, logo do ministério e tema.
select pg_temp.swap('private.organization_settings_save(uuid,uuid,jsonb)',
 $$array['updatedAt','name','appName','seniorPastorName','legalName','taxId','primaryColor','accentColor','logo','appTheme']$$,
 $$array['updatedAt','name','seniorPastorName','legalName','taxId']$$);
select pg_temp.swap('private.organization_settings_save(uuid,uuid,jsonb)',
 $$if length(trim(coalesce(p_data->>'appName','')))<2 or length(trim(coalesce(p_data->>'seniorPastorName','')))<2 or coalesce(p_data->>'primaryColor','') !~ '^#[0-9A-Fa-f]{6}$' or coalesce(p_data->>'accentColor','') !~ '^#[0-9A-Fa-f]{6}$' then$$,
 $$if length(trim(coalesce(p_data->>'seniorPastorName','')))<2 then$$);
select pg_temp.swap('private.organization_settings_save(uuid,uuid,jsonb)',$$app_name=trim(p_data->>'appName'),$$,'');
select pg_temp.swap('private.organization_settings_save(uuid,uuid,jsonb)',$$primary_color=p_data->>'primaryColor',accent_color=p_data->>'accentColor',$$,'');

-- 2) Cadastro inicial: só nome do ministério e pastor titular; identidade do app fica com a Vinha.
select pg_temp.swap('public.save_organization_onboarding(uuid,jsonb)',
 $$ if p_data ? 'logo' then perform private.save_church_brand(p_organization_id,null,p_data->>'logo'); end if;$$,'');
select pg_temp.swap('public.save_organization_onboarding(uuid,jsonb)',$$ or length(trim(coalesce(p_data->>'appName','')))<2$$,'');
select pg_temp.swap('public.save_organization_onboarding(uuid,jsonb)',
 $$ or coalesce(p_data->>'primaryColor','') !~ '^#[0-9A-Fa-f]{6}$' or coalesce(p_data->>'accentColor','') !~ '^#[0-9A-Fa-f]{6}$'$$,'');
select pg_temp.swap('public.save_organization_onboarding(uuid,jsonb)',$$app_name=trim(p_data->>'appName'),$$,'');
select pg_temp.swap('public.save_organization_onboarding(uuid,jsonb)',$$,primary_color=p_data->>'primaryColor',accent_color=p_data->>'accentColor'$$,'');

-- 3) Logo do ministério (a do app) só pela Central; logos das igrejas seguem no painel.
select pg_temp.swap('private.save_church_brand(uuid,uuid,text)',
 $$ if not private.valid_church_logo(p_logo) then$$,
 $$ if p_unit is null then raise exception 'identity_managed_by_vinha' using errcode='42501'; end if;
 if not private.valid_church_logo(p_logo) then$$);

-- 4) Abertura do app só pela Central (a biblioteca de vídeos e as transmissões seguem no painel).
select pg_temp.swap('private.ministry_media_admin(uuid,uuid,text,uuid,integer,jsonb)',
 $$elsif p_action='opening' then$$,
 $$elsif p_action='opening' then
  raise exception 'opening_managed_by_vinha' using errcode='42501';$$);
select pg_temp.swap('private.ministry_media_admin(uuid,uuid,text,uuid,integer,jsonb)',
 $$'canOpening',private.has_organization_role(p_org,array['owner','admin']::public.membership_role[])$$,
 $$'canOpening',false$$);

-- 5) Ícone do app (tela do celular e loja), guardado nos arquivos públicos do app.
alter table private.ministry_apps add column if not exists icon_url text
 check(icon_url is null or icon_url ~ '^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/vinha-app-assets/[0-9a-f-]{36}/icon-[0-9a-f-]{36}\.png$');
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('vinha-app-assets','vinha-app-assets',true,52428800,array['image/png','image/jpeg','image/webp','video/mp4'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
-- Sem políticas: só o servidor da Vinha grava (link de envio assinado gerado após conferir o operador).

select pg_temp.swap('private.ministry_app_json(public.organizations,private.ministry_apps,boolean)',
 $$'pushReady',$$,$$'iconUrl',a.icon_url,'pushReady',$$);
select pg_temp.swap('public.platform_apps(text,uuid,jsonb)',
 $$'iosBundleId',x.ios_bundle_id) order by x.profile)$$,
 $$'iosBundleId',x.ios_bundle_id,'iconUrl',x.icon_url) order by x.profile)$$);

-- 6) Central › Aplicativos › Identidade: ler e salvar nome, cores, logo, abertura e ícone.
create or replace function public.platform_app_identity(p_action text, p_org uuid, p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path to '' as $$
declare o public.organizations; op private.ministry_app_openings; a private.ministry_apps; v_logo text;
begin
 if not private.has_aal2() or not private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]) then
  raise exception 'platform_operator_required' using errcode='42501';
 end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>360000 then raise exception 'invalid_identity' using errcode='22023'; end if;
 select * into o from public.organizations where id=p_org;
 if not found then raise exception 'organization_not_found' using errcode='P0002'; end if;
 if p_action='get' then
  return jsonb_build_object('organizationId',o.id,'ministry',o.name,'appName',coalesce(o.app_name,o.name),
   'primaryColor',coalesce(o.primary_color,'#285c45'),'accentColor',coalesce(o.accent_color,'#d8b769'),'theme',coalesce(o.app_theme,'dark'),
   'updatedAt',o.updated_at,'logo',(select logo_png from private.church_branding where scope_id=o.id),
   'opening',member_app_api.opening(o.id),'iconUrl',(select icon_url from private.ministry_apps where organization_id=o.id),
   'released',exists(select 1 from private.ministry_apps where organization_id=o.id),
   'canEdit',private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
 end if;
 if not private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]) then raise exception 'platform_operator_required' using errcode='42501'; end if;
 perform 1 from public.organizations where id=p_org for update;
 if p_action='identity' then
  if p_data-array['appName','primaryColor','accentColor','updatedAt']<>'{}' or length(btrim(coalesce(p_data->>'appName',''))) not between 2 and 60
   or coalesce(p_data->>'primaryColor','')!~'^#[0-9A-Fa-f]{6}$' or coalesce(p_data->>'accentColor','')!~'^#[0-9A-Fa-f]{6}$' then
   raise exception 'invalid_identity' using errcode='22023';
  end if;
  if o.updated_at is distinct from (p_data->>'updatedAt')::timestamptz then raise exception 'identity_changed' using errcode='40001'; end if;
  update public.organizations set app_name=btrim(p_data->>'appName'),primary_color=lower(p_data->>'primaryColor'),accent_color=lower(p_data->>'accentColor'),updated_at=clock_timestamp()
   where id=p_org returning * into o;
 elsif p_action='logo' then
  if p_data-array['logo']<>'{}' then raise exception 'invalid_identity' using errcode='22023'; end if;
  v_logo:=nullif(p_data->>'logo','');
  if not private.valid_church_logo(v_logo) then raise exception 'invalid_logo' using errcode='22023'; end if;
  insert into private.church_branding(scope_id,organization_id,unit_id,logo_png,updated_by) values(p_org,p_org,null,v_logo,auth.uid())
  on conflict(scope_id) do update set logo_png=excluded.logo_png,updated_by=excluded.updated_by,updated_at=clock_timestamp();
  update public.organizations set updated_at=clock_timestamp() where id=p_org returning * into o;
 elsif p_action='opening' then
  if p_data-array['kind','url','title','seconds','version']<>'{}' or coalesce(p_data->>'kind','') not in('none','image','video')
   or length(coalesce(p_data->>'title',''))>160 or coalesce(p_data->>'seconds','')!~'^[0-9]{1,2}$' or (p_data->>'seconds')::int not between 1 and 15
   or p_data->>'kind'<>'none' and not private.ministry_public_url(p_data->>'url')
   or p_data->>'kind'='video' and p_data->>'url' !~* '\.mp4(\?[^[:space:]]*)?$' then
   raise exception 'invalid_identity' using errcode='22023';
  end if;
  select * into op from private.ministry_app_openings where organization_id=p_org for update;
  if coalesce(op.version,0) is distinct from coalesce((p_data->>'version')::int,0) then raise exception 'identity_changed' using errcode='40001'; end if;
  insert into private.ministry_app_openings(organization_id,kind,url,title,seconds,updated_by)
  values(p_org,p_data->>'kind',case when p_data->>'kind'='none' then '' else p_data->>'url' end,coalesce(p_data->>'title',''),(p_data->>'seconds')::int,auth.uid())
  on conflict(organization_id) do update set kind=excluded.kind,url=excluded.url,title=excluded.title,seconds=excluded.seconds,
   version=ministry_app_openings.version+1,updated_by=auth.uid(),updated_at=clock_timestamp();
 elsif p_action='icon' then
  if p_data-array['url']<>'{}' then raise exception 'invalid_identity' using errcode='22023'; end if;
  update private.ministry_apps set icon_url=nullif(p_data->>'url',''),version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
   where organization_id=p_org returning * into a;
  if not found then raise exception 'app_not_released' using errcode='22023'; end if;
 else
  raise exception 'invalid_identity' using errcode='22023';
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_org,auth.uid(),'platform.app_identity.'||p_action,'organization',p_org::text,
  case p_action when 'identity' then p_data-'updatedAt' when 'opening' then p_data-'version' when 'icon' then p_data else jsonb_build_object('removed',v_logo is null) end);
 return public.platform_app_identity('get',p_org,'{}');
end $$;
revoke all on function public.platform_app_identity(text,uuid,jsonb) from public,anon;
grant execute on function public.platform_app_identity(text,uuid,jsonb) to authenticated;
commit;
