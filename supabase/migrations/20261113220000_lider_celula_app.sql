-- Células · "Minha célula" no app: o líder (ou quem tem permissão de relatório na célula) cuida do grupo pelo celular.
-- Encontros, presença, visitantes com telefone, observações do líder, indicações, aniversários e materiais.

alter table public.church_cell_meetings add column if not exists leader_notes text;
alter table public.church_cell_visits add column if not exists phone text;
alter table public.church_cell_visits add column if not exists meeting_id uuid references public.church_cell_meetings(id) on delete set null;
do $$ begin
 alter table public.church_cell_meetings drop constraint if exists church_cell_meetings_leader_notes_check;
 alter table public.church_cell_meetings add constraint church_cell_meetings_leader_notes_check check (leader_notes is null or length(leader_notes)<=1000);
 alter table public.church_cell_visits drop constraint if exists church_cell_visits_phone_check;
 alter table public.church_cell_visits add constraint church_cell_visits_phone_check check (phone is null or phone ~ '^[0-9]{8,15}$');
end $$;
create index if not exists cell_visits_meeting_idx on public.church_cell_visits(meeting_id) where meeting_id is not null;

-- Líder cadastrado na célula com conta ativa na igreja (sem precisar de acesso ao painel).
create or replace function private.cell_leader_of(p_org uuid, p_unit uuid, p_cell uuid)
returns boolean language sql stable security definer set search_path to '' as $$
 select auth.uid() is not null
  and exists(select 1 from public.church_cells c join public.people p on p.id=c.leader_person_id and p.organization_id=c.organization_id and p.unit_id=c.unit_id
   where c.id=p_cell and c.organization_id=p_org and c.unit_id=p_unit and c.status='active' and p.status='active' and p.auth_user_id=auth.uid())
  and exists(select 1 from public.organization_memberships m where m.organization_id=p_org and m.user_id=auth.uid() and m.status='active')
  and exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial'))
  and private.unit_module_contracted(p_org,p_unit,'people')
$$;
revoke all on function private.cell_leader_of(uuid,uuid,uuid) from public,anon,authenticated;

create or replace function private.cell_leader_can(p_org uuid, p_unit uuid, p_cell uuid, p_capability text)
returns boolean language sql stable security definer set search_path to '' as $$
 select private.cell_leader_of(p_org,p_unit,p_cell)
  or coalesce(private.cell_plus_cell(p_org,p_unit,p_cell,auth.uid(),p_capability),false)
$$;
revoke all on function private.cell_leader_can(uuid,uuid,uuid,text) from public,anon,authenticated;

