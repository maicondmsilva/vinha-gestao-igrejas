create table public.saas_plans (
  id text primary key,
  code text not null unique,
  name text not null,
  description text,
  base_price_cents integer not null default 0 check (base_price_cents >= 0),
  billing_cycle text not null default 'monthly' check (billing_cycle in ('monthly','yearly')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.saas_module_catalog (
  code text primary key,
  name text not null,
  description text,
  monthly_price_cents integer not null default 0 check (monthly_price_cents >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.saas_plan_modules (
  plan_id text not null references public.saas_plans(id) on delete cascade,
  module_code text not null references public.saas_module_catalog(code) on delete restrict,
  included boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(plan_id,module_code)
);
create index idx_saas_plan_modules_code on public.saas_plan_modules(module_code);
create table public.saas_subscriptions (
  id uuid primary key default extensions.gen_random_uuid(),
  organization_id uuid not null unique references public.organizations(id) on delete cascade,
  plan_id text not null references public.saas_plans(id) on delete restrict,
  status text not null default 'trialing' check (status in ('trialing','active','past_due','suspended','cancelled')),
  app_addon boolean not null default false,
  trial_ends_at timestamptz,
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_saas_subscriptions_plan on public.saas_subscriptions(plan_id);
create table public.saas_subscription_modules (
  subscription_id uuid not null references public.saas_subscriptions(id) on delete cascade,
  module_code text not null references public.saas_module_catalog(code) on delete restrict,
  enabled boolean not null default true,
  limit_value integer,
  created_at timestamptz not null default now(),
  primary key(subscription_id,module_code)
);
create index idx_saas_subscription_modules_code on public.saas_subscription_modules(module_code);
create table public.saas_promotions (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique,
  name text not null,
  discount_type text not null check (discount_type in ('percent','fixed')),
  discount_value integer not null check (discount_value > 0),
  starts_at timestamptz,
  ends_at timestamptz,
  max_redemptions integer check (max_redemptions is null or max_redemptions > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_saas_promotions_active_period on public.saas_promotions(active,starts_at,ends_at);
create table public.saas_subscription_discounts (
  subscription_id uuid primary key references public.saas_subscriptions(id) on delete cascade,
  promotion_id uuid references public.saas_promotions(id) on delete set null,
  custom_percent integer not null default 0 check (custom_percent between 0 and 100),
  custom_amount_cents integer not null default 0 check (custom_amount_cents >= 0),
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_saas_subscription_discounts_promotion on public.saas_subscription_discounts(promotion_id);

alter table public.saas_plans enable row level security;
alter table public.saas_module_catalog enable row level security;
alter table public.saas_plan_modules enable row level security;
alter table public.saas_subscriptions enable row level security;
alter table public.saas_subscription_modules enable row level security;
alter table public.saas_promotions enable row level security;
alter table public.saas_subscription_discounts enable row level security;

create policy saas_catalog_read_operator on public.saas_plans for select to authenticated using (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]));
create policy saas_catalog_write_operator on public.saas_plans for all to authenticated using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])) with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_modules_read_operator on public.saas_module_catalog for select to authenticated using (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]));
create policy saas_modules_write_operator on public.saas_module_catalog for all to authenticated using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])) with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_plan_modules_read_operator on public.saas_plan_modules for select to authenticated using (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]));
create policy saas_plan_modules_write_operator on public.saas_plan_modules for all to authenticated using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])) with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_subscriptions_operator on public.saas_subscriptions for all to authenticated using (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[])) with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_subscription_modules_operator on public.saas_subscription_modules for all to authenticated using (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[])) with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_promotions_read_operator on public.saas_promotions for select to authenticated using (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]));
create policy saas_promotions_write_operator on public.saas_promotions for all to authenticated using (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[])) with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));
create policy saas_discounts_operator on public.saas_subscription_discounts for all to authenticated using (private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[])) with check (private.has_aal2() and private.is_platform_operator(array['owner','admin']::public.platform_operator_role[]));

grant select,insert,update,delete on public.saas_plans,public.saas_module_catalog,public.saas_plan_modules,public.saas_subscriptions,public.saas_subscription_modules,public.saas_promotions,public.saas_subscription_discounts to authenticated;
revoke all on public.saas_plans,public.saas_module_catalog,public.saas_plan_modules,public.saas_subscriptions,public.saas_subscription_modules,public.saas_promotions,public.saas_subscription_discounts from anon;

insert into public.saas_plans(id,code,name,description,base_price_cents) values
('plan-essential','essential','Essencial','Membresia, unidades e comunicação básica',14900),
('plan-management','management','Gestão','Operação integrada da igreja e seus ministérios',29900),
('plan-complete','complete','Completo','Todos os módulos e recursos avançados',49900);
insert into public.saas_module_catalog(code,name,description,monthly_price_cents) values
('people','Membresia','Cadastro, famílias e jornada do membro',4900),('finance','Financeiro','Tesouraria, conciliação e contabilidade',6900),('cells','Células','Células, grupos e acompanhamento',3900),('kids','Kids','Check-in, responsáveis e segurança',4900),('events','Eventos','Eventos, inscrições e tickets',5900),('scales','Escalas','Escalas integradas de ministérios',3900),('worship','Louvor','Repertório, cifras e planejamento',4900),('communication','Comunicação','Canais, chat e notificações',3900),('broadcasts','Transmissões','Lives, audiência e moderação',5900),('reports','Relatórios','Indicadores e exportações',2900),('terms','Termos e consentimentos','Documentos, aceite e auditoria',2900),('custom_app','Aplicativo personalizado','Aplicativo próprio publicado nas lojas',9900);
insert into public.saas_plan_modules(plan_id,module_code)
select 'plan-essential',code from public.saas_module_catalog where code in ('people','communication','terms');
insert into public.saas_plan_modules(plan_id,module_code)
select 'plan-management',code from public.saas_module_catalog where code in ('people','finance','cells','kids','events','scales','communication','reports','terms');
insert into public.saas_plan_modules(plan_id,module_code)
select 'plan-complete',code from public.saas_module_catalog where code <> 'custom_app';
