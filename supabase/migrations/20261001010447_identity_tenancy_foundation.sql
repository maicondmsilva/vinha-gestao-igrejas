create extension if not exists pgcrypto with schema extensions;

create type public.organization_status as enum ('active', 'trial', 'suspended', 'cancelled');
create type public.unit_type as enum ('headquarters', 'campus', 'congregation', 'regional', 'branch');
create type public.membership_role as enum ('owner', 'pastor', 'admin', 'secretary', 'finance', 'leader', 'member', 'viewer');
create type public.membership_status as enum ('pending', 'active', 'suspended', 'revoked');
create type public.unit_access_level as enum ('read', 'manage', 'admin');

create table public.organizations (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  legal_name text,
  tax_id text,
  status public.organization_status not null default 'trial',
  primary_color text not null default '#166534' check (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_units (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  parent_unit_id uuid references public.organization_units(id) on delete set null,
  name text not null check (char_length(name) between 2 and 120),
  slug text not null check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  unit_type public.unit_type not null default 'congregation',
  status public.organization_status not null default 'active',
  address jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, slug),
  unique (id, organization_id)
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_memberships (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  default_unit_id uuid,
  role public.membership_role not null default 'member',
  status public.membership_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, user_id),
  foreign key (default_unit_id, organization_id)
    references public.organization_units(id, organization_id) on delete set null
);

create table public.membership_unit_access (
  membership_id uuid not null references public.organization_memberships(id) on delete cascade,
  unit_id uuid not null references public.organization_units(id) on delete cascade,
  access_level public.unit_access_level not null default 'read',
  include_children boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (membership_id, unit_id)
);

create index organization_units_organization_idx on public.organization_units (organization_id);
create index organization_units_parent_idx on public.organization_units (parent_unit_id);
create index memberships_user_status_idx on public.organization_memberships (user_id, status);
create index memberships_organization_role_idx on public.organization_memberships (organization_id, role, status);
create index memberships_default_unit_idx on public.organization_memberships (default_unit_id);
create index unit_access_unit_idx on public.membership_unit_access (unit_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger organizations_set_updated_at
before update on public.organizations
for each row execute function public.set_updated_at();

create trigger organization_units_set_updated_at
before update on public.organization_units
for each row execute function public.set_updated_at();

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger memberships_set_updated_at
before update on public.organization_memberships
for each row execute function public.set_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.email,
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

alter table public.organizations enable row level security;
alter table public.organization_units enable row level security;
alter table public.profiles enable row level security;
alter table public.organization_memberships enable row level security;
alter table public.membership_unit_access enable row level security;

create schema if not exists private;

create or replace function private.is_organization_member(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.organization_memberships m
    where m.organization_id = target_organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  );
$$;

create or replace function private.has_organization_role(
  target_organization_id uuid,
  allowed_roles public.membership_role[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.organization_memberships m
    where m.organization_id = target_organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and m.role = any(allowed_roles)
  );
$$;

create or replace function private.can_view_profile(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_user_id = (select auth.uid()) or exists (
    select 1
    from public.organization_memberships mine
    join public.organization_memberships theirs
      on theirs.organization_id = mine.organization_id
    where mine.user_id = (select auth.uid())
      and mine.status = 'active'
      and theirs.user_id = target_user_id
      and theirs.status = 'active'
  );
$$;

create or replace function private.can_view_membership(
  target_organization_id uuid,
  target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_user_id = (select auth.uid())
    or private.has_organization_role(
      target_organization_id,
      array['owner', 'pastor', 'admin', 'secretary']::public.membership_role[]
    );
$$;

create or replace function private.membership_organization(target_membership_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select organization_id
  from public.organization_memberships
  where id = target_membership_id;
$$;

create or replace function private.membership_user(target_membership_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select user_id
  from public.organization_memberships
  where id = target_membership_id;
$$;

create policy organizations_select_member
on public.organizations for select to authenticated
using (
  private.is_organization_member(organizations.id)
);

create policy organizations_update_admin
on public.organizations for update to authenticated
using (
  private.has_organization_role(organizations.id, array['owner', 'pastor', 'admin']::public.membership_role[])
)
with check (
  private.has_organization_role(organizations.id, array['owner', 'pastor', 'admin']::public.membership_role[])
);

create policy units_select_member
on public.organization_units for select to authenticated
using (
  private.is_organization_member(organization_units.organization_id)
);

create policy units_write_admin
on public.organization_units for all to authenticated
using (
  private.has_organization_role(organization_units.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
)
with check (
  private.has_organization_role(organization_units.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
);

create policy profiles_select_related
on public.profiles for select to authenticated
using (
  private.can_view_profile(profiles.id)
);

create policy profiles_update_self
on public.profiles for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy memberships_select_scope
on public.organization_memberships for select to authenticated
using (
  private.can_view_membership(organization_memberships.organization_id, organization_memberships.user_id)
);

create policy memberships_write_admin
on public.organization_memberships for all to authenticated
using (
  private.has_organization_role(organization_memberships.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
)
with check (
  private.has_organization_role(organization_memberships.organization_id, array['owner', 'pastor', 'admin']::public.membership_role[])
);

create policy unit_access_select_scope
on public.membership_unit_access for select to authenticated
using (
  private.can_view_membership(
    private.membership_organization(membership_unit_access.membership_id),
    private.membership_user(membership_unit_access.membership_id)
  )
);

create policy unit_access_write_admin
on public.membership_unit_access for all to authenticated
using (
  private.has_organization_role(
    private.membership_organization(membership_unit_access.membership_id),
    array['owner', 'pastor', 'admin']::public.membership_role[]
  )
)
with check (
  private.has_organization_role(
    private.membership_organization(membership_unit_access.membership_id),
    array['owner', 'pastor', 'admin']::public.membership_role[]
  )
);

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on all functions in schema private from public, anon;
grant usage on schema private to authenticated;
grant execute on all functions in schema private to authenticated;

