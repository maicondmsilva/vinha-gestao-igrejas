import {spawnSync} from 'node:child_process';
if(process.argv[2]!=='--local-synthetic')throw Error('Somente Docker local fictício.');
const sql=`do $$declare org uuid;unit uuid;adult uuid;actor uuid;profile uuid;room uuid;class uuid;session uuid;grp uuid;cell uuid;member uuid;begin
select id into org from public.organizations where slug='kids-visual-0ccf07ad-7ce7-4332-9725-7444ec231911';
select id,unit_id,auth_user_id into adult,unit,actor from public.people where organization_id=org and full_name='Equipe Kids — pessoa fictícia' and status='active';
if org is null or adult is null or not exists(select 1 from auth.users where id=actor and email='visual-kids-k2-20261024-b@example.invalid') then raise exception 'Fixture local conhecida ausente';end if;
select id into profile from private.kids_profiles where organization_id=org and unit_id=unit and status='active' and review_status='approved' order by created_at limit 1;
if profile is null then raise exception 'Criança fictícia ausente';end if;
insert into private.kids_guardians(organization_id,unit_id,profile_id,person_id,relationship,verification_note,can_pickup,can_edit,status,approved_by,approved_at,created_by) values(org,unit,profile,adult,'Responsável fictício','Conferência de homologação local, sem família real',true,true,'approved',actor,now(),actor) on conflict(profile_id,person_id) do nothing;
if not exists(select 1 from private.kids_sessions where organization_id=org and name='Kids do aplicativo — sessão fictícia') then
room=extensions.gen_random_uuid();class=extensions.gen_random_uuid();session=extensions.gen_random_uuid();grp=extensions.gen_random_uuid();
insert into private.kids_rooms(id,organization_id,unit_id,name,location,capacity) values(room,org,unit,'Sala de demonstração do app','Sala fictícia',3);
insert into private.kids_classes(id,organization_id,unit_id,name,min_months,max_months) values(class,org,unit,'Turma fictícia do app',0,215);
insert into private.kids_sessions(id,organization_id,unit_id,name,starts_at,ends_at,status,created_by) values(session,org,unit,'Kids do aplicativo — sessão fictícia',now()-interval '5 minutes',now()+interval '4 hours','open',actor);
insert into private.kids_session_rooms(id,organization_id,unit_id,session_id,room_id,class_id,capacity,min_staff) values(grp,org,unit,session,room,class,3,1);
select id into member from public.organization_memberships where organization_id=org and user_id=actor;
insert into private.kids_assignments(id,organization_id,unit_id,session_id,group_id,person_id,member_id,role) values(extensions.gen_random_uuid(),org,unit,session,grp,adult,member,'teacher');
end if;
if not exists(select 1 from public.church_cells where organization_id=org and name='Glória — grupo fictício do aplicativo') then
cell=extensions.gen_random_uuid();insert into public.church_cells(id,organization_id,unit_id,name,leader_person_id,leader_name,meeting_day,meeting_time,meeting_format,location,created_by) values(cell,org,unit,'Glória — grupo fictício do aplicativo',adult,'Equipe fictícia',2,'19:30','presential','Endereço reservado fictício, somente participantes',actor);
insert into private.cell_app_publications(cell_id,organization_id,unit_id,area,description,published,updated_by) values(cell,org,unit,'Centro fictício','Grupo de demonstração para validar o aplicativo, sem dados reais.',true,actor);
end if;end $$;`;
const r=spawnSync('docker',['exec','-i','supabase_db_vinha','psql','-X','-q','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-1'],{input:sql,encoding:'utf8',timeout:30000});if(r.status!==0){console.error(r.stderr);process.exit(1)}console.log('Fixture somente local: responsável, sessão Kids e grupo fictícios preparados.');
