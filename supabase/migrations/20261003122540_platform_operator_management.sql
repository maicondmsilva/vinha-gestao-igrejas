alter table public.platform_operators add column email text;

update public.platform_operators operator
set email = lower(auth_user.email)
from auth.users auth_user
where auth_user.id = operator.user_id;

alter table public.platform_operators
  alter column email set not null,
  add constraint platform_operators_email_format check (email = lower(email) and position('@' in email) > 1);

create unique index platform_operators_email_idx on public.platform_operators (email);

create table public.platform_operator_invites (
  id uuid primary key default extensions.gen_random_uuid(),
  email text not null check (email = lower(email) and position('@' in email) > 1),
  role public.platform_operator_role not null,
  token uuid not null unique default extensions.gen_random_uuid(),
  invited_by uuid not null references public.platform_operators(user_id),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create index platform_operator_invites_pending_idx
  on public.platform_operator_invites (email, expires_at)
  where accepted_at is null and revoked_at is null;

create unique index platform_operator_invites_one_pending_idx
  on public.platform_operator_invites (email)
  where accepted_at is null and revoked_at is null;

create table public.platform_operator_events (
  id bigint generated always as identity primary key,
  actor_user_id uuid references auth.users(id) on delete set null,
  target_user_id uuid references auth.users(id) on delete set null,
  invitation_id uuid references public.platform_operator_invites(id) on delete set null,
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index platform_operator_events_created_idx on public.platform_operator_events (created_at desc);

alter table public.platform_operator_invites enable row level security;
alter table public.platform_operator_events enable row level security;

create or replace function private.has_aal2()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce((select auth.jwt() ->> 'aal') = 'aal2', false);
$$;

drop policy platform_operators_select_self on public.platform_operators;

create policy platform_operators_select_scope
on public.platform_operators for select to authenticated
using (
  user_id = (select auth.uid())
  or (
    private.has_aal2()
    and private.is_platform_operator(array['owner', 'admin']::public.platform_operator_role[])
  )
);

create policy platform_operators_update_manager
on public.platform_operators for update to authenticated
using (
  private.has_aal2()
  and private.is_platform_operator(array['owner', 'admin']::public.platform_operator_role[])
  and (
    private.is_platform_operator(array['owner']::public.platform_operator_role[])
    or role <> 'owner'
  )
)
with check (
  private.has_aal2()
  and private.is_platform_operator(array['owner', 'admin']::public.platform_operator_role[])
  and (
    private.is_platform_operator(array['owner']::public.platform_operator_role[])
    or role <> 'owner'
  )
);

create policy platform_operator_invites_select_scope
on public.platform_operator_invites for select to authenticated
using (
  email = lower((select auth.jwt() ->> 'email'))
  or (
    private.has_aal2()
    and private.is_platform_operator(array['owner', 'admin']::public.platform_operator_role[])
  )
);

create policy platform_operator_invites_create_manager
on public.platform_operator_invites for insert to authenticated
with check (
  invited_by = (select auth.uid())
  and private.has_aal2()
  and private.is_platform_operator(array['owner', 'admin']::public.platform_operator_role[])
  and (
    private.is_platform_operator(array['owner']::public.platform_operator_role[])
    or role <> 'owner'
  )
);

create policy platform_operator_invites_update_scope
on public.platform_operator_invites for update to authenticated
using (
  private.has_aal2()
  and private.is_platform_operator(array['owner', 'admin']::public.platform_operator_role[])
)
with check (
  private.has_aal2()
  and private.is_platform_operator(array['owner', 'admin']::public.platform_operator_role[])
);

create policy platform_operator_events_select_manager
on public.platform_operator_events for select to authenticated
using (
  private.has_aal2()
  and private.is_platform_operator(array['owner', 'admin']::public.platform_operator_role[])
);

create or replace function private.protect_platform_operator()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.user_id = (select auth.uid()) and not new.active then
    raise exception 'an operator cannot suspend their own access';
  end if;

  if old.role = 'owner' and old.active and (new.role <> 'owner' or not new.active)
    and (select count(*) from public.platform_operators where role = 'owner' and active) <= 1 then
    raise exception 'the last active owner cannot be removed';
  end if;

  return new;
end;
$$;

create trigger platform_operators_protect_owner
before update on public.platform_operators
for each row execute function private.protect_platform_operator();

create or replace function private.audit_platform_operator_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.platform_operator_events (actor_user_id, target_user_id, action, metadata)
  values (
    (select auth.uid()),
    case when tg_op = 'INSERT' then new.user_id else old.user_id end,
    case when tg_op = 'INSERT' then 'operator.created' else 'operator.updated' end,
    jsonb_build_object(
      'role', new.role,
      'active', new.active
    )
  );
  return new;
end;
$$;

create trigger platform_operators_audit
after insert or update on public.platform_operators
for each row execute function private.audit_platform_operator_change();

create or replace function private.audit_platform_invitation_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.platform_operator_events (actor_user_id, invitation_id, action, metadata)
  values (
    (select auth.uid()),
    new.id,
    case
      when tg_op = 'INSERT' then 'invitation.created'
      when new.accepted_at is not null and old.accepted_at is null then 'invitation.accepted'
      when new.revoked_at is not null and old.revoked_at is null then 'invitation.revoked'
      else 'invitation.updated'
    end,
    jsonb_build_object('email', new.email, 'role', new.role)
  );
  return new;
end;
$$;

create trigger platform_operator_invites_audit
after insert or update on public.platform_operator_invites
for each row execute function private.audit_platform_invitation_change();

create or replace function public.bootstrap_platform_owner(p_full_name text)
returns table (
  user_id uuid,
  role public.platform_operator_role,
  full_name text,
  active boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  insert into public.platform_operators (user_id, email, role, full_name)
  values (
    (select auth.uid()),
    lower((select auth.jwt() ->> 'email')),
    'owner',
    trim(p_full_name)
  );

  return query select * from public.platform_operator_context();
end;
$$;

create or replace function private.accept_platform_operator_invite(p_token uuid, p_full_name text)
returns table (
  user_id uuid,
  role public.platform_operator_role,
  full_name text,
  active boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation public.platform_operator_invites;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  select * into invitation
  from public.platform_operator_invites
  where token = p_token
    and email = lower((select auth.jwt() ->> 'email'))
    and accepted_at is null
    and revoked_at is null
    and expires_at > now();

  if invitation.id is null then
    raise exception 'invalid or expired invitation';
  end if;

  insert into public.platform_operators (user_id, email, role, full_name)
  values ((select auth.uid()), invitation.email, invitation.role, trim(p_full_name));

  update public.platform_operator_invites
  set accepted_at = now()
  where id = invitation.id;

  return query select * from public.platform_operator_context();
end;
$$;

create or replace function public.accept_platform_operator_invite(p_token uuid, p_full_name text)
returns table (
  user_id uuid,
  role public.platform_operator_role,
  full_name text,
  active boolean
)
language sql
security invoker
set search_path = ''
as $$
  select * from private.accept_platform_operator_invite(p_token, p_full_name);
$$;

grant select, update on public.platform_operators to authenticated;
grant select, insert, update on public.platform_operator_invites to authenticated;
grant select on public.platform_operator_events to authenticated;
revoke insert, update, delete on public.platform_operator_events from authenticated, anon;
revoke all on function public.accept_platform_operator_invite(uuid, text) from public, anon;
grant execute on function public.accept_platform_operator_invite(uuid, text) to authenticated;
revoke all on function private.accept_platform_operator_invite(uuid, text) from public, anon;
grant execute on function private.accept_platform_operator_invite(uuid, text) to authenticated;
grant execute on function private.has_aal2() to authenticated;
revoke all on function private.protect_platform_operator() from public, anon, authenticated;
revoke all on function private.audit_platform_operator_change() from public, anon, authenticated;
revoke all on function private.audit_platform_invitation_change() from public, anon, authenticated;
