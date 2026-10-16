-- Generated from the tested isolated database; preserve invoker privileges and RLS.
SET local check_function_bodies = on;

CREATE OR REPLACE FUNCTION public.save_person_record (
  p_organization uuid,
  p_unit         uuid,
  p_person       uuid,
  p_data         jsonb
)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY INVOKER
  SET search_path TO ''
  AS $function$
declare
 v_person public.people%rowtype;
 v_address public.person_addresses%rowtype;
 v_contact public.emergency_contacts%rowtype;
 v_columns jsonb:='{}'; v_address_columns jsonb:='{}'; v_key text; v_value jsonb; v_column text;
 v_core_map constant jsonb:='{"name":"full_name","birthDate":"birth_date","gender":"gender","maritalStatus":"marital_status","cpf":"cpf","email":"email","phone":"phone","status":"journey_status","group":"group_name","firstVisit":"first_visit_at","joined":"joined_at","baptismDate":"baptism_date"}';
 v_address_map constant jsonb:='{"address":"street","number":"number","extra":"complement","district":"district","city":"city","state":"state","zip":"postal_code"}';
 v_consent_map constant jsonb:='{"privacy":"privacy","imageConsent":"image","messages":"messages"}';
 v_allowed constant text[]:=array['name','birthDate','gender','maritalStatus','cpf','email','phone','status','group','firstVisit','joined','baptized','baptismDate' ,'tags','address','number','extra','district','city','state','zip','emergencyName','emergencyPhone','notes','privacy','imageConsent','messages'];
 v_rows integer; v_last boolean; v_note text; v_create boolean:=p_person is null;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if not private.has_organization_role(p_organization,array['owner','pastor','admin','secretary','leader']::public.membership_role[]) then
  raise exception 'person_write_denied' using errcode='42501';
 end if;
 if not public.unit_module_enabled(p_organization,'people') then raise exception 'module_not_enabled' using errcode='42501'; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>65536 then
  raise exception 'invalid_person_payload' using errcode='22023';
 end if;
 for v_key,v_value in select * from jsonb_each(p_data) loop
  if not v_key=any(v_allowed) then raise exception 'unknown_person_field' using errcode='22023'; end if;
  if v_consent_map ? v_key then
   if jsonb_typeof(v_value)<>'boolean' then raise exception 'invalid_consent_value' using errcode='22023'; end if;
  elsif jsonb_typeof(v_value) not in ('string','null') then
   raise exception 'invalid_person_field_type' using errcode='22023';
  end if;
  if v_core_map ? v_key then
   v_column:=v_core_map->>v_key;
   v_columns:=v_columns||jsonb_build_object(v_column,nullif(trim(p_data->>v_key),''));
  elsif v_address_map ? v_key then
   v_address_columns:=v_address_columns||jsonb_build_object(v_address_map->>v_key,nullif(trim(p_data->>v_key),''));
  end if;
 end loop;
 if v_create then
  if p_unit is null then raise exception 'unit_required' using errcode='22023'; end if;
  v_person.id:=extensions.gen_random_uuid();v_person.organization_id:=p_organization;
  v_person.unit_id:=p_unit;v_person.journey_status:='Visitante';v_person.baptized:=false;
  v_person.tags:='{}';v_person.app_role:='member';v_person.status:='active';v_person.joined_at:=now();
 else
  select * into v_person from public.people where id=p_person and organization_id=p_organization for update;
  if not found then raise exception 'person_not_found' using errcode='P0002'; end if;
  if not private.can_manage_person(p_person) then raise exception 'person_write_denied' using errcode='42501'; end if;
  if p_unit is not null then v_person.unit_id:=p_unit; end if;
 end if;
 if v_person.unit_id is not null and not private.can_access_unit(p_organization,v_person.unit_id,array['manage','admin']::public.unit_access_level[]) then
  raise exception 'unit_write_denied' using errcode='42501';
 end if;
 if p_data ? 'baptized' then
  if coalesce(p_data->>'baptized','') not in ('Sim','Não','Não informado','') then raise exception 'invalid_baptism_value' using errcode='22023'; end if;
  v_columns:=v_columns||jsonb_build_object('baptized',p_data->>'baptized'='Sim');
 end if;
 if p_data ? 'tags' then
  v_columns:=v_columns||jsonb_build_object('tags',coalesce((
   select jsonb_agg(trim(t)) from unnest(string_to_array(p_data->>'tags',',')) t where trim(t)<>''
  ),'[]'::jsonb));
 end if;
 -- Date-only fields represent midnight UTC, independent of the caller's timezone.
 if nullif(p_data->>'firstVisit','') is not null then v_columns:=v_columns||jsonb_build_object('first_visit_at',((p_data->>'firstVisit')::date::timestamp at time zone 'UTC')); end if;
 if nullif(p_data->>'joined','') is not null then v_columns:=v_columns||jsonb_build_object('joined_at',((p_data->>'joined')::date::timestamp at time zone 'UTC')); end if;
 v_person:=jsonb_populate_record(v_person,v_columns);
 if v_create then
  insert into public.people(id,organization_id,unit_id,full_name,birth_date,gender,marital_status,cpf,email,phone,journey_status,group_name,first_visit_at,joined_at,baptized,baptism_date,tags,app_role,status)
  values(v_person.id,p_organization,v_person.unit_id,v_person.full_name,v_person.birth_date,v_person.gender,v_person.marital_status,v_person.cpf,v_person.email,v_person.phone,v_person.journey_status,v_person.group_name,v_person.first_visit_at,v_person.joined_at,v_person.baptized,v_person.baptism_date,v_person.tags,v_person.app_role,'active');
 else
  update public.people set unit_id=v_person.unit_id,full_name=v_person.full_name,birth_date=v_person.birth_date,
   gender=v_person.gender,marital_status=v_person.marital_status,cpf=v_person.cpf,email=v_person.email,phone=v_person.phone,
   journey_status=v_person.journey_status,group_name=v_person.group_name,first_visit_at=v_person.first_visit_at,
   joined_at=v_person.joined_at,baptized=v_person.baptized,baptism_date=v_person.baptism_date,tags=v_person.tags,app_role=v_person.app_role
  where id=v_person.id and organization_id=p_organization;
  get diagnostics v_rows=row_count;
  if v_rows<>1 then raise exception 'person_not_found' using errcode='P0002'; end if;
 end if;
 if v_address_columns<>'{}'::jsonb then
  select * into v_address from public.person_addresses where person_id=v_person.id and organization_id=p_organization for update;
  v_address:=jsonb_populate_record(v_address,v_address_columns);
  insert into public.person_addresses(organization_id,person_id,postal_code,street,number,complement,district,city,state)
  values(p_organization,v_person.id,v_address.postal_code,v_address.street,v_address.number,v_address.complement,v_address.district,v_address.city,v_address.state)
  on conflict(organization_id,person_id) do update set postal_code=excluded.postal_code,street=excluded.street,
   number=excluded.number,complement=excluded.complement,district=excluded.district,city=excluded.city,state=excluded.state;
 end if;
 -- The flat form edits the oldest contact; additional contacts are preserved.
 if p_data ?| array['emergencyName','emergencyPhone'] then
  select * into v_contact from public.emergency_contacts where person_id=v_person.id and organization_id=p_organization order by created_at,id limit 1 for update;
  if p_data ? 'emergencyName' then v_contact.name:=nullif(trim(p_data->>'emergencyName'),''); end if;
  if p_data ? 'emergencyPhone' then v_contact.phone:=nullif(trim(p_data->>'emergencyPhone'),''); end if;
  if v_contact.name is null and v_contact.phone is null then
   if v_contact.id is not null then delete from public.emergency_contacts where id=v_contact.id and organization_id=p_organization; end if;
  elsif v_contact.name is null or v_contact.phone is null then raise exception 'incomplete_emergency_contact' using errcode='22023';
  elsif v_contact.id is null then
   insert into public.emergency_contacts(organization_id,person_id,name,phone) values(p_organization,v_person.id,v_contact.name,v_contact.phone);
  else
   update public.emergency_contacts set name=v_contact.name,phone=v_contact.phone where id=v_contact.id and organization_id=p_organization;
  end if;
 end if;
 for v_key,v_value in select * from jsonb_each(v_consent_map) loop
  if p_data ? v_key then
   select granted into v_last from public.person_consents where person_id=v_person.id and organization_id=p_organization
    and consent_type=v_consent_map->>v_key order by created_at desc,id desc limit 1;
   if not found or v_last is distinct from (p_data->>v_key)::boolean then
    insert into public.person_consents(organization_id,person_id,consent_type,granted,source,acceptance_snapshot,granted_at,revoked_at,created_at)
    values(p_organization,v_person.id,v_consent_map->>v_key,(p_data->>v_key)::boolean,'admin',
     jsonb_build_object('recorded_by_user_id',auth.uid(),'record_type','administrative_record','verified_member_acceptance',false),
     case when (p_data->>v_key)::boolean then clock_timestamp() end,
     case when not (p_data->>v_key)::boolean then clock_timestamp() end,clock_timestamp());
   end if;
  end if;
 end loop;
 if nullif(trim(p_data->>'notes'),'') is not null then
  if not private.has_organization_role(p_organization,array['owner','pastor']::public.membership_role[]) then
   raise exception 'pastoral_note_denied' using errcode='42501';
  end if;
  select content into v_note from public.pastoral_notes where person_id=v_person.id and organization_id=p_organization order by created_at desc,id desc limit 1;
  if v_note is distinct from trim(p_data->>'notes') then
   insert into public.pastoral_notes(organization_id,person_id,author_user_id,content,created_at)
   values(p_organization,v_person.id,auth.uid(),trim(p_data->>'notes'),clock_timestamp());
  end if;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_organization,auth.uid(),case when v_create then 'person.created' else 'person.updated' end,'person',v_person.id::text,
  jsonb_build_object('atomic',true,'fields',(select jsonb_agg(k) from jsonb_object_keys(p_data) k)));
 return v_person.id;
end;
$function$;

REVOKE ALL ON FUNCTION "public"."save_person_record"(uuid, uuid, uuid, jsonb) FROM PUBLIC, "anon";

GRANT EXECUTE ON FUNCTION "public"."save_person_record"(uuid, uuid, uuid, jsonb) TO "authenticated";

