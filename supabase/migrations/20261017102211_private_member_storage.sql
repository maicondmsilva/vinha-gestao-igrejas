set local check_function_bodies=on;
set local lock_timeout='5s';
set local statement_timeout='30s';

-- New bucket only. No legacy object is moved, deleted or made public.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('member-private','member-private',false,4194304,array['application/pdf','image/png','image/jpeg'])
on conflict(id) do nothing;

create function private.member_file_allowed(p_name text,p_write boolean default false)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare parts text[]:=string_to_array(p_name,'/'); oid uuid; pid uuid;
begin
 if auth.uid() is null or cardinality(parts)<>3
  or parts[1]!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or parts[2]!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or parts[3]!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|png|jpg)$' then return false; end if;
 oid:=parts[1]::uuid;pid:=parts[2]::uuid;
 if p_write then return exists(select 1 from public.people where id=pid and organization_id=oid and private.can_manage_person(id)); end if;
 return exists(select 1 from public.people p where p.id=pid and p.organization_id=oid
  and private.has_organization_role(oid,array['owner','pastor','admin','secretary','leader']::public.membership_role[])
  and private.can_access_unit(oid,p.unit_id));
end $$;
revoke all on function private.member_file_allowed(text,boolean) from public,anon,authenticated,service_role;
grant execute on function private.member_file_allowed(text,boolean) to authenticated;
create policy member_file_read on storage.objects for select to authenticated
using(bucket_id='member-private' and private.member_file_allowed(name,false));
create policy member_file_insert on storage.objects for insert to authenticated
with check(bucket_id='member-private' and private.member_file_allowed(name,true));
-- No update/upsert/delete policy: clients cannot replace/move/purge a document.
