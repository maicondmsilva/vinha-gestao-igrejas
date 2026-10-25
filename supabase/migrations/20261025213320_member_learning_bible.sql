set local lock_timeout='5s';
create table private.scripture_books(code text primary key,verses integer[] not null);
revoke all on private.scripture_books from public,anon,authenticated,service_role;
alter table private.scripture_books enable row level security;
insert into private.scripture_books(code,verses) values
('GEN',array[31,25,24,26,32,22,24,22,29,32,32,20,18,24,21,16,27,33,38,18,34,24,20,67,34,35,46,22,35,43,55,32,20,31,29,43,36,30,23,23,57,38,34,34,28,34,31,22,33,26]),
('EXO',array[22,25,22,31,23,30,25,32,35,29,10,51,22,31,27,36,16,27,25,26,36,31,33,18,40,37,21,43,46,38,18,35,23,35,35,38,29,31,43,38]),
('LEV',array[17,16,17,35,19,30,38,36,24,20,47,8,59,57,33,34,16,30,37,27,24,33,44,23,55,46,34]),
('NUM',array[54,34,51,49,31,27,89,26,23,36,35,16,33,45,41,50,13,32,22,29,35,41,30,25,18,65,23,31,40,16,54,42,56,29,34,13]),
('DEU',array[46,37,29,49,33,25,26,20,29,22,32,32,18,29,23,22,20,22,21,20,23,30,25,22,19,19,26,68,29,20,30,52,29,12]),
('JOS',array[18,24,17,24,15,27,26,35,27,43,23,24,33,15,63,10,18,28,51,9,45,34,16,33]),
('JDG',array[36,23,31,24,31,40,25,35,57,18,40,15,25,20,20,31,13,31,30,48,25]),
('RUT',array[22,23,18,22]),
('1SA',array[28,36,21,22,12,21,17,22,27,27,15,25,23,52,35,23,58,30,24,42,15,23,29,22,44,25,12,25,11,31,13]),
('2SA',array[27,32,39,12,25,23,29,18,13,19,27,31,39,33,37,23,29,33,43,26,22,51,39,25]),
('1KI',array[53,46,28,34,18,38,51,66,28,29,43,33,34,31,34,34,24,46,21,43,29,53]),
('2KI',array[18,25,27,44,27,33,20,29,37,36,21,21,25,29,38,20,41,37,37,21,26,20,37,20,30]),
('1CH',array[54,55,24,43,26,81,40,40,44,14,47,40,14,17,29,43,27,17,19,8,30,19,32,31,31,32,34,21,30]),
('2CH',array[17,18,17,22,14,42,22,18,31,19,23,16,22,15,19,14,19,34,11,37,20,12,21,27,28,23,9,27,36,27,21,33,25,33,27,23]),
('EZR',array[11,70,13,24,17,22,28,36,15,44]),
('NEH',array[11,20,32,23,19,19,73,18,38,39,36,47,31]),
('EST',array[22,23,15,17,14,14,10,17,32,3]),
('JOB',array[22,13,26,21,27,30,21,22,35,22,20,25,28,22,35,22,16,21,29,29,34,30,17,25,6,14,23,28,25,31,40,22,33,37,16,33,24,41,30,24,34,17]),
('PSA',array[6,12,8,8,12,10,17,9,20,18,7,8,6,7,5,11,15,50,14,9,13,31,6,10,22,12,14,9,11,12,24,11,22,22,28,12,40,22,13,17,13,11,5,26,17,11,9,14,20,23,19,9,6,7,23,13,11,11,17,12,8,12,11,10,13,20,7,35,36,5,24,20,28,23,10,12,20,72,13,19,16,8,18,12,13,17,7,18,52,17,16,15,5,23,11,13,12,9,9,5,8,28,22,35,45,48,43,13,31,7,10,10,9,8,18,19,2,29,176,7,8,9,4,8,5,6,5,6,8,8,3,18,3,3,21,26,9,8,24,13,10,7,12,15,21,10,20,14,9,6]),
('PRO',array[33,22,35,27,23,35,27,36,18,32,31,28,25,35,33,33,28,24,29,30,31,29,35,34,28,28,27,28,27,33,31]),
('ECC',array[18,26,22,16,20,12,29,17,18,20,10,14]),
('SNG',array[17,17,11,16,16,13,13,14]),
('ISA',array[31,22,26,6,30,13,25,22,21,34,16,6,22,32,9,14,14,7,25,6,17,25,18,23,12,21,13,29,24,33,9,20,24,17,10,22,38,22,8,31,29,25,28,28,25,13,15,22,26,11,23,15,12,17,13,12,21,14,21,22,11,12,19,12,25,24]),
('JER',array[19,37,25,31,31,30,34,22,26,25,23,17,27,22,21,21,27,23,15,18,14,30,40,10,38,24,22,17,32,24,40,44,26,22,19,32,21,28,18,16,18,22,13,30,5,28,7,47,39,46,64,34]),
('LAM',array[22,22,66,22,22]),
('EZK',array[28,10,27,17,17,14,27,18,11,22,25,28,23,23,8,63,24,32,14,49,32,31,49,27,17,21,36,26,21,26,18,32,33,31,15,38,28,23,29,49,26,20,27,31,25,24,23,35]),
('DAN',array[21,49,30,37,31,28,28,27,27,21,45,13]),
('HOS',array[11,23,5,19,15,11,16,14,17,15,12,14,16,9]),
('JOL',array[20,32,21]),
('AMO',array[15,16,15,13,27,14,17,14,15]),
('OBA',array[21]),
('JON',array[17,10,10,11]),
('MIC',array[16,13,12,13,15,16,20]),
('NAM',array[15,13,19]),
('HAB',array[17,20,19]),
('ZEP',array[18,15,20]),
('HAG',array[15,23]),
('ZEC',array[21,13,10,14,11,15,14,23,17,12,17,14,9,21]),
('MAL',array[14,17,18,6]),
('MAT',array[25,23,17,25,48,34,29,34,38,42,30,50,58,36,39,28,27,35,30,34,46,46,39,51,46,75,66,20]),
('MRK',array[45,28,35,41,43,56,37,38,50,52,33,44,37,72,47,20]),
('LUK',array[80,52,38,44,39,49,50,56,62,42,54,59,35,35,32,31,37,43,48,47,38,71,56,53]),
('JHN',array[51,25,36,54,47,71,53,59,41,42,57,50,38,31,27,33,26,40,42,31,25]),
('ACT',array[26,47,26,37,42,15,60,40,43,48,30,25,52,28,41,40,34,28,41,38,40,30,35,27,27,32,44,31]),
('ROM',array[32,29,31,25,21,23,25,39,33,21,36,21,14,23,33,27]),
('1CO',array[31,16,23,21,13,20,40,13,27,33,34,31,13,40,58,24]),
('2CO',array[24,17,18,18,21,18,16,24,15,18,33,21,14]),
('GAL',array[24,21,29,31,26,18]),
('EPH',array[23,22,21,32,33,24]),
('PHP',array[30,30,21,23]),
('COL',array[29,23,25,18]),
('1TH',array[10,20,13,18,28]),
('2TH',array[12,17,18]),
('1TI',array[20,15,16,16,25,21]),
('2TI',array[18,26,17,22]),
('TIT',array[16,15,15]),
('PHM',array[25]),
('HEB',array[14,18,19,16,14,20,28,13,28,39,40,29,25]),
('JAS',array[27,26,18,17,20]),
('1PE',array[25,25,22,19,14]),
('2PE',array[21,22,18]),
('1JN',array[10,29,24,21,21]),
('2JN',array[13]),
('3JN',array[14]),
('JUD',array[25]),
('REV',array[20,29,22,11,14,17,17,13,21,11,19,17,18,20,8,21,18,24,21,15,27,21]);
create table private.learning_programs(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,kind text not null check(kind in('journey','reading')),
 title text not null check(length(title) between 2 and 160),summary text not null default '' check(length(summary)<=2000),steps jsonb not null check(jsonb_typeof(steps)='array' and jsonb_array_length(steps) between 1 and 366),
 status text not null default 'draft' check(status in('draft','published','archived')),version integer not null default 1,created_by uuid not null references auth.users(id),nonce text not null,
 created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),unique(id,organization_id,unit_id),unique(organization_id,created_by,nonce),foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create table private.learning_enrollments(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),unit_id uuid not null,program_id uuid not null,user_id uuid not null references auth.users(id),
 done integer[] not null default '{}',version integer not null default 1,completed_at timestamptz,created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),
 unique(program_id,user_id),foreign key(program_id,organization_id,unit_id) references private.learning_programs(id,organization_id,unit_id)
);
create table private.scripture_preferences(
 organization_id uuid not null references public.organizations(id),user_id uuid not null references auth.users(id),book text not null references private.scripture_books(code),chapter integer not null,verse integer not null,
 font integer not null check(font between 14 and 32),theme text not null check(theme in('system','light','dark')),version integer not null default 1,updated_at timestamptz not null default clock_timestamp(),primary key(organization_id,user_id)
);
create table private.scripture_bookmarks(
 id uuid primary key default extensions.gen_random_uuid(),organization_id uuid not null references public.organizations(id),user_id uuid not null references auth.users(id),book text not null references private.scripture_books(code),chapter integer not null,verse integer not null,
 created_at timestamptz not null default clock_timestamp(),unique(organization_id,user_id,book,chapter,verse)
);
create index learning_programs_scope on private.learning_programs(unit_id,organization_id,status,created_at,id);
create index learning_programs_creator on private.learning_programs(created_by);
create index learning_enrollments_scope on private.learning_enrollments(program_id,organization_id,unit_id);
create index learning_enrollments_user on private.learning_enrollments(user_id,organization_id,created_at,id);
create index learning_enrollments_org on private.learning_enrollments(organization_id);
create index scripture_preferences_user on private.scripture_preferences(user_id);
create index scripture_preferences_book on private.scripture_preferences(book);
create index scripture_bookmarks_user on private.scripture_bookmarks(user_id,organization_id,created_at,id);
create index scripture_bookmarks_book on private.scripture_bookmarks(book);
alter table private.learning_programs enable row level security;
alter table private.learning_enrollments enable row level security;
alter table private.scripture_preferences enable row level security;
alter table private.scripture_bookmarks enable row level security;
revoke all on private.learning_programs,private.learning_enrollments,private.scripture_preferences,private.scripture_bookmarks from public,anon,authenticated,service_role;

