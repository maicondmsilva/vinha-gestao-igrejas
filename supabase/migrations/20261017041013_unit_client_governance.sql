set local check_function_bodies=on;
set local lock_timeout='5s';
set local statement_timeout='30s';

-- Preserve RLS and trusted service procedures; restrict direct client writes.
revoke delete on public.organization_units from public,anon,authenticated;
create function private.guard_unit_client_fields()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if current_user<>'authenticated' then return new; end if;
 if tg_op='UPDATE' and new.organization_id is distinct from old.organization_id then
  raise exception 'unit_organization_is_immutable' using errcode='23514';
 end if;
 perform 1 from public.organizations where id=new.organization_id and status in ('active','trial') for update;
 if not found then raise exception 'unit_organization_unavailable' using errcode='42501'; end if;
 if tg_op='INSERT' then
  if new.created_at is distinct from transaction_timestamp() then
   raise exception 'unit_original_date_denied' using errcode='42501';
  end if;
  if new.unit_type='headquarters' and exists(select 1 from public.organization_units where organization_id=new.organization_id and unit_type='headquarters') then
   raise exception 'unit_headquarters_exists' using errcode='42501';
  end if;
 else
  if (to_jsonb(new)-array['parent_unit_id','name','unit_type','status','address','updated_at','legal_name','tax_id','pastor_name','email','phone','financial_autonomy','communication_autonomy','branding_autonomy'])
   is distinct from
   (to_jsonb(old)-array['parent_unit_id','name','unit_type','status','address','updated_at','legal_name','tax_id','pastor_name','email','phone','financial_autonomy','communication_autonomy','branding_autonomy']) then
   raise exception 'unit_identity_fields_immutable' using errcode='42501';
  end if;
  if new.unit_type is distinct from old.unit_type and (new.unit_type='headquarters' or old.unit_type='headquarters') then
   raise exception 'unit_headquarters_classification_immutable' using errcode='42501';
  end if;
 end if;
 if new.unit_type='headquarters' and new.parent_unit_id is not null then
  raise exception 'unit_headquarters_parent_denied' using errcode='42501';
 end if;
 new.updated_at:=transaction_timestamp();
 return new;
end $$;
revoke all on function private.guard_unit_client_fields() from public,anon,authenticated,service_role;
-- Run after unit_hierarchy_guard so existing cycle/foreign-ministry failures keep their contract.
create trigger unit_write_fields_guard before insert or update on public.organization_units
for each row execute function private.guard_unit_client_fields();
