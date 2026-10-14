-- Only the account that created an unclaimed self-service organization may
-- create its first owner membership. Central invitations use the validated RPC.
alter table public.organizations add column bootstrap_user_id uuid references auth.users(id) default auth.uid();
create index organizations_bootstrap_user_idx on public.organizations(bootstrap_user_id);
create function private.is_organization_bootstrap_creator(p_organization uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.organizations where id=p_organization and bootstrap_user_id=auth.uid())
$$;
revoke all on function private.is_organization_bootstrap_creator(uuid) from public,anon;
grant execute on function private.is_organization_bootstrap_creator(uuid) to authenticated;
drop policy memberships_insert_authorized on public.organization_memberships;
create policy memberships_insert_authorized on public.organization_memberships for insert to authenticated with check (
 private.has_organization_role(organization_id,array['owner','pastor','admin']::public.membership_role[])
 or (user_id=(select auth.uid()) and role='owner' and status='active' and not private.current_user_has_memberships()
 and not private.organization_has_memberships(organization_id) and private.is_organization_bootstrap_creator(organization_id))
);

create function public.pending_organization_invitation() returns jsonb
language plpgsql stable security definer set search_path='' as $$ declare result jsonb; begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 select jsonb_build_object('token',i.invite_token,'organizationName',o.name) into result
 from public.saas_organization_invites i join public.organizations o on o.id=i.organization_id
 where i.owner_email=lower(auth.jwt()->>'email') and i.status='pending' and i.expires_at>now() and o.status in ('active','trial')
 order by i.created_at desc limit 1;
 return result;
end $$;
revoke all on function public.pending_organization_invitation() from public,anon;
grant execute on function public.pending_organization_invitation() to authenticated;