create function private.scripture_valid(p_ref jsonb) returns boolean language plpgsql stable security definer set search_path='' as $$
declare counts integer[];ch integer;v integer;
begin
 if jsonb_typeof(p_ref) is distinct from 'object' or p_ref-array['book','chapter','verse']<>'{}' or jsonb_typeof(p_ref->'book') is distinct from 'string' or coalesce(p_ref->>'chapter','')!~'^[0-9]{1,3}$' or coalesce(p_ref->>'verse','1')!~'^[0-9]{1,3}$' then return false;end if;
 select verses into counts from private.scripture_books where code=p_ref->>'book';ch:=(p_ref->>'chapter')::integer;v:=coalesce((p_ref->>'verse')::integer,1);
 return coalesce(ch between 1 and cardinality(counts) and v between 1 and counts[ch],false);
end $$;
revoke all on function private.scripture_valid(jsonb) from public,anon,authenticated,service_role;
create function private.learning_steps_valid(p_kind text,p_steps jsonb) returns boolean language plpgsql stable security definer set search_path='' as $$
declare step jsonb;ref jsonb;
begin
 if p_kind not in('journey','reading') or p_kind is null or jsonb_typeof(p_steps) is distinct from 'array' or jsonb_array_length(p_steps) not between 1 and 366 or length(p_steps::text)>450000 then return false;end if;
 for step in select value from jsonb_array_elements(p_steps) loop
  if jsonb_typeof(step) is distinct from 'object' or step-array['title','body','href','readings']<>'{}' or not(step ?& array['title','body','href','readings']) or exists(select 1 from jsonb_each(step) j where j.key<>'readings' and jsonb_typeof(j.value)<>'string')
   or length(btrim(step->>'title')) not between 2 and 160 or length(step->>'body')>4000 or length(step->>'href')>2000 or (step->>'href'<>'' and step->>'href'!~'^https://[^[:space:]@]+$') or jsonb_typeof(step->'readings') is distinct from 'array' or jsonb_array_length(step->'readings') not between (case when p_kind='reading' then 1 else 0 end) and 12 then return false;end if;
  for ref in select value from jsonb_array_elements(step->'readings') loop if not private.scripture_valid(ref) or ref ? 'verse' then return false;end if;end loop;
 end loop;
 return true;