create or replace function private.cell_leader_hub(p_org uuid, p_unit uuid, p_cell uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare actor uuid=auth.uid(); today date=(now() at time zone 'America/Sao_Paulo')::date; can_report boolean; result jsonb;
 meeting public.church_cell_meetings; ref private.cell_referrals; ids uuid[]; snapshot uuid[]; v integer; d date; t text; topic text; notes text; x jsonb; n integer=0;
begin
 if actor is null then raise exception 'cell_access_denied' using errcode='42501';end if;
 if p_action is null or p_action not in('mine','overview','meeting','report','referral') or p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>32768 then raise exception 'invalid_cell_leader' using errcode='22023';end if;

 if p_action='mine' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'leader',private.cell_leader_of(p_org,p_unit,c.id)) order by c.name)
   from public.church_cells c where c.organization_id=p_org and c.unit_id=p_unit and c.status='active' and private.cell_leader_can(p_org,p_unit,c.id,'report')),'[]'::jsonb));
 end if;

 if p_cell is null or not exists(select 1 from public.church_cells c where c.id=p_cell and c.organization_id=p_org and c.unit_id=p_unit and c.status='active')
  or not private.cell_leader_can(p_org,p_unit,p_cell,'read') then raise exception 'cell_access_denied' using errcode='42501';end if;
 can_report=private.cell_leader_can(p_org,p_unit,p_cell,'report');

 if p_action='overview' then
  select jsonb_build_object(
   'cell',(select jsonb_build_object('id',c.id,'name',c.name,'day',c.meeting_day,'time',c.meeting_time,'format',c.meeting_format,'location',coalesce(c.location,'')) from public.church_cells c where c.id=p_cell),
   'canReport',can_report,'today',today,
   'people',coalesce((select jsonb_agg(jsonb_build_object('participantId',m.id,'name',p.full_name,
      'phone',case when can_report then coalesce(p.phone,'') else '' end,
      'birthday',case when p.birth_date is null then '' else to_char(p.birth_date,'MM-DD') end,
      'since',m.created_at::date,
      'recent',(select coalesce(jsonb_agg(a.present order by mt.meeting_date desc),'[]'::jsonb) from (select a2.present,a2.meeting_id from public.church_cell_attendance a2 where a2.participant_id=m.id) a
        join lateral (select mt2.meeting_date from public.church_cell_meetings mt2 where mt2.id=a.meeting_id and mt2.status='completed') mt on true
        where a.meeting_id in(select mm.id from public.church_cell_meetings mm where mm.cell_id=p_cell and mm.status='completed' order by mm.meeting_date desc,mm.id desc limit 4)))
     order by p.full_name)
    from public.church_cell_participants m join public.people p on p.id=m.person_id
    where m.cell_id=p_cell and m.status='active' and p.status='active'),'[]'::jsonb),
   'meetings',coalesce((select jsonb_agg(jsonb_build_object('id',mt.id,'topic',mt.topic,'date',mt.meeting_date,'time',mt.meeting_time,'status',mt.status,'version',mt.version,
      'notes',case when can_report then coalesce(mt.leader_notes,'') else '' end,
      'expected',(select count(*) from public.church_cell_attendance a where a.meeting_id=mt.id),
      'present',(select count(*) from public.church_cell_attendance a where a.meeting_id=mt.id and a.present),
      'roster',(select coalesce(jsonb_agg(jsonb_build_object('participantId',a.participant_id,'name',p.full_name,'present',a.present) order by p.full_name),'[]'::jsonb)
        from public.church_cell_attendance a join public.church_cell_participants cp on cp.id=a.participant_id join public.people p on p.id=cp.person_id where a.meeting_id=mt.id),
      'visitors',(select count(*) from public.church_cell_visits v2 where v2.meeting_id=mt.id and v2.status='recorded'))
     order by mt.meeting_date desc,mt.id)
    from (select * from public.church_cell_meetings mm where mm.cell_id=p_cell and mm.status<>'cancelled' and mm.meeting_date between today-120 and today+60 order by mm.meeting_date desc,mm.id limit 24) mt),'[]'::jsonb),
   'visitors',coalesce((select jsonb_agg(jsonb_build_object('id',v2.id,'name',v2.visitor_name,'phone',case when can_report then coalesce(v2.phone,'') else '' end,'date',v2.visit_date) order by v2.visit_date desc,v2.id)
    from (select * from public.church_cell_visits vv where vv.cell_id=p_cell and vv.status='recorded' and vv.visit_date>=today-90 order by vv.visit_date desc,vv.id limit 60) v2),'[]'::jsonb),
   'referrals',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.person_name,'version',r.version,'linked',r.person_id is not null) order by r.created_at)
    from private.cell_referrals r where r.organization_id=p_org and r.unit_id=p_unit and r.cell_id=p_cell and r.status='pending'),'[]'::jsonb),
   'materials',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'title',s.title,'body',s.body,'url',s.url) order by s.updated_at desc)
    from private.cell_study_materials s where s.organization_id=p_org and s.unit_id=p_unit and s.status='published'
     and(s.network_id is null or s.network_id in(select l.network_id from public.church_cell_network_links l where l.cell_id=p_cell))),'[]'::jsonb)
  ) into result;
  return result;
 end if;

 if not can_report then raise exception 'cell_access_denied' using errcode='42501';end if;
 perform 1 from public.church_cells where id=p_cell for update;

 if p_action='meeting' then
  if not(p_data?&array['id','topic','date','time']) or p_data-array['id','topic','date','time']<>'{}' or exists(select 1 from jsonb_each(p_data)e where jsonb_typeof(e.value)<>'string')
   or p_data->>'id' !~ '^[0-9a-f-]{36}$' or p_data->>'date' !~ '^\d{4}-\d{2}-\d{2}$' or p_data->>'time' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'invalid_cell_leader' using errcode='22023';end if;
  d=(p_data->>'date')::date; topic=btrim(p_data->>'topic');
  if d not between today-60 and today+60 or length(topic) not between 2 and 120 or topic ~ '[[:cntrl:]]' then raise exception 'invalid_cell_leader' using errcode='22023';end if;
  select * into meeting from public.church_cell_meetings where id=(p_data->>'id')::uuid;
  if meeting.id is not null then
   if meeting.cell_id<>p_cell then raise exception 'cell_access_denied' using errcode='42501';end if;
   return jsonb_build_object('id',meeting.id,'version',meeting.version);
  end if;
  insert into public.church_cell_meetings(id,organization_id,unit_id,cell_id,topic,meeting_date,meeting_time,status,created_by)
   values((p_data->>'id')::uuid,p_org,p_unit,p_cell,topic,d,p_data->>'time','scheduled',actor) returning * into meeting;
  insert into public.church_cell_attendance(meeting_id,participant_id,cell_id,organization_id,unit_id,present)
   select meeting.id,m.id,p_cell,p_org,p_unit,false from public.church_cell_participants m where m.cell_id=p_cell and m.status='active';
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,actor,'cell.leader_meeting','church_cell_meeting',meeting.id::text,jsonb_build_object('unit_id',p_unit,'cell_id',p_cell));
  return jsonb_build_object('id',meeting.id,'version',meeting.version);

 elsif p_action='report' then
  if not(p_data?&array['meeting','version','present','visitors','notes']) or p_data-array['meeting','version','present','visitors','notes']<>'{}'
   or jsonb_typeof(p_data->'meeting')<>'string' or jsonb_typeof(p_data->'version')<>'number' or jsonb_typeof(p_data->'present')<>'array' or jsonb_typeof(p_data->'visitors')<>'array' or jsonb_typeof(p_data->'notes')<>'string'
   or jsonb_array_length(p_data->'present')>500 or jsonb_array_length(p_data->'visitors')>30 or length(p_data->>'notes')>1000
   or exists(select 1 from jsonb_array_elements(p_data->'present')e where jsonb_typeof(e)<>'string' or e#>>'{}' !~ '^[0-9a-f-]{36}$') then raise exception 'invalid_cell_leader' using errcode='22023';end if;
  select * into meeting from public.church_cell_meetings where id=(p_data->>'meeting')::uuid for update;
  if meeting.id is null or meeting.cell_id<>p_cell or meeting.organization_id<>p_org or meeting.unit_id<>p_unit then raise exception 'cell_access_denied' using errcode='42501';end if;
  if meeting.version<>(p_data->>'version')::integer then raise exception 'cell_version_conflict' using errcode='40001';end if;
  if meeting.status not in('scheduled','completed') or meeting.meeting_date>today then raise exception 'invalid_cell_leader' using errcode='22023';end if;
  select coalesce(array_agg(distinct e::uuid),'{}') into ids from jsonb_array_elements_text(p_data->'present')e;
  select coalesce(array_agg(participant_id),'{}') into snapshot from public.church_cell_attendance where meeting_id=meeting.id;
  if cardinality(ids)<>jsonb_array_length(p_data->'present') or not ids<@snapshot then raise exception 'invalid_cell_leader' using errcode='22023';end if;
  for x in select value from jsonb_array_elements(p_data->'visitors') loop
   if jsonb_typeof(x)<>'object' or not(x?&array['name','phone']) or x-array['name','phone']<>'{}' or jsonb_typeof(x->'name')<>'string' or jsonb_typeof(x->'phone')<>'string'
    or length(btrim(x->>'name')) not between 2 and 120 or (x->>'name') ~ '[[:cntrl:]]' or (x->>'phone')!='' and (x->>'phone') !~ '^[0-9]{8,15}$' then raise exception 'invalid_cell_leader' using errcode='22023';end if;
  end loop;
  notes=nullif(btrim(p_data->>'notes'),'');
  if notes ~ '[\x00-\x08\x0b\x0c\x0e-\x1f]' then raise exception 'invalid_cell_leader' using errcode='22023';end if;
  update public.church_cell_attendance set present=participant_id=any(ids) where meeting_id=meeting.id;
  -- Reenviar o relatório substitui os visitantes deste encontro.
  delete from public.church_cell_visits where meeting_id=meeting.id and person_id is null;
  insert into public.church_cell_visits(id,organization_id,unit_id,cell_id,person_id,visitor_name,visit_date,status,created_by,phone,meeting_id)
   select gen_random_uuid(),p_org,p_unit,p_cell,null,btrim(e->>'name'),meeting.meeting_date,'recorded',actor,nullif(e->>'phone',''),meeting.id from jsonb_array_elements(p_data->'visitors')e;
  get diagnostics n=row_count;
  update public.church_cell_meetings set status='completed',leader_notes=notes,version=version+1,updated_at=clock_timestamp() where id=meeting.id returning version into v;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,actor,'cell.leader_report','church_cell_meeting',meeting.id::text,jsonb_build_object('unit_id',p_unit,'cell_id',p_cell,'present',cardinality(ids),'visitors',n,'version',v));
  return jsonb_build_object('id',meeting.id,'version',v,'present',cardinality(ids),'visitors',n);

 else -- referral: aceitar ou recusar indicação para esta célula
  if not(p_data?&array['id','version','answer']) or p_data-array['id','version','answer']<>'{}' or jsonb_typeof(p_data->'id')<>'string' or jsonb_typeof(p_data->'version')<>'number'
   or p_data->>'answer' not in('accept','decline') or p_data->>'id' !~ '^[0-9a-f-]{36}$' then raise exception 'invalid_cell_leader' using errcode='22023';end if;
  select * into ref from private.cell_referrals where id=(p_data->>'id')::uuid for update;
  if ref.id is null or ref.cell_id<>p_cell or ref.organization_id<>p_org or ref.unit_id<>p_unit then raise exception 'cell_access_denied' using errcode='42501';end if;
  if ref.status<>'pending' or ref.version<>(p_data->>'version')::integer then raise exception 'cell_version_conflict' using errcode='40001';end if;
  if p_data->>'answer'='accept' then
   if ref.person_id is null or not exists(select 1 from public.people where id=ref.person_id and organization_id=p_org and unit_id=p_unit and status='active') then raise exception 'link_member_before_accept' using errcode='22023';end if;
   insert into public.church_cell_participants(id,organization_id,unit_id,cell_id,person_id,status,created_by) values(gen_random_uuid(),p_org,p_unit,p_cell,ref.person_id,'active',actor)
    on conflict(cell_id,person_id) do update set status='active',version=public.church_cell_participants.version+1,updated_at=clock_timestamp();
  end if;
  update private.cell_referrals set status=case when p_data->>'answer'='accept' then 'accepted' else 'rejected' end,version=version+1,updated_at=clock_timestamp() where id=ref.id returning version into v;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,actor,'cell.leader_referral_'||(p_data->>'answer'),'church_cell_referral',ref.id::text,jsonb_build_object('unit_id',p_unit,'cell_id',p_cell,'version',v));
  return jsonb_build_object('id',ref.id,'version',v);
 end if;
end $function$;
revoke all on function private.cell_leader_hub(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;

create or replace function public.member_cell_leader(p_org uuid, p_unit uuid, p_cell uuid, p_action text, p_data jsonb default '{}'::jsonb)
returns jsonb language sql security definer set search_path to '' as $$ select private.cell_leader_hub(p_org,p_unit,p_cell,p_action,p_data) $$;
revoke all on function public.member_cell_leader(uuid,uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.member_cell_leader(uuid,uuid,uuid,text,jsonb) to authenticated;
