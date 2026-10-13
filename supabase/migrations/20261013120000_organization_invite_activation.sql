create or replace function private.organization_invite_preview(p_token uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$ declare v_result jsonb; begin
  select jsonb_build_object(
    'organization',jsonb_build_object('name',o.name,'appName',coalesce(o.app_name,o.name),'slug',o.slug,'color',o.primary_color),
    'ownerName',i.owner_name,
    'ownerEmail',regexp_replace(i.owner_email,'^(.{2}).*(@.*)$','\1••••\2'),
    'planName',p.name,
    'trialEndsAt',s.trial_ends_at,
    'status',case when i.status='pending' and i.expires_at<=now() then 'expired' else i.status end
  ) into v_result
  from public.saas_organization_invites i
  join public.organizations o on o.id=i.organization_id
  left join public.saas_subscriptions s on s.organization_id=o.id
  left join public.saas_plans p on p.id=s.plan_id
  where i.invite_token=p_token;
  if v_result is null then raise exception 'invite_not_found' using errcode='P0002'; end if;
  return v_result;
end $$;

create or replace function private.accept_organization_invite(p_token uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare v_invite public.saas_organization_invites; v_user_id uuid:=auth.uid(); v_email text:=lower(auth.jwt()->>'email'); v_unit_id uuid; begin
  if v_user_id is null or v_email is null then raise exception 'authentication_required' using errcode='28000'; end if;
  select * into v_invite from public.saas_organization_invites where invite_token=p_token for update;
  if v_invite.id is null then raise exception 'invite_not_found' using errcode='P0002'; end if;
  if v_invite.owner_email<>v_email then raise exception 'invite_email_mismatch' using errcode='42501'; end if;
  if v_invite.status='accepted' then
    if exists(select 1 from public.organization_memberships where organization_id=v_invite.organization_id and user_id=v_user_id and status='active') then
      return jsonb_build_object('slug',(select slug from public.organizations where id=v_invite.organization_id),'alreadyAccepted',true);
    end if;
    raise exception 'invite_already_used' using errcode='42501';
  end if;
  if v_invite.status<>'pending' or v_invite.expires_at<=now() then raise exception 'invite_expired' using errcode='22023'; end if;
  select id into v_unit_id from public.organization_units where organization_id=v_invite.organization_id and unit_type='headquarters' and status='active' order by created_at limit 1;
  insert into public.organization_memberships(organization_id,user_id,default_unit_id,role,status) values(v_invite.organization_id,v_user_id,v_unit_id,'owner','active')
  on conflict(organization_id,user_id) do update set default_unit_id=excluded.default_unit_id,role='owner',status='active',updated_at=now();
  update public.profiles set full_name=coalesce(nullif(full_name,''),v_invite.owner_name),email=v_email where id=v_user_id;
  insert into public.user_access_preferences(user_id,selected_organization_id,selected_unit_id) values(v_user_id,v_invite.organization_id,v_unit_id)
  on conflict(user_id) do update set selected_organization_id=excluded.selected_organization_id,selected_unit_id=excluded.selected_unit_id,updated_at=now();
  update public.saas_organization_invites set status='accepted',accepted_at=now() where id=v_invite.id;
  update public.saas_onboarding_progress set status='in_progress',started_at=coalesce(started_at,now()),updated_at=now() where organization_id=v_invite.organization_id;
  insert into public.platform_audit_events(actor_user_id,action,entity_type,entity_id,metadata) values(v_user_id,'organization.activated','organization',v_invite.organization_id::text,jsonb_build_object('owner_email',v_email));
  return jsonb_build_object('slug',(select slug from public.organizations where id=v_invite.organization_id),'alreadyAccepted',false);
end $$;

create or replace function public.organization_invite_preview(p_token uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.organization_invite_preview(p_token) $$;
create or replace function public.accept_organization_invite(p_token uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.accept_organization_invite(p_token) $$;

revoke all on function private.organization_invite_preview(uuid),private.accept_organization_invite(uuid) from public;
grant execute on function private.organization_invite_preview(uuid) to anon,authenticated;
grant execute on function private.accept_organization_invite(uuid) to authenticated;
revoke all on function public.organization_invite_preview(uuid),public.accept_organization_invite(uuid) from public;
grant execute on function public.organization_invite_preview(uuid) to anon,authenticated;
grant execute on function public.accept_organization_invite(uuid) to authenticated;