end $$;
revoke all on function private.learning_steps_valid(text,jsonb) from public,anon,authenticated,service_role;

create function member_app_api.learning(p_org uuid,p_unit uuid,p_kind text default 'journey',p_id uuid default null,p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;
begin
 if p_kind is null or p_kind not in('journey','reading') or p_offset is null or p_offset not between 0 and 100000 then raise exception 'invalid_learning' using errcode='22023';end if;
 if not private.community_scope(p_org,p_unit) then return jsonb_build_object('items','[]'::jsonb,'more',false,'program',null);end if;
 if p_id is not null then return jsonb_build_object('program',(select to_jsonb(q) from(select id,unit_id,kind,title,summary,steps,status,version from private.learning_programs where id=p_id and organization_id=p_org and unit_id=p_unit and status='published')q));end if;
 select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select id,unit_id,kind,title,summary,status,version,jsonb_array_length(steps) total from private.learning_programs where organization_id=p_org and unit_id=p_unit and kind=p_kind and status='published' order by created_at desc,id limit 21 offset p_offset)q;
 return jsonb_build_object('items',case when jsonb_array_length(rows)>20 then rows-20 else rows end,'more',jsonb_array_length(rows)>20);
end $$;
revoke all on function member_app_api.learning(uuid,uuid,text,uuid,integer) from public,service_role;
grant execute on function member_app_api.learning(uuid,uuid,text,uuid,integer) to anon,authenticated;
create function public.member_learning_public(p_org uuid,p_unit uuid,p_kind text default 'journey',p_id uuid default null,p_offset integer default 0) returns jsonb language sql stable security invoker set search_path='' as $$select member_app_api.learning(p_org,p_unit,p_kind,p_id,p_offset)$$;
revoke all on function public.member_learning_public(uuid,uuid,text,uuid,integer) from public,service_role;
grant execute on function public.member_learning_public(uuid,uuid,text,uuid,integer) to anon,authenticated;

