-- The first organization and membership must be created atomically before any
-- tenant-scoped RLS relationship exists. The function validates auth.uid(),
-- serializes requests per user and refuses users with an existing membership.
alter function public.bootstrap_organization(text, text, text, text)
  security definer;

-- Keep the private schema private. These tightly scoped public wrappers are
-- allowed to call the private implementations, which validate token state,
-- expiration and the authenticated e-mail before changing any data.
alter function public.organization_invite_preview(uuid)
  security definer;

alter function public.accept_organization_invite(uuid)
  security definer;

revoke all on function public.bootstrap_organization(text, text, text, text) from public, anon;
grant execute on function public.bootstrap_organization(text, text, text, text) to authenticated;

revoke all on function public.organization_invite_preview(uuid) from public;
grant execute on function public.organization_invite_preview(uuid) to anon, authenticated;

revoke all on function public.accept_organization_invite(uuid) from public, anon;
grant execute on function public.accept_organization_invite(uuid) to authenticated;
