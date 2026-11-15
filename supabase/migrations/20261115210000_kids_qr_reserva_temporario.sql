-- Kids:
--  · QR Code da reserva: ao reservar, a família recebe um QR (o mesmo para todos os responsáveis da criança).
--    Na recepção, a equipe lê o QR para a entrada e o MESMO QR vale como comprovante na saída
--    (o banco guarda só o hash na presença, como já fazia).
--  · Foto da criança para a equipe (painel e Vinha Equipe), lida só por quem opera o Kids naquela igreja.
--  · Responsável temporário: o responsável autoriza, pelo app, outro membro a buscar a criança por até 30 dias.

alter table private.kids_member_reservations add column if not exists pass_code text check(pass_code is null or pass_code ~ '^[a-f0-9]{64}$');
create unique index if not exists kids_member_reservations_pass on private.kids_member_reservations(pass_code) where pass_code is not null;
alter table private.kids_guardians add column if not exists temporary boolean not null default false;
alter table private.kids_guardians add column if not exists granted_by uuid;

create or replace function private.kids_reservation_pass() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
 if new.status='reserved' and (tg_op='INSERT' or old.status<>'reserved' or new.pass_code is null) then
  new.pass_code:=encode(extensions.gen_random_bytes(32),'hex');
 elsif new.status<>'reserved' then
  new.pass_code:=null;
 end if;
 return new;
end $$;
revoke all on function private.kids_reservation_pass() from public,anon,authenticated;
drop trigger if exists kids_reservation_pass on private.kids_member_reservations;
create trigger kids_reservation_pass before insert or update of status on private.kids_member_reservations for each row execute function private.kids_reservation_pass();
update private.kids_member_reservations set pass_code=encode(extensions.gen_random_bytes(32),'hex') where status='reserved' and pass_code is null;

