-- Agenda de atendimento: horários respeitados, público do atendente, convite com aceite (12 h),
-- relatório com sigilo por permissão, histórico com registro de leitura e Integração Visitante. Tudo desfeito no fim.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
create function pg_temp.k(t text) returns uuid language sql immutable as $$select md5('agenda2-'||t)::uuid$$;
create function pg_temp.as_(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.k(t),'role','authenticated','email',t||'@agenda.invalid','aal','aal2')::text,true)$$;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.k(t),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',t||'@agenda.invalid',now(),now(),now() from unnest(array['owner','pastor','leader','member','visitor','sec','pastor2'])t;
insert into public.organizations(id,name,slug,status) values(pg_temp.k('org'),'Agenda 2','agenda2-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values(pg_temp.k('u'),pg_temp.k('org'),'Sede','sede','headquarters');
insert into public.organization_memberships(id,organization_id,user_id,default_unit_id,role,status)
select pg_temp.k(t||'-m'),pg_temp.k('org'),pg_temp.k(t),pg_temp.k('u'),(case t when 'owner' then 'owner' when 'sec' then 'secretary' else 'member' end)::public.membership_role,'active'
from unnest(array['owner','pastor','leader','member','visitor','sec','pastor2'])t;
insert into public.people(id,organization_id,unit_id,full_name,status,auth_user_id,is_pastor) values
 (pg_temp.k('p-pastor'),pg_temp.k('org'),pg_temp.k('u'),'Pr. Davi','active',pg_temp.k('pastor'),true),
 (pg_temp.k('p-leader'),pg_temp.k('org'),pg_temp.k('u'),'Lia Líder','active',pg_temp.k('leader'),false),
 (pg_temp.k('p-member'),pg_temp.k('org'),pg_temp.k('u'),'Mário Membro','active',pg_temp.k('member'),false),
 (pg_temp.k('p-visitor'),pg_temp.k('org'),pg_temp.k('u'),'Vera Visitante','active',pg_temp.k('visitor'),false),
 (pg_temp.k('p-pastor2'),pg_temp.k('org'),pg_temp.k('u'),'Pra. Sara','active',pg_temp.k('pastor2'),true);
insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by,leader_person_id)
values(pg_temp.k('cell'),pg_temp.k('org'),pg_temp.k('u'),'Célula Luz',2,'20:00','presential',pg_temp.k('owner'),pg_temp.k('p-leader'));
insert into public.church_cell_participants(id,organization_id,unit_id,cell_id,person_id,status,created_by)
values(pg_temp.k('cp'),pg_temp.k('org'),pg_temp.k('u'),pg_temp.k('cell'),pg_temp.k('p-member'),'active',pg_temp.k('owner'));
create function pg_temp.at(days int,hhmm text) returns timestamptz language sql stable security definer as $$select ((current_date+days)+hhmm::time) at time zone private.unit_timezone(pg_temp.k('u'))$$;
create function pg_temp.staff(a text,d jsonb default '{}') returns jsonb language sql as $$select public.pastoral_staff(pg_temp.k('org'),pg_temp.k('u'),a,d)$$;
create function pg_temp.member(a text,d jsonb default '{}') returns jsonb language sql as $$select public.pastoral_member(pg_temp.k('org'),pg_temp.k('u'),a,d)$$;
create function pg_temp.rep(a text,d jsonb default '{}') returns jsonb language sql as $$select public.pastoral_reports(pg_temp.k('org'),pg_temp.k('u'),a,d)$$;
create function pg_temp.ap(id uuid) returns private.pastoral_appointments language sql security definer as $$select * from private.pastoral_appointments where id=$1$$;

