-- Canonical visual identity. Institutional data remains in organizations / organization_units.
create table private.church_branding (
 scope_id uuid primary key,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid unique references public.organization_units(id) on delete cascade,
 logo_png text,
 updated_at timestamptz not null default clock_timestamp(),
 updated_by uuid references auth.users(id),
 check (scope_id=coalesce(unit_id,organization_id)),
 check (logo_png is null or octet_length(logo_png)<=341358)
);
create index church_branding_organization_idx on private.church_branding(organization_id);
create index church_branding_updated_by_idx on private.church_branding(updated_by);
alter table private.church_branding enable row level security;
revoke all on private.church_branding from public,anon,authenticated,service_role;

create function private.valid_church_logo(p_logo text) returns boolean
language plpgsql immutable security invoker set search_path='' as $$
declare b bytea; w bigint; h bigint;
begin
 if p_logo is null or p_logo='' then return true; end if;
 if octet_length(p_logo)>341358 or p_logo !~ '^data:image/png;base64,[A-Za-z0-9+/]+={0,2}$' then return false; end if;
 b:=decode(substr(p_logo,23),'base64');
 if octet_length(b) not between 45 and 256000 or encode(substring(b from 1 for 8),'hex')<>'89504e470d0a1a0a'
 or encode(substring(b from 9 for 8),'hex')<>'0000000d49484452'
 or encode(substring(b from octet_length(b)-11 for 12),'hex')<>'0000000049454e44ae426082' then return false; end if;
 w:=get_byte(b,16)::bigint*16777216+get_byte(b,17)*65536+get_byte(b,18)*256+get_byte(b,19);
 h:=get_byte(b,20)::bigint*16777216+get_byte(b,21)*65536+get_byte(b,22)*256+get_byte(b,23);
 return w between 1 and 2000 and h between 1 and 2000 and w*h<=2000000;
exception when others then return false;
end $$;
revoke all on function private.valid_church_logo(text) from public,anon,authenticated;

create function private.save_church_brand(p_org uuid,p_unit uuid,p_logo text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organization_memberships where organization_id=p_org and user_id=auth.uid()
 and status='active' and role in ('owner','admin','pastor') for share;
 if not found then raise exception 'settings_access_denied' using errcode='42501'; end if;
 perform 1 from public.organizations where id=p_org and status in ('active','trial') for update;
 if not found then raise exception 'settings_access_denied' using errcode='42501'; end if;
 if p_unit is not null then
  perform 1 from public.organization_units where id=p_unit and organization_id=p_org and status='active' for update;
  if not found then raise exception 'settings_access_denied' using errcode='42501'; end if;
 end if;
 if not private.valid_church_logo(p_logo) then raise exception 'invalid_logo' using errcode='22023'; end if;
 insert into private.church_branding(scope_id,organization_id,unit_id,logo_png,updated_by)
 values(coalesce(p_unit,p_org),p_org,p_unit,nullif(p_logo,''),auth.uid())
 on conflict(scope_id) do update set logo_png=excluded.logo_png,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 if p_unit is null then update public.organizations set updated_at=clock_timestamp() where id=p_org;
 else update public.organization_units set updated_at=clock_timestamp() where id=p_unit and organization_id=p_org; end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_org,auth.uid(),'settings.logo.updated','church_branding',coalesce(p_unit,p_org),jsonb_build_object('removed',coalesce(p_logo,'')=''));
end $$;
revoke all on function private.save_church_brand(uuid,uuid,text) from public,anon;
grant execute on function private.save_church_brand(uuid,uuid,text) to authenticated;

