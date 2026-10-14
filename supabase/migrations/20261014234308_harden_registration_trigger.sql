create or replace function private.assign_church_registration_code() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='UPDATE' then
  if new.registration_code is distinct from old.registration_code then raise exception 'registration_code_immutable' using errcode='22023'; end if;
  return new;
 end if;
 if tg_table_name='organization_units' then
  if new.unit_type='headquarters' then
   select registration_code into new.registration_code from public.organizations where id=new.organization_id;
   return new;
  end if;
 end if;
 new.registration_code:=nextval('public.church_registration_code_seq');
 return new;
end $$;
