alter table public.organization_units
  add column legal_name text,
  add column tax_id text,
  add column pastor_name text,
  add column email text,
  add column phone text,
  add column financial_autonomy boolean not null default false,
  add column communication_autonomy boolean not null default true,
  add column branding_autonomy boolean not null default false;

alter table public.organization_units
  add constraint organization_units_parent_same_organization_fkey
  foreign key (parent_unit_id, organization_id)
  references public.organization_units (id, organization_id)
  on delete set null (parent_unit_id);

create table public.people (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  unit_id uuid,
  auth_user_id uuid references auth.users(id) on delete set null,
  full_name text not null check (char_length(trim(full_name)) between 2 and 160),
  photo_path text,
  birth_date date,
  gender text,
  marital_status text,
  cpf text,
  email text,
  phone text,
  journey_status text not null default 'Visitante',
  group_name text,
  first_visit_at timestamptz,
  joined_at timestamptz,
  baptized boolean not null default false,
  baptism_date date,
  tags text[] not null default '{}',
  app_role text not null default 'member',
  status text not null default 'active' check (status in ('pending', 'active', 'inactive', 'rejected', 'deceased')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id),
  foreign key (unit_id, organization_id)
    references public.organization_units(id, organization_id) on delete set null (unit_id)
);

create unique index people_organization_email_unique
  on public.people (organization_id, lower(email))
  where email is not null and trim(email) <> '';
create index people_organization_status_idx on public.people (organization_id, status);
create index people_unit_idx on public.people (organization_id, unit_id);
create index people_auth_user_idx on public.people (auth_user_id) where auth_user_id is not null;
create index people_name_search_idx on public.people (organization_id, lower(full_name));

create table public.person_addresses (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  person_id uuid not null,
  postal_code text,
  street text,
  number text,
  complement text,
  district text,
  city text,
  state text,
  country_code text not null default 'BR',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, person_id),
  foreign key (person_id, organization_id)
    references public.people(id, organization_id) on delete cascade
);

create table public.emergency_contacts (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  person_id uuid not null,
  name text not null check (char_length(trim(name)) between 2 and 160),
  relationship text,
  phone text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (person_id, organization_id)
    references public.people(id, organization_id) on delete cascade
);

create index emergency_contacts_person_idx on public.emergency_contacts (organization_id, person_id);

create table public.person_consents (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  person_id uuid not null,
  consent_type text not null,
  granted boolean not null,
  source text not null default 'admin',
  term_id uuid,
  accepted_by_person_id uuid,
  subject_person_id uuid,
  acceptance_snapshot jsonb not null default '{}'::jsonb,
  ip_address inet,
  user_agent text,
  granted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (person_id, organization_id)
    references public.people(id, organization_id) on delete cascade,
  foreign key (accepted_by_person_id, organization_id)
    references public.people(id, organization_id) on delete set null (accepted_by_person_id),
  foreign key (subject_person_id, organization_id)
    references public.people(id, organization_id) on delete set null (subject_person_id)
);

create index person_consents_person_type_idx
  on public.person_consents (organization_id, person_id, consent_type, created_at desc);

