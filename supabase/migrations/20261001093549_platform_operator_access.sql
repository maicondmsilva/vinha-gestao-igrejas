create type public.platform_operator_role as enum ('owner', 'admin', 'support', 'read_only');

create table public.platform_operators (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role public.platform_operator_role not null default 'read_only',
  full_name text not null check (char_length(full_name) between 2 and 120),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index platform_operators_active_role_idx
  on public.platform_operators (active, role);

create trigger platform_operators_set_updated_at
before update on public.platform_operators
for each row execute function public.set_updated_at();

alter table public.platform_operators enable row level security;

create or replace function private.no_platform_operators()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1 from public.platform_operators where active
  );
$$;

create or replace function private.is_platform_operator(allowed_roles public.platform_operator_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_operators operator
    where operator.user_id = (select auth.uid())
      and operator.active
      and operator.role = any(allowed_roles)
  );
$$;

create policy platform_operators_select_self
on public.platform_operators for select to authenticated
using (user_id = (select auth.uid()));

create policy platform_operators_bootstrap_first_owner
on public.platform_operators for insert to authenticated
with check (
  user_id = (select auth.uid())
  and role = 'owner'
  and private.no_platform_operators()
);

create or replace function public.platform_operator_context()
returns table (
  user_id uuid,
  role public.platform_operator_role,
  full_name text,
  active boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select operator.user_id, operator.role, operator.full_name, operator.active
  from public.platform_operators operator
  where operator.user_id = (select auth.uid())
    and operator.active;
$$;

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

  insert into public.platform_operators (user_id, role, full_name)
  values ((select auth.uid()), 'owner', trim(p_full_name));

  return query select * from public.platform_operator_context();
end;
$$;

grant usage on type public.platform_operator_role to authenticated;
grant select, insert on public.platform_operators to authenticated;
revoke update, delete on public.platform_operators from authenticated, anon;
revoke all on function public.platform_operator_context() from public, anon;
revoke all on function public.bootstrap_platform_owner(text) from public, anon;
grant execute on function public.platform_operator_context() to authenticated;
grant execute on function public.bootstrap_platform_owner(text) to authenticated;
grant execute on function private.no_platform_operators() to authenticated;
grant execute on function private.is_platform_operator(public.platform_operator_role[]) to authenticated;
