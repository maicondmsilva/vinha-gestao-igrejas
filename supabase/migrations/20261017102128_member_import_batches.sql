-- Bounded imports retain the existing invoker transaction and all people RLS.
set local check_function_bodies=on;
set local lock_timeout='5s';
set local statement_timeout='30s';

create table public.member_import_receipts(
 id uuid primary key,
 organization_id uuid not null references public.organizations(id),
 unit_id uuid not null,
 created_by uuid not null references auth.users(id),
 file_name text not null check(char_length(file_name) between 1 and 180),
 fingerprint text not null,
 result jsonb not null,
 created_at timestamptz not null default clock_timestamp(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
alter table public.member_import_receipts enable row level security;
revoke all on public.member_import_receipts from public,anon,authenticated;
grant select on public.member_import_receipts to authenticated;
create policy member_import_receipts_own_read on public.member_import_receipts for select to authenticated using(
 created_by=(select auth.uid()) and private.has_organization_role(organization_id,array['owner','pastor','admin','secretary','leader']::public.membership_role[])
 and private.can_access_unit(organization_id,unit_id,array['manage','admin']::public.unit_access_level[])
);
create index member_import_receipts_owner_recent on public.member_import_receipts(organization_id,created_by,created_at desc);
create index people_import_cpf_lookup on public.people(organization_id,(regexp_replace(cpf,'[^0-9]','','g'))) where cpf is not null;
create index people_page_order on public.people(organization_id,created_at desc,id desc);

create function private.member_import_scope(p_organization uuid,p_unit uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null
 and private.has_organization_role(p_organization,array['owner','pastor','admin','secretary','leader']::public.membership_role[])
 and private.can_access_unit(p_organization,p_unit,array['manage','admin']::public.unit_access_level[])
 and private.target_unit_module_enabled(p_organization,p_unit,'people')
 and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id
 where u.id=p_unit and u.organization_id=p_organization and u.status='active' and o.status in('active','trial'));
$$;

-- Internal metadata persistence needs the owner privilege because clients have no
-- INSERT/UPDATE/DELETE grant on receipts. This helper is outside the exposed schema,
-- checks the current identity/unit/contract and never reads or writes member fields.
create function private.member_import_receipt(p_organization uuid,p_unit uuid,p_request uuid,p_fingerprint text,p_file text,p_result jsonb default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare receipt public.member_import_receipts%rowtype;
begin
 if not private.member_import_scope(p_organization,p_unit) then raise exception 'member_import_denied' using errcode='42501';end if;
 if p_request is null or p_fingerprint is null or length(p_fingerprint)<>64 then raise exception 'invalid_import_request' using errcode='22023';end if;
 -- Serializes import identity checks for an organization, including retries.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('member-import:'||p_organization::text,0));
 select * into receipt from public.member_import_receipts where id=p_request;
 if found then
  if receipt.organization_id<>p_organization or receipt.unit_id<>p_unit or receipt.created_by<>auth.uid() or receipt.fingerprint<>p_fingerprint then
   raise exception 'import_idempotency_conflict' using errcode='22023';
  end if;
  return receipt.result;
 end if;
 if p_result is not null then
  if jsonb_typeof(p_result)<>'object' or octet_length(p_result::text)>4096
   or exists(select 1 from jsonb_object_keys(p_result) k where k<>all(array['jobId','total','imported','skipped','invalid','replayed']))
   or not (p_result ?& array['total','imported','skipped','invalid','jobId'])
   or (p_result->>'jobId')::uuid<>p_request
   or (p_result->>'total')::int not between 1 and 100
   or (p_result->>'imported')::int<0 or (p_result->>'skipped')::int<0 or (p_result->>'invalid')::int<0
   or (p_result->>'total')::int<>(p_result->>'imported')::int+(p_result->>'skipped')::int+(p_result->>'invalid')::int then
   raise exception 'invalid_import_receipt' using errcode='22023';
  end if;
  insert into public.member_import_receipts(id,organization_id,unit_id,created_by,file_name,fingerprint,result)
  values(p_request,p_organization,p_unit,auth.uid(),left(coalesce(nullif(trim(p_file),''),'membros.csv'),180),p_fingerprint,p_result);
 end if;
 return p_result;
end;$$;

-- Internal boolean lookup avoids reading or disclosing records from another unit.
-- A duplicate is never overwritten or linked to an app identity by this importer.
create function private.member_import_duplicate(p_organization uuid,p_unit uuid,p_email text,p_cpf text) returns boolean
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.member_import_scope(p_organization,p_unit) then raise exception 'member_import_denied' using errcode='42501';end if;
 return exists(select 1 from public.people p where p.organization_id=p_organization and(
  (nullif(p_email,'') is not null and lower(p.email)=p_email)
  or (nullif(p_cpf,'') is not null and regexp_replace(p.cpf,'[^0-9]','','g')=p_cpf)));
end;$$;

create function public.import_member_batch(p_organization uuid,p_unit uuid,p_rows jsonb,p_mode text,p_request uuid default null,p_file text default 'membros.csv')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 item jsonb; row_data jsonb; output_rows jsonb:='[]'; errors jsonb;
 seen_email text[]:='{}';seen_cpf text[]:='{}'; email_value text;cpf_value text;name_value text;birth_value text;status_value text;
 total_count integer;invalid_count integer:=0;skipped_count integer:=0;imported_count integer:=0;line_number integer:=1;
 fingerprint text;previous jsonb;result jsonb;unit_name text;key_name text;sum_value integer;digit_value integer;i integer;n integer;cpf_ok boolean;
begin
 if not private.member_import_scope(p_organization,p_unit) then raise exception 'member_import_denied' using errcode='42501';end if;
 if p_mode is null or p_mode not in('preview','commit') or p_rows is null or jsonb_typeof(p_rows)<>'array' or octet_length(p_rows::text)>524288 then
  raise exception 'invalid_import_payload' using errcode='22023';end if;
 total_count:=jsonb_array_length(p_rows);
 if total_count<1 or total_count>(case when p_mode='commit' then 100 else 500 end) then raise exception 'invalid_import_size' using errcode='22023';end if;
 select name into unit_name from public.organization_units where id=p_unit and organization_id=p_organization;
 fingerprint:=encode(extensions.digest(p_rows::text||':'||p_unit::text,'sha256'),'hex');
 if p_mode='commit' then
  previous:=private.member_import_receipt(p_organization,p_unit,p_request,fingerprint,p_file);
  if previous is not null then return previous||jsonb_build_object('replayed',true);end if;
 end if;
 for item in select value from jsonb_array_elements(p_rows) loop
  line_number:=line_number+1;errors:='[]';
  if jsonb_typeof(item)<>'object' then item:='{}';errors:=errors||'"Colunas inválidas"'::jsonb;end if;
  for key_name in select jsonb_object_keys(item) loop
   if key_name<>all(array['nome','email','telefone','cpf','nascimento','status','campus','grupo']) or jsonb_typeof(item->key_name)<>'string' then errors:=errors||'"Colunas ou tipos inválidos"'::jsonb;end if;
  end loop;
  name_value:=trim(coalesce(item->>'nome',''));email_value:=lower(trim(coalesce(item->>'email','')));
  cpf_value:=regexp_replace(coalesce(item->>'cpf',''),'[.\-\s]','','g');birth_value:=trim(coalesce(item->>'nascimento',''));
  status_value:=case lower(trim(coalesce(nullif(item->>'status',''),'visitante'))) when 'member' then 'Membro' when 'membro' then 'Membro' when 'visitor' then 'Visitante' when 'visitante' then 'Visitante' when 'integration' then 'Em integração' when 'em integração' then 'Em integração' else '' end;
  if char_length(name_value) not between 2 and 160 then errors:=errors||'"Nome inválido"'::jsonb;end if;
  if email_value<>'' and (email_value !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' or length(email_value)>254) then errors:=errors||'"E-mail inválido"'::jsonb;end if;
  if email_value<>'' and email_value=any(seen_email) then errors:=errors||'"E-mail repetido na planilha"'::jsonb;end if;
  if cpf_value<>'' then
   cpf_ok:=cpf_value~'^[0-9]{11}$' and cpf_value!~'^([0-9])\1{10}$';
   if cpf_ok then
    for n in 9..10 loop
     sum_value:=0;for i in 1..n loop sum_value:=sum_value+substr(cpf_value,i,1)::integer*(n+2-i);end loop;
     digit_value:=mod(sum_value*10,11);if digit_value=10 then digit_value:=0;end if;
     if digit_value<>substr(cpf_value,n+1,1)::integer then cpf_ok:=false;end if;
    end loop;
   end if;
   if not cpf_ok then errors:=errors||'"CPF inválido"'::jsonb;end if;
   if cpf_value=any(seen_cpf) then errors:=errors||'"CPF repetido na planilha"'::jsonb;end if;
  end if;
  if birth_value<>'' then
   begin
    if birth_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or birth_value::date>current_date then errors:=errors||'"Data de nascimento inválida"'::jsonb;end if;
   exception when invalid_datetime_format or datetime_field_overflow then errors:=errors||'"Data de nascimento inválida"'::jsonb;end;
  end if;
  if status_value='' then errors:=errors||'"Status inválido"'::jsonb;end if;
  if char_length(coalesce(item->>'telefone',''))>30 or char_length(coalesce(item->>'grupo',''))>160 then errors:=errors||'"Campo muito longo"'::jsonb;end if;
  if nullif(trim(item->>'campus'),'') is not null and lower(trim(item->>'campus'))<>lower(unit_name) and item->>'campus'<>p_unit::text then errors:=errors||'"Unidade diferente da selecionada"'::jsonb;end if;
  if email_value<>'' then seen_email:=array_append(seen_email,email_value);end if;
  if cpf_value<>'' then seen_cpf:=array_append(seen_cpf,cpf_value);end if;
  row_data:=jsonb_build_object('nome',name_value,'email',email_value,'cpf',cpf_value,'nascimento',birth_value,'status',status_value,'telefone',trim(coalesce(item->>'telefone','')),'grupo',trim(coalesce(item->>'grupo','')),'campus',unit_name);
  if jsonb_array_length(errors)>0 then invalid_count:=invalid_count+1;
  elsif private.member_import_duplicate(p_organization,p_unit,email_value,cpf_value) then
   skipped_count:=skipped_count+1;
   output_rows:=output_rows||jsonb_build_array(jsonb_build_object('line',line_number,'row',row_data,'errors',errors,'duplicate',true));continue;
  elsif p_mode='commit' then
   begin
    perform public.save_person_record(p_organization,p_unit,null,jsonb_build_object('name',name_value,'email',email_value,'phone',row_data->>'telefone','cpf',cpf_value,'birthDate',birth_value,'status',status_value,'group',row_data->>'grupo'));
    imported_count:=imported_count+1;
   exception when unique_violation then
    -- A concurrent normal save may win the unique email check. Never overwrite it.
    skipped_count:=skipped_count+1;
   end;
  end if;
  output_rows:=output_rows||jsonb_build_array(jsonb_build_object('line',line_number,'row',row_data,'errors',errors,'duplicate',false));
 end loop;
 if p_mode='preview' then return jsonb_build_object('total',total_count,'valid',total_count-invalid_count-skipped_count,'invalid',invalid_count,'skipped',skipped_count,'rows',output_rows);end if;
 result:=jsonb_build_object('jobId',p_request,'total',total_count,'imported',imported_count,'skipped',skipped_count,'invalid',invalid_count,'replayed',false);
 -- Receipt and append-only audit are in the same transaction as all member writes.
 perform private.member_import_receipt(p_organization,p_unit,p_request,fingerprint,p_file,result);
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_organization,auth.uid(),'people.imported','member_import_batch',p_request::text,jsonb_build_object('unit_id',p_unit,'total',total_count,'imported',imported_count,'skipped',skipped_count,'invalid',invalid_count));
 return result;
end;$$;

revoke all on function private.member_import_scope(uuid,uuid),private.member_import_receipt(uuid,uuid,uuid,text,text,jsonb),private.member_import_duplicate(uuid,uuid,text,text),public.import_member_batch(uuid,uuid,jsonb,text,uuid,text) from public,anon;
grant execute on function private.member_import_scope(uuid,uuid),private.member_import_receipt(uuid,uuid,uuid,text,text,jsonb),private.member_import_duplicate(uuid,uuid,text,text),public.import_member_batch(uuid,uuid,jsonb,text,uuid,text) to authenticated;
comment on table public.member_import_receipts is 'Immutable import metadata only. No raw CSV, CPF, contact information, or app identity is persisted in receipts.';
