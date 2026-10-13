create table public.audit_logs (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  ip_address inet,
  created_at timestamptz not null default now()
);

create index audit_logs_organization_created_idx
  on public.audit_logs (organization_id, created_at desc);
create index audit_logs_entity_idx
  on public.audit_logs (organization_id, entity_type, entity_id);

alter table public.audit_logs enable row level security;

create policy audit_logs_select_leadership
on public.audit_logs for select to authenticated
using (
  private.has_organization_role(
    audit_logs.organization_id,
    array['owner', 'pastor', 'admin']::public.membership_role[]
  )
);

create policy audit_logs_insert_actor
on public.audit_logs for insert to authenticated
with check (
  actor_user_id = (select auth.uid())
  and private.is_organization_member(audit_logs.organization_id)
);

grant select, insert on public.audit_logs to authenticated;
revoke all on public.audit_logs from anon;