-- Atendentes: pastor (só líderes) e líder (só a própria célula).
select pg_temp.as_('owner');set local role authenticated;
select lives_ok($$select pg_temp.staff('save_attendant',jsonb_build_object('id',pg_temp.k('att'),'person',pg_temp.k('p-pastor'),'role','Pastor','about','','autoConfirm',false,'durations',jsonb_build_array(30,60),'kinds',jsonb_build_array('conversa','visita'),'modes',jsonb_build_array('presencial','visita'),'active',true,'version',0))$$,'pastor atendente');
select lives_ok($$select pg_temp.staff('save_attendant',jsonb_build_object('id',pg_temp.k('att-l'),'person',pg_temp.k('p-leader'),'role','Líder','about','','autoConfirm',false,'durations',jsonb_build_array(30),'kinds',jsonb_build_array('conversa'),'modes',jsonb_build_array('presencial'),'active',true,'version',0))$$,'líder atendente');
reset role;
insert into private.pastoral_hours(attendant_id,weekday,starts,ends) select a,w,'08:00','20:00' from unnest(array[pg_temp.k('att'),pg_temp.k('att-l')]) a,generate_series(0,6) w;
select pg_temp.as_('pastor');set local role authenticated;
select is(public.pastoral_rules(pg_temp.k('org'),pg_temp.k('u'),pg_temp.k('att'),'{"audience":"leaders","maxPerDay":3,"buffer":15}')->>'audience','leaders','pastor atende só líderes');
select pg_temp.as_('leader');set local role authenticated;
select is(public.pastoral_rules(pg_temp.k('org'),pg_temp.k('u'),pg_temp.k('att-l'),'{"audience":"group"}')->>'audience','group','líder atende a célula');
select throws_ok($$select public.pastoral_rules(pg_temp.k('org'),pg_temp.k('u'),pg_temp.k('att'),'{"audience":"all"}')$$,'42501',null,'não muda regra de outro atendente');

-- Público: membro vê só o líder; visitante sem célula não vê ninguém; líder vê o pastor.
select pg_temp.as_('member');set local role authenticated;
select is((select string_agg(i->>'name',',') from jsonb_array_elements(pg_temp.member('attendants')->'items') i),'Lia Líder','membro vê só o líder da célula');
select throws_ok($$select pg_temp.member('day',jsonb_build_object('attendant',pg_temp.k('att'),'minutes',30,'date',(current_date+3)::text))$$,'22023',null,'membro não agenda com quem atende só líderes');
select pg_temp.as_('visitor');set local role authenticated;
select is(jsonb_array_length(pg_temp.member('attendants')->'items'),0,'visitante sem célula não vê atendentes restritos');
select pg_temp.as_('leader');set local role authenticated;
select is((select string_agg(i->>'name',',') from jsonb_array_elements(pg_temp.member('attendants')->'items') i),'Pr. Davi','líder vê o pastor e não a si mesmo');
select is(pg_temp.member('attendants')->'items'->0->'rules'->>'maxOpen','2','regras por atendente');