create table public.pastoral_notes (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  person_id uuid not null,
  author_user_id uuid not null references auth.users(id) on delete restrict,
  content text not null check (char_length(trim(content)) between 1 and 10000),
  visibility text not null default 'pastoral' check (visibility in ('pastoral', 'leadership')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (person_id, organization_id)
    references public.people(id, organization_id) on delete cascade
);

create index pastoral_notes_person_idx on public.pastoral_notes (organization_id, person_id, created_at desc);

create trigger people_set_updated_at
before update on public.people
for each row execute function public.set_updated_at();

create trigger person_addresses_set_updated_at
before update on public.person_addresses
for each row execute function public.set_updated_at();

create trigger emergency_contacts_set_updated_at
before update on public.emergency_contacts
for each row execute function public.set_updated_at();

create trigger pastoral_notes_set_updated_at
before update on public.pastoral_notes
for each row execute function public.set_updated_at();

create or replace function private.can_access_unit(
  target_organization_id uuid,
  target_unit_id uuid,
  required_levels public.unit_access_level[] default array['read', 'manage', 'admin']::public.unit_access_level[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_organization_role(
    target_organization_id,
    array['owner', 'pastor', 'admin']::public.membership_role[]
  ) or exists (
    with recursive ancestors as (
      select u.id, u.parent_unit_id
      from public.organization_units u
      where u.id = target_unit_id
        and u.organization_id = target_organization_id
      union all
      select parent.id, parent.parent_unit_id
      from public.organization_units parent
      join ancestors child on child.parent_unit_id = parent.id
      where parent.organization_id = target_organization_id
    )
    select 1
    from public.organization_memberships membership
    join public.membership_unit_access access
      on access.membership_id = membership.id
    join ancestors scope on scope.id = access.unit_id
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.status = 'active'
      and access.access_level = any(required_levels)
      and (access.unit_id = target_unit_id or access.include_children)
  );
$$;

create or replace function private.is_person_self(target_person_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.people person
    where person.id = target_person_id
      and person.auth_user_id = (select auth.uid())
      and person.status <> 'rejected'
  );
$$;

create or replace function private.can_view_person(target_person_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.people person
    where person.id = target_person_id
      and (
        person.auth_user_id = (select auth.uid())
        or private.has_organization_role(
          person.organization_id,
          array['owner', 'pastor', 'admin', 'secretary']::public.membership_role[]
        )
        or (
          person.unit_id is not null
          and private.can_access_unit(person.organization_id, person.unit_id)
        )
      )
  );
$$;

create or replace function private.can_manage_person(target_person_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.people person
    where person.id = target_person_id
      and (
        private.has_organization_role(
          person.organization_id,
          array['owner', 'pastor', 'admin', 'secretary']::public.membership_role[]
        )
        or (
          person.unit_id is not null
          and private.can_access_unit(
            person.organization_id,
            person.unit_id,
            array['manage', 'admin']::public.unit_access_level[]
          )
        )
      )
  );
$$;

alter table public.people enable row level security;
alter table public.person_addresses enable row level security;
alter table public.emergency_contacts enable row level security;
alter table public.person_consents enable row level security;
alter table public.pastoral_notes enable row level security;

create policy people_select_scope
on public.people for select to authenticated
using (private.can_view_person(people.id));

create policy people_insert_scope
on public.people for insert to authenticated
with check (
  private.has_organization_role(
    people.organization_id,
    array['owner', 'pastor', 'admin', 'secretary']::public.membership_role[]
  )
  or (
    people.unit_id is not null
    and private.can_access_unit(
      people.organization_id,
      people.unit_id,
      array['manage', 'admin']::public.unit_access_level[]
    )
  )
);

create policy people_update_scope
on public.people for update to authenticated
using (private.can_manage_person(people.id))
with check (
  private.has_organization_role(
    people.organization_id,
    array['owner', 'pastor', 'admin', 'secretary']::public.membership_role[]
  )
  or (
    people.unit_id is not null
    and private.can_access_unit(
      people.organization_id,
      people.unit_id,
      array['manage', 'admin']::public.unit_access_level[]
    )
  )
);

create policy people_delete_admin
on public.people for delete to authenticated
using (
  private.has_organization_role(
    people.organization_id,
    array['owner', 'pastor', 'admin']::public.membership_role[]
  )
);

create policy addresses_select_scope
on public.person_addresses for select to authenticated
using (private.can_view_person(person_addresses.person_id));

create policy addresses_insert_scope
on public.person_addresses for insert to authenticated
with check (private.can_manage_person(person_addresses.person_id));

create policy addresses_update_scope
on public.person_addresses for update to authenticated
using (private.can_manage_person(person_addresses.person_id))
with check (private.can_manage_person(person_addresses.person_id));

create policy addresses_delete_scope
on public.person_addresses for delete to authenticated
using (private.can_manage_person(person_addresses.person_id));

create policy emergency_contacts_select_scope
on public.emergency_contacts for select to authenticated
using (private.can_view_person(emergency_contacts.person_id));

create policy emergency_contacts_insert_scope
on public.emergency_contacts for insert to authenticated
with check (private.can_manage_person(emergency_contacts.person_id));

create policy emergency_contacts_update_scope
on public.emergency_contacts for update to authenticated
using (private.can_manage_person(emergency_contacts.person_id))
with check (private.can_manage_person(emergency_contacts.person_id));

create policy emergency_contacts_delete_scope
on public.emergency_contacts for delete to authenticated
using (private.can_manage_person(emergency_contacts.person_id));

create policy person_consents_select_scope
on public.person_consents for select to authenticated
using (private.can_view_person(person_consents.person_id));

create policy person_consents_insert_scope
on public.person_consents for insert to authenticated
with check (
  private.can_manage_person(person_consents.person_id)
  or private.is_person_self(person_consents.person_id)
);

create policy person_consents_update_scope
on public.person_consents for update to authenticated
using (
  private.can_manage_person(person_consents.person_id)
  or private.is_person_self(person_consents.person_id)
)
with check (
  private.can_manage_person(person_consents.person_id)
  or private.is_person_self(person_consents.person_id)
);

create policy pastoral_notes_select_pastoral
on public.pastoral_notes for select to authenticated
using (
  private.has_organization_role(
    pastoral_notes.organization_id,
    array['owner', 'pastor']::public.membership_role[]
  )
);

create policy pastoral_notes_insert_pastoral
on public.pastoral_notes for insert to authenticated
with check (
  author_user_id = (select auth.uid())
  and private.has_organization_role(
    pastoral_notes.organization_id,
    array['owner', 'pastor']::public.membership_role[]
  )
);

create policy pastoral_notes_update_pastoral
on public.pastoral_notes for update to authenticated
using (
  author_user_id = (select auth.uid())
  and private.has_organization_role(
    pastoral_notes.organization_id,
    array['owner', 'pastor']::public.membership_role[]
  )
)
with check (
  author_user_id = (select auth.uid())
  and private.has_organization_role(
    pastoral_notes.organization_id,
    array['owner', 'pastor']::public.membership_role[]
  )
);

create policy pastoral_notes_delete_pastoral
on public.pastoral_notes for delete to authenticated
using (
  author_user_id = (select auth.uid())
  and private.has_organization_role(
    pastoral_notes.organization_id,
    array['owner', 'pastor']::public.membership_role[]
  )
);

grant select, insert, update, delete on public.people to authenticated;
grant select, insert, update, delete on public.person_addresses to authenticated;
grant select, insert, update, delete on public.emergency_contacts to authenticated;
grant select, insert, update on public.person_consents to authenticated;
grant select, insert, update, delete on public.pastoral_notes to authenticated;

revoke all on public.people from anon;
revoke all on public.person_addresses from anon;
revoke all on public.emergency_contacts from anon;
revoke all on public.person_consents from anon;
revoke all on public.pastoral_notes from anon;

revoke all on function private.can_access_unit(uuid, uuid, public.unit_access_level[]) from public, anon;
revoke all on function private.is_person_self(uuid) from public, anon;
revoke all on function private.can_view_person(uuid) from public, anon;
revoke all on function private.can_manage_person(uuid) from public, anon;
grant execute on function private.can_access_unit(uuid, uuid, public.unit_access_level[]) to authenticated;
grant execute on function private.is_person_self(uuid) to authenticated;
grant execute on function private.can_view_person(uuid) to authenticated;
grant execute on function private.can_manage_person(uuid) to authenticated;