create function private.church_branding_read(p_org uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.has_organization_role(p_org,array['owner','admin','pastor','secretary','leader','finance','member','viewer']::public.membership_role[])
 then raise exception 'settings_access_denied' using errcode='42501'; end if;
 return coalesce((select jsonb_object_agg(scope_id::text,logo_png) from private.church_branding where organization_id=p_org),'{}'::jsonb);
end $$;
revoke all on function private.church_branding_read(uuid) from public,anon;
grant execute on function private.church_branding_read(uuid) to authenticated;
create function public.church_branding_read(p_org uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.church_branding_read(p_org)$$;
revoke all on function public.church_branding_read(uuid) from public,anon;
grant execute on function public.church_branding_read(uuid) to authenticated;

create function private.organization_settings_save(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare original timestamptz; saved timestamptz; item record; allowed text[];
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organization_memberships where organization_id=p_org and user_id=auth.uid() and status='active' and role in ('owner','admin','pastor') for share;
 if not found then raise exception 'settings_access_denied' using errcode='42501'; end if;
 select updated_at into original from public.organizations where id=p_org and status in ('active','trial') for update;
 if not found then raise exception 'settings_access_denied' using errcode='42501'; end if;
 if p_unit is not null then
  select updated_at into original from public.organization_units where id=p_unit and organization_id=p_org and status='active' for update;
  if not found then raise exception 'settings_access_denied' using errcode='42501'; end if;
 end if;
 if jsonb_typeof(p_data)<>'object' or nullif(p_data->>'updatedAt','') is null then raise exception 'invalid_settings' using errcode='22023'; end if;
 if original is distinct from (p_data->>'updatedAt')::timestamptz then raise exception 'settings_changed' using errcode='40001'; end if;
 allowed:=case when p_unit is null then array['updatedAt','name','appName','seniorPastorName','legalName','taxId','primaryColor','accentColor','logo'] else array['updatedAt','name','pastorName','legalName','taxId','email','phone','address','logo'] end;
 if exists(select 1 from jsonb_object_keys(p_data) k where not k=any(allowed)) then raise exception 'invalid_settings' using errcode='22023'; end if;
 for item in select key,value from jsonb_each(p_data) where key not in ('address','logo') loop
  if jsonb_typeof(item.value)<>'string' or length(item.value#>>'{}')>200 then raise exception 'invalid_settings' using errcode='22023'; end if;
 end loop;
 if length(trim(coalesce(p_data->>'name','')))<2 then raise exception 'invalid_settings' using errcode='22023'; end if;
 if p_unit is null then
  if length(trim(coalesce(p_data->>'appName','')))<2 or length(trim(coalesce(p_data->>'seniorPastorName','')))<2 or coalesce(p_data->>'primaryColor','') !~ '^#[0-9A-Fa-f]{6}$' or coalesce(p_data->>'accentColor','') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'invalid_settings' using errcode='22023'; end if;
  update public.organizations set name=trim(p_data->>'name'),app_name=trim(p_data->>'appName'),senior_pastor_name=trim(p_data->>'seniorPastorName'),legal_name=nullif(trim(p_data->>'legalName'),''),tax_id=nullif(trim(p_data->>'taxId'),''),primary_color=p_data->>'primaryColor',accent_color=p_data->>'accentColor',updated_at=clock_timestamp() where id=p_org returning updated_at into saved;
 else
  if jsonb_typeof(p_data->'address') is distinct from 'object' or exists(select 1 from jsonb_each(p_data->'address') e where e.key not in ('postal_code','street','number','complement','district','city','state') or jsonb_typeof(e.value)<>'string' or length(e.value#>>'{}')>200)
  or coalesce(p_data->>'email','')<>'' and p_data->>'email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  then raise exception 'invalid_settings' using errcode='22023'; end if;
  update public.organization_units set name=trim(p_data->>'name'),pastor_name=nullif(trim(p_data->>'pastorName'),''),legal_name=nullif(trim(p_data->>'legalName'),''),tax_id=nullif(trim(p_data->>'taxId'),''),email=nullif(lower(trim(p_data->>'email')),''),phone=nullif(trim(p_data->>'phone'),''),address=coalesce(address,'{}')||(p_data->'address'),updated_at=clock_timestamp() where id=p_unit and organization_id=p_org returning updated_at into saved;
 end if;
 if p_data ? 'logo' then perform private.save_church_brand(p_org,p_unit,p_data->>'logo'); end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_org,auth.uid(),'settings.profile.updated',case when p_unit is null then 'organization' else 'organization_unit' end,coalesce(p_unit,p_org),jsonb_build_object('fields',to_jsonb(allowed)-'logo'));
 return jsonb_build_object('ok',true,'updatedAt',saved);
end $$;
revoke all on function private.organization_settings_save(uuid,uuid,jsonb) from public,anon;
grant execute on function private.organization_settings_save(uuid,uuid,jsonb) to authenticated;
create function public.organization_settings_save(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.organization_settings_save(p_org,p_unit,p_data)$$;
revoke all on function public.organization_settings_save(uuid,uuid,jsonb) from public,anon;
grant execute on function public.organization_settings_save(uuid,uuid,jsonb) to authenticated;

-- Keep onboarding behavior and its existing guards; save the optional logo in the same transaction.
do $$declare definition text; anchor text:='if step=''identity'' then'; begin
 definition:=pg_get_functiondef('public.save_organization_onboarding(uuid,jsonb)'::regprocedure);
 if position('private.save_church_brand' in definition)>0 then return; end if;
 if position(anchor in definition)=0 then raise exception 'onboarding_definition_changed'; end if;
 definition:=replace(definition,anchor,anchor||E'\n if p_data ? ''logo'' then perform private.save_church_brand(p_organization_id,null,p_data->>''logo''); end if;');
 execute definition;
end $$;
