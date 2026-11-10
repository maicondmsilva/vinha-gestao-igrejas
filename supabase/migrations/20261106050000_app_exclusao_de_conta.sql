begin;
set local lock_timeout='5s';
-- App Store 5.1.1(v) / Google Play: the account holder can close their account from inside the app.
-- Church records (finance, Kids history, audit) stay with the church as required by law; the login is
-- revoked and the Auth identity is soft-deleted (e-mail and phone anonymized) by the server afterwards.
create table private.account_closures(
 user_id uuid primary key,
 organizations uuid[] not null default '{}',
 requested_via text not null check(requested_via in('app','web')),
 closed_at timestamptz not null default clock_timestamp()
);
alter table private.account_closures enable row level security;
revoke all on private.account_closures from public,anon,authenticated,service_role;

create function private.account_close(p_user uuid,p_via text) returns jsonb language plpgsql security definer set search_path='' as $$
declare orgs uuid[];
begin
 if p_user is null or p_via not in('app','web') then raise exception 'invalid_account_closure' using errcode='22023';end if;
 perform 1 from auth.users where id=p_user and deleted_at is null for update;
 if not found then
  if exists(select 1 from private.account_closures where user_id=p_user) then return jsonb_build_object('ok',true,'repeated',true);end if;
  raise exception 'account_unavailable' using errcode='42501';
 end if;
 -- Governance first: a church must never lose its last owner, pastor, admin or finance actor this way.
 if exists(select 1 from public.platform_operators where user_id=p_user and active) then
  return jsonb_build_object('ok',false,'reason','platform_operator');
 end if;
 if exists(select 1 from public.organization_memberships where user_id=p_user and status='active'
   and role in('owner','pastor','admin','finance')) then
  return jsonb_build_object('ok',false,'reason','privileged_role');
 end if;
 select coalesce(array_agg(organization_id),'{}') into orgs from public.organization_memberships where user_id=p_user;
 update public.organization_memberships set status='revoked',updated_at=clock_timestamp()
  where user_id=p_user and status<>'revoked';
 update private.member_push_devices set enabled=false,updated_at=clock_timestamp() where user_id=p_user and enabled;
 insert into private.account_closures(user_id,organizations,requested_via) values(p_user,orgs,p_via)
  on conflict(user_id) do nothing;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function private.account_close(uuid,text) from public,anon,authenticated;
grant execute on function private.account_close(uuid,text) to service_role;
-- Server-only wrapper: the API verifies the caller's own access token and passes only that user id.
create function public.account_close(p_user uuid,p_via text) returns jsonb language sql security definer set search_path='' as $$select private.account_close(p_user,p_via)$$;
revoke all on function public.account_close(uuid,text) from public,anon,authenticated;
grant execute on function public.account_close(uuid,text) to service_role;
notify pgrst,'reload schema';
commit;