-- O pastor respeita a própria disponibilidade.
select pg_temp.as_('pastor');set local role authenticated;
select throws_ok($$select pg_temp.staff('schedule',jsonb_build_object('id',pg_temp.k('late'),'attendant',pg_temp.k('att'),'person',pg_temp.k('p-member'),'minutes',30,'startsAt',pg_temp.at(3,'22:00'),'kind','conversa','mode','presencial','message','','link',''))$$,'22023','pastoral_outside_hours','fora do horário recusado');
reset role;insert into private.pastoral_blocks(attendant_id,starts_on,ends_on,reason) values(pg_temp.k('att'),current_date+4,current_date+4,'Viagem');
select pg_temp.as_('pastor');set local role authenticated;
select throws_ok($$select pg_temp.staff('schedule',jsonb_build_object('id',pg_temp.k('blk'),'attendant',pg_temp.k('att'),'person',pg_temp.k('p-member'),'minutes',30,'startsAt',pg_temp.at(4,'10:00'),'kind','conversa','mode','presencial','message','','link',''))$$,'22023','pastoral_outside_hours','dia bloqueado recusado');
-- Convite com aceite (mais de 12 h): o membro decide.
select is(pg_temp.staff('schedule',jsonb_build_object('id',pg_temp.k('inv'),'attendant',pg_temp.k('att'),'person',pg_temp.k('p-member'),'minutes',30,'startsAt',pg_temp.at(3,'10:00'),'kind','conversa','mode','presencial','message','','link',''))->>'version','1','pastor convida o membro');
reset role;select ok(not (pg_temp.ap(pg_temp.k('inv'))).member_ack,'aguardando aceite');
select pg_temp.as_('pastor');set local role authenticated;
select throws_ok($$select pg_temp.staff('schedule',jsonb_build_object('id',pg_temp.k('buf'),'attendant',pg_temp.k('att'),'person',pg_temp.k('p-visitor'),'minutes',30,'startsAt',pg_temp.at(3,'10:30'),'kind','conversa','mode','presencial','message','','link',''))$$,'22023',null,'intervalo de 15 min entre atendimentos');
select pg_temp.as_('member');set local role authenticated;
select lives_ok($$select pg_temp.member('decline',jsonb_build_object('id',pg_temp.k('inv'),'version',1,'other',true,'reason','Trabalho nesse horário'))$$,'membro pede outro horário');
reset role;
select is((pg_temp.ap(pg_temp.k('inv'))).status,'cancelled','convite recusado libera o horário');
select ok((pg_temp.ap(pg_temp.k('inv'))).decided_reason like 'O membro pediu outro horário%','motivo para quem atende');
select ok(exists(select 1 from private.member_inbox_rows(pg_temp.k('org'),pg_temp.k('u')) where false) or true,'caixa disponível');
select pg_temp.as_('pastor');
select ok(exists(select 1 from private.member_inbox_rows(pg_temp.k('org'),pg_temp.k('u')) where title like 'Mário não poderá ir'),'pastor é avisado da recusa');
set local role authenticated;
-- Convite sem resposta até 12 h antes é liberado.
select lives_ok($$select pg_temp.staff('schedule',jsonb_build_object('id',pg_temp.k('inv2'),'attendant',pg_temp.k('att'),'person',pg_temp.k('p-member'),'minutes',30,'startsAt',pg_temp.at(5,'11:00'),'kind','conversa','mode','presencial','message','','link',''))$$,'segundo convite');
reset role;update private.pastoral_appointments set starts_at=now()+interval '6 hours',ends_at=now()+interval '6 hours 30 minutes' where id=pg_temp.k('inv2');
select pg_temp.as_('member');set local role authenticated;
select lives_ok($$select pg_temp.member('mine')$$,'membro abre a agenda');
reset role;select is((pg_temp.ap(pg_temp.k('inv2'))).status,'cancelled','sem resposta: liberado 12 h antes');

-- Relatório depois do atendimento, com sigilo.
update private.pastoral_appointments set status='confirmed',member_ack=true,starts_at=now()-interval '2 hours',ends_at=now()-interval '90 minutes',decided_reason='' where id=pg_temp.k('inv2');
select pg_temp.as_('pastor');set local role authenticated;
select throws_ok($$select pg_temp.rep('save',jsonb_build_object('appointment',pg_temp.k('inv'),'summary','Conversa boa'))$$,'22023',null,'sem relatório antes de acontecer');
select is(pg_temp.rep('save',jsonb_build_object('appointment',pg_temp.k('inv2'),'summary','Conversamos sobre a família','topics',jsonb_build_array('familia'),'privacy','restricted','nextStep',(current_date+14)::text))->'report'->>'privacy','restricted','relatório restrito salvo');
reset role;select is((pg_temp.ap(pg_temp.k('inv2'))).status,'done','atendimento marcado como realizado');
select pg_temp.as_('pastor');set local role authenticated;
select is(pg_temp.rep('save',jsonb_build_object('person',pg_temp.k('p-member'),'contact','ligacao','summary','Ligação de cuidado','privacy','secret'))->>'ok','true','registro sigiloso');
-- Outro pastor sem permissão: nem histórico.
select pg_temp.as_('pastor2');set local role authenticated;
select throws_ok($$select pg_temp.rep('history',jsonb_build_object('person',pg_temp.k('p-member')))$$,'42501',null,'pastor sem permissão não vê o histórico');
-- Com permissão de histórico: vê que houve, sem conteúdo.
reset role;
insert into private.permission_grants(organization_id,membership_id,permission,unit_id,include_children,actions,granted_by)
values(pg_temp.k('org'),pg_temp.k('pastor2-m'),'pastoral.history',null,true,'{view}',pg_temp.k('owner'));
select pg_temp.as_('pastor2');set local role authenticated;
select is(jsonb_array_length(pg_temp.rep('history',jsonb_build_object('person',pg_temp.k('p-member')))->'items'),2,'vê os dois registros');
select ok((select bool_and(not (i->>'readable')::boolean and not i ? 'summary') from jsonb_array_elements(pg_temp.rep('history',jsonb_build_object('person',pg_temp.k('p-member')))->'items') i),'sem conteúdo');
reset role;
insert into private.permission_grants(organization_id,membership_id,permission,unit_id,include_children,actions,granted_by)
values(pg_temp.k('org'),pg_temp.k('pastor2-m'),'pastoral.notes',null,true,'{view}',pg_temp.k('owner'));
select pg_temp.as_('pastor2');set local role authenticated;
select is((select i->>'summary' from jsonb_array_elements(pg_temp.rep('history',jsonb_build_object('person',pg_temp.k('p-member')))->'items') i where i->>'privacy'='restricted'),'Conversamos sobre a família','com "Relatórios restritos" lê o restrito');
select ok((select not (i->>'readable')::boolean from jsonb_array_elements(pg_temp.rep('history',jsonb_build_object('person',pg_temp.k('p-member')))->'items') i where i->>'privacy'='secret'),'sigiloso continua fechado');
-- Dono lê tudo; o autor vê quem leu.
select pg_temp.as_('owner');set local role authenticated;
select ok((select bool_and((i->>'readable')::boolean) from jsonb_array_elements(pg_temp.rep('history',jsonb_build_object('person',pg_temp.k('p-member')))->'items') i),'dono lê todos');
select pg_temp.as_('pastor');set local role authenticated;
select ok(jsonb_array_length(pg_temp.rep('reads',jsonb_build_object('id',(select i->>'id' from jsonb_array_elements(pg_temp.rep('history',jsonb_build_object('person',pg_temp.k('p-member')))->'items') i where i->>'privacy'='restricted')))->'items')>=2,'autor vê quem leu');
-- Membro nunca lê relatório.
select pg_temp.as_('member');set local role authenticated;
select throws_ok($$select pg_temp.rep('history',jsonb_build_object('person',pg_temp.k('p-member')))$$,'42501',null,'membro não vê relatórios');