create function private.member_learning_self(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare program private.learning_programs;enrollment private.learning_enrollments;pref private.scripture_preferences;rows jsonb;pos integer;next_pos integer;ref jsonb;new_done integer[];
begin
 perform private.community_identity(p_org,p_unit,false);
 if p_action is null or jsonb_typeof(p_data) is distinct from 'object' or p_offset is null or p_offset not between 0 and 100000 then raise exception 'invalid_learning' using errcode='22023';end if;
 if p_action='mine' then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select e.id,e.program_id,e.unit_id,e.done,e.version,e.completed_at,p.title,p.kind,p.summary,p.status,jsonb_array_length(p.steps) total,u.name church from private.learning_enrollments e join private.learning_programs p on p.id=e.program_id join public.organization_units u on u.id=e.unit_id where e.organization_id=p_org and e.user_id=auth.uid() order by e.created_at desc,e.id limit 21 offset p_offset)q;
  return jsonb_build_object('items',case when jsonb_array_length(rows)>20 then rows-20 else rows end,'more',jsonb_array_length(rows)>20);
 elsif p_action='detail' then
  select * into enrollment from private.learning_enrollments where program_id=p_id and organization_id=p_org and user_id=auth.uid();
  if not found then return jsonb_build_object('enrollment',null,'program',null);end if;
  select * into program from private.learning_programs where id=p_id and organization_id=p_org;
  return jsonb_build_object('enrollment',to_jsonb(enrollment)-array['organization_id','user_id'],'program',jsonb_build_object('id',program.id,'unit_id',program.unit_id,'kind',program.kind,'title',program.title,'summary',program.summary,'steps',program.steps,'status',program.status,'version',program.version));
 elsif p_action='enroll' then
  select * into program from private.learning_programs where id=p_id and organization_id=p_org and unit_id=p_unit and status='published' for update;
  if not found then raise exception 'learning_closed' using errcode='40001';end if;
  insert into private.learning_enrollments(organization_id,unit_id,program_id,user_id) values(p_org,p_unit,program.id,auth.uid()) on conflict(program_id,user_id) do nothing;
  return jsonb_build_object('ok',true);
 elsif p_action='progress' then
  select * into enrollment from private.learning_enrollments where id=p_id and organization_id=p_org and user_id=auth.uid() for update;
  if not found then raise exception 'learning_denied' using errcode='42501';end if;
  if enrollment.version is distinct from p_version then raise exception 'learning_changed' using errcode='40001';end if;
  select * into program from private.learning_programs where id=enrollment.program_id;
  if p_data-array['position','done']<>'{}' or jsonb_typeof(p_data->'done') is distinct from 'boolean' or coalesce(p_data->>'position','')!~'^[0-9]{1,3}$' then raise exception 'invalid_learning' using errcode='22023';end if;
  pos:=(p_data->>'position')::integer;if pos not between 1 and jsonb_array_length(program.steps) then raise exception 'invalid_learning' using errcode='22023';end if;
  select min(i) into next_pos from generate_series(1,jsonb_array_length(program.steps))i where not(i=any(enrollment.done));
  if program.kind='journey' and (p_data->>'done')::boolean and pos>coalesce(next_pos,jsonb_array_length(program.steps)) then raise exception 'learning_sequence' using errcode='40001';end if;
  if (p_data->>'done')::boolean then select array_agg(distinct n order by n) into new_done from unnest(enrollment.done||pos)n;
  else select coalesce(array_agg(n order by n),'{}') into new_done from unnest(enrollment.done)n where n<>pos and (program.kind<>'journey' or n<pos);end if;
  update private.learning_enrollments set done=new_done,version=version+1,completed_at=case when cardinality(new_done)=jsonb_array_length(program.steps) then coalesce(completed_at,clock_timestamp()) else null end,updated_at=clock_timestamp() where id=enrollment.id;
  return jsonb_build_object('ok',true);
 elsif p_action='reader' then
  select * into pref from private.scripture_preferences where organization_id=p_org and user_id=auth.uid();
  return jsonb_build_object('preferences',case when pref.user_id is null then jsonb_build_object('book','GEN','chapter',1,'verse',1,'font',18,'theme','system','version',0) else to_jsonb(pref)-array['organization_id','user_id'] end);
 elsif p_action='reader.save' then
  ref:=jsonb_build_object('book',p_data->'book','chapter',p_data->'chapter','verse',p_data->'verse');
  if p_data-array['book','chapter','verse','font','theme']<>'{}' or not private.scripture_valid(ref) or coalesce(p_data->>'font','')!~'^[0-9]{2}$' or (p_data->>'font')::integer not between 14 and 32 or p_data->>'theme' not in('system','light','dark') then raise exception 'invalid_learning' using errcode='22023';end if;
  select * into pref from private.scripture_preferences where organization_id=p_org and user_id=auth.uid() for update;
  if coalesce(pref.version,0) is distinct from p_version then raise exception 'learning_changed' using errcode='40001';end if;
  insert into private.scripture_preferences(organization_id,user_id,book,chapter,verse,font,theme) values(p_org,auth.uid(),p_data->>'book',(p_data->>'chapter')::integer,(p_data->>'verse')::integer,(p_data->>'font')::integer,p_data->>'theme') on conflict(organization_id,user_id) do update set book=excluded.book,chapter=excluded.chapter,verse=excluded.verse,font=excluded.font,theme=excluded.theme,version=private.scripture_preferences.version+1,updated_at=clock_timestamp();
  return jsonb_build_object('ok',true);
 elsif p_action in('bookmarks','marks') then
  if p_action='marks' and not private.scripture_valid(p_data) then raise exception 'invalid_learning' using errcode='22023';end if;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select id,book,chapter,verse from private.scripture_bookmarks where organization_id=p_org and user_id=auth.uid() and (p_action='bookmarks' or (book=p_data->>'book' and chapter=(p_data->>'chapter')::integer)) order by created_at desc,id limit (case when p_action='bookmarks' then 21 else 200 end) offset (case when p_action='bookmarks' then p_offset else 0 end))q;
  return jsonb_build_object('items',case when p_action='bookmarks' and jsonb_array_length(rows)>20 then rows-20 else rows end,'more',p_action='bookmarks' and jsonb_array_length(rows)>20);
 elsif p_action in('bookmark.add','bookmark.remove') then
  if not private.scripture_valid(p_data) or not(p_data ? 'verse') then raise exception 'invalid_learning' using errcode='22023';end if;
  if p_action='bookmark.add' then insert into private.scripture_bookmarks(organization_id,user_id,book,chapter,verse) values(p_org,auth.uid(),p_data->>'book',(p_data->>'chapter')::integer,(p_data->>'verse')::integer) on conflict(organization_id,user_id,book,chapter,verse) do nothing;
  else delete from private.scripture_bookmarks where organization_id=p_org and user_id=auth.uid() and book=p_data->>'book' and chapter=(p_data->>'chapter')::integer and verse=(p_data->>'verse')::integer;end if;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'invalid_learning' using errcode='22023';