-- App da família: a lista de reservas traz o QR para quem pode buscar a criança.
do $$ declare d text; n int; begin
 d:=pg_get_functiondef('private.member_family(uuid,uuid,text,uuid,integer,jsonb,integer)'::regprocedure);
 if position('r.pass_code end pass' in d)=0 then
  n:=(length(d)-length(replace(d,'a.status attendance,a.checked_in_at,a.checked_out_at,rm.name room from private.kids_member_reservations r','')))/length('a.status attendance,a.checked_in_at,a.checked_out_at,rm.name room from private.kids_member_reservations r');
  if n<>1 then raise exception 'member_family: reservas não encontradas (%)',n;end if;
  execute replace(d,'a.status attendance,a.checked_in_at,a.checked_out_at,rm.name room from private.kids_member_reservations r',
   'a.status attendance,a.checked_in_at,a.checked_out_at,rm.name room,coalesce(c.photo_path,'''') photo,
    case when r.status=''reserved'' and s.ends_at>clock_timestamp() and (a.status is null or a.status=''present'') and exists(select 1 from private.kids_guardians g2 where g2.profile_id=r.profile_id and g2.person_id=person and g2.status=''approved'' and g2.can_pickup and (g2.valid_until is null or g2.valid_until>=current_date)) then r.pass_code end pass
    from private.kids_member_reservations r');
 end if;
end $$;

-- Recepção: o QR da reserva diz quem é a criança, a sala, quem pode levar/buscar e se ela já entrou.
create or replace function public.kids_pass(p_org uuid, p_unit uuid, p_code text) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare r private.kids_member_reservations; a private.kids_attendance; s private.kids_sessions;
begin
 if coalesce(p_code,'') !~ '^[a-f0-9]{64}$' then raise exception 'kids_invalid' using errcode='22023';end if;
 select * into r from private.kids_member_reservations where pass_code=p_code and organization_id=p_org and unit_id=p_unit;
 if r.id is null then
  -- QR de uma criança que já saiu ou reserva cancelada: não revela nada.
  return jsonb_build_object('found',false);
 end if;
 select * into s from private.kids_sessions where id=r.session_id;
 if not private.kids_op_allowed(p_org,p_unit,r.session_id,'receive',r.group_id) then raise exception 'kids_access_denied' using errcode='42501';end if;
 select * into a from private.kids_attendance where session_id=r.session_id and profile_id=r.profile_id;
 return jsonb_build_object('found',true,'reservation',r.id,'sessionId',r.session_id,'session',s.name,'sessionStatus',s.status,'startsAt',s.starts_at,'groupId',r.group_id,
  'room',(select rm.name from private.kids_session_rooms g join private.kids_rooms rm on rm.id=g.room_id where g.id=r.group_id),
  'profileId',r.profile_id,'child',(select p.full_name from private.kids_profiles k join public.people p on p.id=k.person_id where k.id=r.profile_id),
  'birthDate',(select p.birth_date from private.kids_profiles k join public.people p on p.id=k.person_id where k.id=r.profile_id),
  'photo',(select coalesce(p.photo_path,'') from private.kids_profiles k join public.people p on p.id=k.person_id where k.id=r.profile_id),
  'care',(select left(instructions,400) from private.kids_care where profile_id=r.profile_id),
  'reservedBy',r.person_id,
  'guardians',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'relationship',g.relationship,'temporary',g.temporary,'validUntil',g.valid_until,'photo',coalesce(p.photo_path,'')) order by (p.id=r.person_id) desc,g.temporary,p.full_name)
   from private.kids_guardians g join public.people p on p.id=g.person_id
   where g.profile_id=r.profile_id and g.status='approved' and g.can_pickup and (g.valid_until is null or g.valid_until>=(clock_timestamp() at time zone private.unit_timezone(p_unit))::date)
    and p.status='active' and p.birth_date<=current_date-interval '18 years'),'[]'::jsonb),
  'attendance',case when a.id is null then null else jsonb_build_object('id',a.id,'version',a.version,'status',a.status,'tag',a.tag_number) end);
end $function$;
revoke all on function public.kids_pass(uuid,uuid,text) from public,anon;
grant execute on function public.kids_pass(uuid,uuid,text) to authenticated;

-- Foto da criança para quem opera o Kids nesta igreja (o arquivo é lido pelo servidor, que gera um link temporário).
create or replace function public.kids_child_photo(p_org uuid, p_unit uuid, p_profile uuid) returns text
language sql stable security definer set search_path to '' as $$
 select coalesce(p.photo_path,'') from private.kids_profiles k join public.people p on p.id=k.person_id
 where k.id=p_profile and k.organization_id=p_org and k.unit_id=p_unit and private.kids_op_allowed(p_org,p_unit,null,'read')
$$;
revoke all on function public.kids_child_photo(uuid,uuid,uuid) from public,anon;
grant execute on function public.kids_child_photo(uuid,uuid,uuid) to authenticated;

-- Responsável temporário, autorizado pelo responsável no app (por e-mail ou celular do outro membro).
create or replace function private.member_kids_temporary(p_org uuid, p_action text, p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare uid uuid=auth.uid(); me public.people; k private.kids_profiles; target public.people; v_digits text; v_email text; n int; days int; g private.kids_guardians;
begin
 if uid is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'kids_invalid' using errcode='22023';end if;
 select * into me from public.people where organization_id=p_org and auth_user_id=uid and status='active' order by created_at limit 1;
 select kp.* into k from private.kids_profiles kp join private.kids_guardians mg on mg.profile_id=kp.id
  where kp.id=nullif(p_data->>'profile','')::uuid and kp.organization_id=p_org and mg.person_id=me.id and mg.status='approved' and not mg.temporary
   and (mg.can_edit or mg.can_pickup) and (mg.valid_until is null or mg.valid_until>=current_date);
 if me.id is null or k.id is null then raise exception 'kids_access_denied' using errcode='42501';end if;
 if p_action='list' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',p.full_name,'relationship',x.relationship,'temporary',x.temporary,'validUntil',x.valid_until,'canPickup',x.can_pickup,'me',p.id=me.id) order by x.temporary,p.full_name)
   from private.kids_guardians x join public.people p on p.id=x.person_id
   where x.profile_id=k.id and x.status='approved' and (x.valid_until is null or x.valid_until>=current_date)),'[]'::jsonb));
 elsif p_action='grant' then
  days:=coalesce(nullif(p_data->>'days','')::int,1);
  if days not between 1 and 30 then raise exception 'kids_invalid' using errcode='22023';end if;
  v_email:=lower(btrim(coalesce(p_data->>'contact','')));
  v_digits:=regexp_replace(v_email,'\D','','g');
  if v_email !~ '@' and length(v_digits) not between 10 and 13 then raise exception 'kids_temp_contact' using errcode='22023';end if;
  select count(*) into n from public.people p join public.organization_memberships m on m.user_id=p.auth_user_id and m.organization_id=p.organization_id and m.status='active'
   where p.organization_id=p_org and p.status='active' and p.birth_date<=current_date-interval '18 years'
    and (case when v_email ~ '@' then lower(p.email)=v_email or exists(select 1 from auth.users au where au.id=p.auth_user_id and lower(au.email)=v_email) else regexp_replace(coalesce(p.phone,''),'\D','','g')=v_digits end);
  if n<>1 then raise exception 'kids_temp_not_found' using errcode='22023';end if;
  select p.* into target from public.people p join public.organization_memberships m on m.user_id=p.auth_user_id and m.organization_id=p.organization_id and m.status='active'
   where p.organization_id=p_org and p.status='active' and p.birth_date<=current_date-interval '18 years'
    and (case when v_email ~ '@' then lower(p.email)=v_email or exists(select 1 from auth.users au where au.id=p.auth_user_id and lower(au.email)=v_email) else regexp_replace(coalesce(p.phone,''),'\D','','g')=v_digits end);
  if target.id=me.id then raise exception 'kids_invalid' using errcode='22023';end if;
  select * into g from private.kids_guardians where profile_id=k.id and person_id=target.id for update;
  if g.id is not null and not g.temporary and g.status='approved' then return jsonb_build_object('ok',true,'name',split_part(target.full_name,' ',1),'already',true);end if;
  insert into private.kids_guardians(id,organization_id,unit_id,profile_id,person_id,relationship,verification_note,can_pickup,can_edit,is_emergency,status,approved_by,approved_at,valid_until,created_by,temporary,granted_by)
   values(extensions.gen_random_uuid(),p_org,k.unit_id,k.id,target.id,'Responsável temporário','Autorizado por '||me.full_name||' pelo app',true,false,false,'approved',uid,clock_timestamp(),current_date+days-1,uid,true,me.id)
   on conflict(profile_id,person_id) do update set status='approved',can_pickup=true,can_edit=false,relationship='Responsável temporário',verification_note=excluded.verification_note,
    approved_by=uid,approved_at=clock_timestamp(),valid_until=excluded.valid_until,temporary=true,granted_by=me.id,version=private.kids_guardians.version+1,updated_at=clock_timestamp();
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,uid,'kids.temporary_guardian','kids_profile',k.id::text,jsonb_build_object('person',target.id,'until',current_date+days-1));
  return jsonb_build_object('ok',true,'name',split_part(target.full_name,' ',1),'until',current_date+days-1);
 elsif p_action='revoke' then
  update private.kids_guardians set status='revoked',approved_by=null,approved_at=null,can_pickup=false,version=version+1,updated_at=clock_timestamp()
   where id=nullif(p_data->>'id','')::uuid and profile_id=k.id and temporary;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'kids_invalid' using errcode='22023';
end $function$;
revoke all on function private.member_kids_temporary(uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.member_kids_temporary(p_org uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.member_kids_temporary(p_org,p_action,p_data) $$;
revoke all on function public.member_kids_temporary(uuid,text,jsonb) from public,anon;
grant execute on function public.member_kids_temporary(uuid,text,jsonb) to authenticated;

-- Caixa de notificações do responsável temporário.
do $$ begin
 if to_regprocedure('private.member_inbox_before_kids_temporary(uuid,uuid)') is null then
  alter function private.member_inbox_rows(uuid,uuid) rename to member_inbox_before_kids_temporary;
 end if;
end $$;
create or replace function private.member_inbox_rows(p_org uuid, p_unit uuid)
returns table(message_key text, title text, body text, occurred_at timestamptz, target text, target_id uuid)
language sql stable security definer set search_path to '' as $function$
 select * from (
  select * from private.member_inbox_before_kids_temporary(p_org,p_unit)
  union all
  select 'kids-temp:'||g.id::text||':'||g.version,'Você pode buscar '||split_part(c.full_name,' ',1)||' no Kids',
   coalesce(split_part(b.full_name,' ',1),'O responsável')||' autorizou você até '||to_char(g.valid_until,'DD/MM')||'. Na saída, mostre o QR Code da reserva que aparece na Área Kids.',
   g.approved_at,'kids'::text,g.profile_id
  from private.kids_guardians g join public.people me on me.id=g.person_id join private.kids_profiles k on k.id=g.profile_id join public.people c on c.id=k.person_id left join public.people b on b.id=g.granted_by
  where g.organization_id=p_org and g.temporary and g.status='approved' and g.valid_until>=current_date and me.auth_user_id=auth.uid()
 ) x order by occurred_at desc nulls last, message_key limit 100
$function$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated;