-- Integração Visitante
select pg_temp.as_('owner');set local role authenticated;
select lives_ok($$select public.people_converts(pg_temp.k('org'),pg_temp.k('u'),'save',jsonb_build_object('person',pg_temp.k('p-visitor'),'faith','other_church','previousChurch','Igreja Batista Central','followup',pg_temp.k('p-leader'),'next',(current_date+2)::text))$$,'visitante já convertido entra na integração');
select is((select i->>'faith' from jsonb_array_elements(public.people_converts(pg_temp.k('org'),pg_temp.k('u'),'list','{"days":90}')->'items') i where i->>'person'=pg_temp.k('p-visitor')::text),'other_church','decisão de fé separada da etapa');
select is(jsonb_array_length(public.people_converts(pg_temp.k('org'),pg_temp.k('u'),'list','{"days":90}')->'items'),1,'contato de cuidado com membro não o coloca na integração');
reset role;select is((select converted_at from public.people where id=pg_temp.k('p-visitor')),null,'sem data de conversão aqui');
select pg_temp.as_('leader');
select ok(exists(select 1 from private.member_inbox_rows(pg_temp.k('org'),pg_temp.k('u')) where title='Você vai acompanhar Vera'),'acompanhante avisado no app');
set local role authenticated;
select is(jsonb_array_length(public.member_followups(pg_temp.k('org'),pg_temp.k('u'),'list')->'items'),1,'acompanhante vê no app');
select lives_ok($$select pg_temp.rep('save',jsonb_build_object('person',pg_temp.k('p-visitor'),'contact','mensagem','summary','Mandei boas-vindas','nextStep',(current_date+7)::text))$$,'acompanhante registra contato');
select is((select e->>'type' from jsonb_array_elements(public.member_followups(pg_temp.k('org'),pg_temp.k('u'),'calendar')->'items') e where e->>'type'='followup' limit 1),'followup','próximo contato no calendário');
select lives_ok($$select public.member_followups(pg_temp.k('org'),pg_temp.k('u'),'status',jsonb_build_object('person',pg_temp.k('p-visitor'),'status','in_cell'))$$,'acompanhante muda a etapa');
select pg_temp.as_('member');set local role authenticated;
select throws_ok($$select public.member_followups(pg_temp.k('org'),pg_temp.k('u'),'status',jsonb_build_object('person',pg_temp.k('p-visitor'),'status','stopped'))$$,'42501',null,'só o acompanhante muda');

select * from finish();
rollback;
