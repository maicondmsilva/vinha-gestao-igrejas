set local check_function_bodies=on;
set local lock_timeout='5s';
set local statement_timeout='30s';
alter table public.saas_organization_invites add column accepted_user_id uuid;
-- No backfill or FK that would erase the binding when an account is deleted.
create or replace function private.accept_organization_invite(p_token uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare invitation public.saas_organization_invites; account auth.users; membership public.organization_memberships;
 org public.organizations; org_id uuid; unit_id uuid;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 select * into account from auth.users where id=auth.uid() for share;
 if account.id is null or account.email is null or account.email_confirmed_at is null or account.deleted_at is not null
  or coalesce(account.is_anonymous,false) or account.banned_until>clock_timestamp() then
  raise exception 'confirmed_email_required' using errcode='42501'; end if;
 select organization_id into org_id from public.saas_organization_invites where invite_token=p_token;
 if org_id is null then raise exception 'invite_not_found' using errcode='P0002'; end if;
 -- Same ministry-first order as governance; row locks serialize accept/revoke and stale snapshots.
 select * into org from public.organizations where id=org_id for update;
 if org.id is null or org.status not in ('active','trial') then raise exception 'invite_unavailable' using errcode='42501'; end if;
 select * into invitation from public.saas_organization_invites where invite_token=p_token and organization_id=org.id for update;
 if invitation.id is null then raise exception 'invite_not_found' using errcode='P0002'; end if;
 if invitation.owner_email<>lower(account.email) then raise exception 'invite_email_mismatch' using errcode='42501'; end if;
 if invitation.status not in ('pending','accepted') then raise exception 'invite_unavailable' using errcode='42501'; end if;
 select * into membership from public.organization_memberships where organization_id=org.id and user_id=account.id for update;
 if invitation.status='accepted' then
  if membership.id is null or membership.status<>'active' or
   (invitation.accepted_user_id is not null and invitation.accepted_user_id<>account.id) or
   (invitation.accepted_user_id is null and membership.role<>'owner') then
   raise exception 'invite_access_revoked' using errcode='42501'; end if;
  -- Legacy unbound links only resume an already active owner: never grant or restore powers.
  return jsonb_build_object('slug',org.slug,'alreadyAccepted',true);
 end if;
 if invitation.expires_at<=clock_timestamp() then raise exception 'invite_expired' using errcode='22023'; end if;
 if not exists(select 1 from public.platform_operators where user_id=invitation.created_by and active and role in ('owner','admin')) then
  raise exception 'invite_issuer_unavailable' using errcode='42501'; end if;
 if membership.id is not null and (membership.status<>'active' or membership.role<>'owner') then
  raise exception 'invite_existing_membership' using errcode='42501'; end if;
 select id into unit_id from public.organization_units where organization_id=org.id and unit_type='headquarters' and status='active' order by created_at,id limit 1 for share;
 if unit_id is null then raise exception 'invite_unit_unavailable' using errcode='42501'; end if;
 if membership.id is null then
  insert into public.organization_memberships(organization_id,user_id,default_unit_id,role,status)
  values(org.id,account.id,unit_id,'owner','active');
  update public.profiles set full_name=coalesce(nullif(full_name,''),invitation.owner_name),email=lower(account.email) where id=account.id;
  insert into public.user_access_preferences(user_id,selected_organization_id,selected_unit_id) values(account.id,org.id,unit_id)
  on conflict(user_id) do update set selected_organization_id=excluded.selected_organization_id,selected_unit_id=excluded.selected_unit_id,updated_at=now();
 end if;
 update public.saas_organization_invites set status='accepted',accepted_at=clock_timestamp(),accepted_user_id=account.id where id=invitation.id;
 update public.saas_onboarding_progress set status='in_progress',started_at=coalesce(started_at,now()),updated_at=now()
 where organization_id=org.id and status<>'completed';
 insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata)
 values(account.id,'organization.activated','organization',org.id::text,jsonb_build_object('invite_id',invitation.id,'existing_owner',membership.id is not null));
 return jsonb_build_object('slug',org.slug,'alreadyAccepted',membership.id is not null);
end $$;

create or replace function public.pending_organization_invitation()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; current_email text;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 select lower(email) into current_email from auth.users where id=auth.uid() and email_confirmed_at is not null
  and deleted_at is null and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<=now());
 if current_email is null then return null; end if;
 select jsonb_build_object('token',i.invite_token,'organizationName',o.name) into result
 from public.saas_organization_invites i join public.organizations o on o.id=i.organization_id
 join public.platform_operators issuer on issuer.user_id=i.created_by and issuer.active and issuer.role in ('owner','admin')
 where i.owner_email=current_email and i.status='pending' and i.expires_at>now() and o.status in ('active','trial')
 and not exists(select 1 from public.organization_memberships m where m.organization_id=o.id and m.user_id=auth.uid() and (m.status<>'active' or m.role<>'owner'))
 order by i.created_at desc,i.id limit 1;
 return result;
end $$;

create or replace function private.organization_invite_preview(p_token uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 select jsonb_build_object('organization',jsonb_build_object('name',o.name,'appName',coalesce(o.app_name,o.name),'slug',o.slug,'color',o.primary_color),
 'ownerName',case when i.status='pending' and i.expires_at>now() then i.owner_name else '' end,
 'ownerEmail',case when i.status='pending' and i.expires_at>now() then regexp_replace(i.owner_email,'^(.{2}).*(@.*)$','\1••••\2') else '' end,
 'planName',case when i.status in ('pending','accepted') then p.name else '' end,
 'status',case when i.status='pending' and i.expires_at<=now() then 'expired' else i.status end) into result
 from public.saas_organization_invites i join public.organizations o on o.id=i.organization_id
 left join public.saas_subscriptions s on s.organization_id=o.id left join public.saas_plans p on p.id=s.plan_id
 where i.invite_token=p_token and o.status in ('active','trial');
 if result is null then raise exception 'invite_unavailable' using errcode='P0002'; end if;
 return result;
end $$;
