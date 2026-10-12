create or replace function private.current_user_email()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select lower(email)
  from auth.users
  where id = (select auth.uid());
$$;

drop policy if exists platform_operator_invites_select_scope
on public.platform_operator_invites;

create policy platform_operator_invites_select_scope
on public.platform_operator_invites for select to authenticated
using (
  email = private.current_user_email()
  or (
    private.has_aal2()
    and private.is_platform_operator(array['owner', 'admin']::public.platform_operator_role[])
  )
);

revoke all on function private.current_user_email() from public, anon;
grant execute on function private.current_user_email() to authenticated;
