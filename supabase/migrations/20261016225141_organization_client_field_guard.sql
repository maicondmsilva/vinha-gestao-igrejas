set local check_function_bodies=on;
set local lock_timeout='5s';
set local statement_timeout='30s';

-- Keep row authorization in RLS; this invoker trigger only narrows client fields.
-- Trusted provisioning/subscription RPCs run as their owner and remain separate.
create function private.guard_organization_client_fields()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if current_user<>'authenticated' then return new; end if;
 if tg_op='INSERT' then
  if auth.uid() is null or new.bootstrap_user_id is distinct from auth.uid()
   or new.status<>'trial' or new.created_at is distinct from transaction_timestamp() then
   raise exception 'organization_bootstrap_fields_denied' using errcode='42501';
  end if;
 else
  -- Deny new administrative columns by default, not only today's known fields.
  if (to_jsonb(new)-array['name','legal_name','tax_id','primary_color','app_name','senior_pastor_name','accent_color','updated_at'])
   is distinct from
   (to_jsonb(old)-array['name','legal_name','tax_id','primary_color','app_name','senior_pastor_name','accent_color','updated_at']) then
   raise exception 'organization_admin_fields_immutable' using errcode='42501';
  end if;
  if old.status not in ('active','trial') then
   raise exception 'organization_configuration_unavailable' using errcode='42501';
  end if;
 end if;
 new.updated_at:=transaction_timestamp();
 return new;
end $$;
revoke all on function private.guard_organization_client_fields() from public,anon,authenticated,service_role;
create trigger organizations_client_fields_guard before insert or update on public.organizations
for each row execute function private.guard_organization_client_fields();