end $$;
revoke all on function private.member_learning_self(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function private.member_learning_self(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;
create function public.member_learning_self(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select private.member_learning_self(p_org,p_unit,p_action,p_id,p_version,p_data,p_offset)$$;
revoke all on function public.member_learning_self(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function public.member_learning_self(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;

create function private.member_learning_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare program private.learning_programs;rows jsonb;result_id uuid;v integer;
begin
 perform private.community_identity(p_org,p_unit,false);
 if p_unit is null or not private.has_organization_role(p_org,array['owner','admin','pastor']::public.membership_role[]) or not private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[]) then raise exception 'learning_denied' using errcode='42501';end if;
 if p_action is null or jsonb_typeof(p_data) is distinct from 'object' or p_offset is null or p_offset not between 0 and 100000 then raise exception 'invalid_learning' using errcode='22023';end if;
 if p_action not in('list','create','edit','duplicate','publish','archive') then raise exception 'invalid_learning' using errcode='22023';end if;
 if p_action='list' then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into rows from(select p.*,(select count(*) from private.learning_enrollments e where e.program_id=p.id) enrollments,(select count(*) from private.learning_enrollments e where e.program_id=p.id and e.completed_at is not null) completions from private.learning_programs p where p.organization_id=p_org and p.unit_id=p_unit order by p.created_at desc,p.id limit 21 offset p_offset)q;
  return jsonb_build_object('items',case when jsonb_array_length(rows)>20 then rows-20 else rows end,'more',jsonb_array_length(rows)>20);
 end if;
 if p_action<>'create' then
  select * into program from private.learning_programs where id=p_id and organization_id=p_org and unit_id=p_unit for update;
  if not found then raise exception 'learning_denied' using errcode='42501';end if;
  if program.version is distinct from p_version then raise exception 'learning_changed' using errcode='40001';end if;
 end if;
 if p_action in('create','edit') then
  if p_data-array['nonce','kind','title','summary','steps']<>'{}' or not(p_data ?& array['kind','title','summary','steps']) or exists(select 1 from jsonb_each(p_data) j where j.key<>'steps' and jsonb_typeof(j.value)<>'string') or length(btrim(p_data->>'title')) not between 2 and 160 or length(p_data->>'summary')>2000 or not private.learning_steps_valid(p_data->>'kind',p_data->'steps') then raise exception 'invalid_learning' using errcode='22023';end if;
  if p_action='create' then
   if length(coalesce(p_data->>'nonce','')) not between 10 and 100 then raise exception 'invalid_learning' using errcode='22023';end if;
   insert into private.learning_programs(organization_id,unit_id,kind,title,summary,steps,created_by,nonce) values(p_org,p_unit,p_data->>'kind',btrim(p_data->>'title'),p_data->>'summary',p_data->'steps',auth.uid(),p_data->>'nonce') on conflict(organization_id,created_by,nonce) do nothing returning id,version into result_id,v;
   if result_id is null then select id,version into result_id,v from private.learning_programs where organization_id=p_org and created_by=auth.uid() and nonce=p_data->>'nonce';return jsonb_build_object('ok',true,'id',result_id,'version',v);end if;
  else
   if program.status<>'draft' then raise exception 'learning_immutable' using errcode='40001';end if;
   update private.learning_programs set kind=p_data->>'kind',title=btrim(p_data->>'title'),summary=p_data->>'summary',steps=p_data->'steps',version=version+1,updated_at=clock_timestamp() where id=program.id returning id,version into result_id,v;
  end if;
 elsif p_action='duplicate' then
  if length(coalesce(p_data->>'nonce','')) not between 10 and 100 or p_data-array['nonce']<>'{}' then raise exception 'invalid_learning' using errcode='22023';end if;
  insert into private.learning_programs(organization_id,unit_id,kind,title,summary,steps,created_by,nonce) values(p_org,p_unit,program.kind,left(program.title,145)||' — nova edição',program.summary,program.steps,auth.uid(),p_data->>'nonce') on conflict(organization_id,created_by,nonce) do nothing returning id,version into result_id,v;
  if result_id is null then select id,version into result_id,v from private.learning_programs where organization_id=p_org and created_by=auth.uid() and nonce=p_data->>'nonce';return jsonb_build_object('ok',true,'id',result_id,'version',v);end if;
 elsif p_action in('publish','archive') then
  if p_data<>'{}' or p_action='publish' and program.status<>'draft' or program.status='archived' or not private.learning_steps_valid(program.kind,program.steps) then raise exception 'learning_closed' using errcode='40001';end if;
  update private.learning_programs set status=case when p_action='publish' then 'published' else 'archived' end,version=version+1,updated_at=clock_timestamp() where id=program.id returning id,version into result_id,v;
 else raise exception 'invalid_learning' using errcode='22023';end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'member.learning.'||p_action,'learning_program',result_id);
 return jsonb_build_object('ok',true,'id',result_id,'version',v);
end $$;
revoke all on function private.member_learning_admin(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function private.member_learning_admin(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;
create function public.member_learning_admin(p_org uuid,p_unit uuid,p_action text,p_id uuid default null,p_version integer default null,p_data jsonb default '{}',p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select private.member_learning_admin(p_org,p_unit,p_action,p_id,p_version,p_data,p_offset)$$;
revoke all on function public.member_learning_admin(uuid,uuid,text,uuid,integer,jsonb,integer) from public,anon,service_role;
grant execute on function public.member_learning_admin(uuid,uuid,text,uuid,integer,jsonb,integer) to authenticated;
create function private.member_inbox_before_learning(p_org uuid,p_unit uuid) returns table(message_key text,title text,body text,occurred_at timestamptz,target text,target_id uuid) language sql stable security definer set search_path='' as $$
 select * from(
 select * from private.member_inbox_before_community(p_org,p_unit)
 union all select 'prayer:'||id||':'||version,'Pedido de oração atualizado',case status when 'care' then 'A equipe está acompanhando seu pedido.' when 'completed' then 'A equipe concluiu o acompanhamento.' else 'Pedido cancelado.' end,updated_at,'prayers',id from private.community_prayers where organization_id=p_org and user_id=auth.uid() and status<>'pending'
 union all select 'testimony:'||id||':'||version,'Seu testemunho',case status when 'published' then 'Seu testemunho foi aprovado e publicado.' when 'rejected' then 'Sua publicação não foi aprovada. Consulte o motivo.' else 'Publicação retirada a seu pedido.' end,updated_at,'testimonies',id from private.community_testimonies where organization_id=p_org and user_id=auth.uid() and status<>'pending'
 union all select 'participation:'||id||':'||version,'Participação em ministério',case status when 'approved' then 'Sua participação foi aprovada.' when 'rejected' then 'Solicitação revisada. Consulte o motivo.' else 'Sua participação foi encerrada.' end,updated_at,'groups',id from private.community_participation where organization_id=p_org and user_id=auth.uid() and status<>'pending'
 )q order by occurred_at desc nulls last,message_key limit 100;
$$;
revoke all on function private.member_inbox_before_learning(uuid,uuid) from public,anon,authenticated,service_role;


create or replace function private.member_inbox_rows(p_org uuid,p_unit uuid) returns table(message_key text,title text,body text,occurred_at timestamptz,target text,target_id uuid) language sql stable security definer set search_path='' as $$
 select * from(select * from private.member_inbox_before_learning(p_org,p_unit)
 union all select 'learning:'||e.id||':'||e.version,'Leitura e jornada concluída',p.title||' — todas as etapas foram marcadas como concluídas.',e.completed_at,'learning',e.program_id from private.learning_enrollments e join private.learning_programs p on p.id=e.program_id where e.organization_id=p_org and e.user_id=auth.uid() and e.completed_at is not null)q order by occurred_at desc nulls last,message_key limit 100;
$$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated,service_role;
