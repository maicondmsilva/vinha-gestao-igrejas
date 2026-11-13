begin;
create extension if not exists pgtap with schema extensions;
select no_plan();
-- Pessoas · gestão: busca com filtros, duplicados (lista, unificar, dispensar), histórico, novos convertidos e ações em lote.
create function pg_temp.x(t text) returns uuid language sql immutable as $$select md5('people-mgmt-'||t)::uuid$$;
create function pg_temp.actor(t text) returns text language sql as $$select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.x(t),'role','authenticated','email',t||'-pm@example.invalid')::text,true)$$;
create function pg_temp.search(f jsonb, pg int default 1, lim int default 25) returns jsonb language sql as $$select public.people_search(pg_temp.x('org'),pg_temp.x('unit'),f,pg,lim)$$;
create function pg_temp.names(f jsonb) returns text language sql as $$
 select coalesce(string_agg(p.full_name,',' order by p.full_name),'') from jsonb_array_elements_text(pg_temp.search(f)->'ids') i join public.people p on p.id=i::uuid$$;
create function pg_temp.dup(a text, d jsonb default '{}') returns jsonb language sql as $$select public.people_duplicates(pg_temp.x('org'),pg_temp.x('unit'),a,d)$$;
create function pg_temp.conv(a text, d jsonb default '{}') returns jsonb language sql as $$select public.people_converts(pg_temp.x('org'),pg_temp.x('unit'),a,d)$$;
create function pg_temp.bulk(a text, d jsonb) returns jsonb language sql as $$select public.people_bulk(pg_temp.x('org'),pg_temp.x('unit'),a,d)$$;
create function pg_temp.person(t text) returns public.people language sql security definer as $$select * from public.people where id=pg_temp.x(t)$$;
create function pg_temp.count_rows(q text) returns bigint language plpgsql security definer as $$declare n bigint; begin execute q into n; return n; end $$;
create function pg_temp.today() returns date language sql stable as $$select (now() at time zone 'America/Sao_Paulo')::date$$;

insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
select pg_temp.x(u),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',u||'-pm@example.invalid',now(),now(),now()
from unnest(array['owner','sec','member','login1','login2']) u;
insert into public.organizations(id,name,slug,status) values(pg_temp.x('org'),'Gestão fictícia','people-mgmt-test','active');
insert into public.organization_units(id,organization_id,name,slug,unit_type) values
 (pg_temp.x('unit'),pg_temp.x('org'),'Sede','sede','headquarters'),(pg_temp.x('unit2'),pg_temp.x('org'),'Bairro','bairro','campus');
insert into public.organization_memberships(id,organization_id,user_id,role,status,default_unit_id) values
 (pg_temp.x('owner-m'),pg_temp.x('org'),pg_temp.x('owner'),'owner','active',pg_temp.x('unit')),
 (pg_temp.x('sec-m'),pg_temp.x('org'),pg_temp.x('sec'),'secretary','active',pg_temp.x('unit')),
 (pg_temp.x('member-m'),pg_temp.x('org'),pg_temp.x('member'),'member','active',pg_temp.x('unit'));
insert into public.membership_unit_access(membership_id,organization_id,unit_id,access_level,include_children)
 values(pg_temp.x('sec-m'),pg_temp.x('org'),pg_temp.x('unit'),'manage',false);
insert into public.people(id,organization_id,unit_id,full_name,email,phone,cpf,birth_date,gender,baptized,journey_status,tags,status,created_at) values
 (pg_temp.x('ana'),pg_temp.x('org'),pg_temp.x('unit'),'Ana Souza','ana@example.invalid','(11) 98888-1111',null,(pg_temp.today()-interval '30 years')::date,'Feminino',true,'Membro','{louvor}','active',now()-interval '10 days'),
 (pg_temp.x('ana2'),pg_temp.x('org'),pg_temp.x('unit'),'ANA  SOUZA',null,'11988881111','123.456.789-01',null,null,false,'Visitante','{novos}','active',now()-interval '2 days'),
 (pg_temp.x('bruno'),pg_temp.x('org'),pg_temp.x('unit'),'Bruno Lima',null,'(11) 97777-2222','12345678901',(pg_temp.today()-interval '15 years')::date,'Masculino',false,'Em integração','{}','active',now()-interval '9 days'),
 (pg_temp.x('caio'),pg_temp.x('org'),pg_temp.x('unit'),'Caio Reis',null,null,null,(pg_temp.today()-interval '45 years')::date,'Masculino',true,'Membro','{louvor}','active',now()-interval '8 days'),
 (pg_temp.x('outra'),pg_temp.x('org'),pg_temp.x('unit2'),'Ana Souza',null,null,null,null,'Feminino',false,'Membro','{}','active',now()-interval '7 days'),
 (pg_temp.x('l1'),pg_temp.x('org'),pg_temp.x('unit'),'Duda Login',null,null,null,null,null,false,'Membro','{}','active',now()-interval '6 days'),
 (pg_temp.x('l2'),pg_temp.x('org'),pg_temp.x('unit'),'Duda Login',null,null,null,null,null,false,'Membro','{}','active',now()-interval '5 days');
update public.people set auth_user_id=pg_temp.x('login1') where id=pg_temp.x('l1');
update public.people set auth_user_id=pg_temp.x('login2') where id=pg_temp.x('l2');
-- Células e redes: Caio na célula A (rede mãe), Ana na célula B (sub-rede).
insert into public.church_cells(id,organization_id,unit_id,name,meeting_day,meeting_time,meeting_format,created_by) values
 (pg_temp.x('cellA'),pg_temp.x('org'),pg_temp.x('unit'),'Célula Aurora',1,'19:00','presential',pg_temp.x('owner')),
 (pg_temp.x('cellB'),pg_temp.x('org'),pg_temp.x('unit'),'Célula Brisa',2,'19:00','presential',pg_temp.x('owner'));
insert into public.church_cell_networks(id,organization_id,unit_id,name,status,created_by) values
 (pg_temp.x('netMae'),pg_temp.x('org'),pg_temp.x('unit'),'Rede Mãe','active',pg_temp.x('owner')),
 (pg_temp.x('netFilha'),pg_temp.x('org'),pg_temp.x('unit'),'Rede Filha','active',pg_temp.x('owner'));
insert into public.church_cell_network_parents(network_id,organization_id,unit_id,parent_id,updated_by) values(pg_temp.x('netFilha'),pg_temp.x('org'),pg_temp.x('unit'),pg_temp.x('netMae'),pg_temp.x('owner'));
insert into public.church_cell_network_links(cell_id,organization_id,unit_id,network_id,updated_by) values
 (pg_temp.x('cellA'),pg_temp.x('org'),pg_temp.x('unit'),pg_temp.x('netMae'),pg_temp.x('owner')),
 (pg_temp.x('cellB'),pg_temp.x('org'),pg_temp.x('unit'),pg_temp.x('netFilha'),pg_temp.x('owner'));
insert into public.church_cell_participants(id,organization_id,unit_id,cell_id,person_id,status,created_by) values
 (pg_temp.x('cp1'),pg_temp.x('org'),pg_temp.x('unit'),pg_temp.x('cellA'),pg_temp.x('caio'),'active',pg_temp.x('owner')),
 (pg_temp.x('cp2'),pg_temp.x('org'),pg_temp.x('unit'),pg_temp.x('cellB'),pg_temp.x('ana2'),'active',pg_temp.x('owner')),
 (pg_temp.x('cp3'),pg_temp.x('org'),pg_temp.x('unit'),pg_temp.x('cellB'),pg_temp.x('ana'),'active',pg_temp.x('owner'));
insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(pg_temp.x('org'),pg_temp.x('owner'),'person.updated','person',pg_temp.x('ana2')::text,'{}');

set local role authenticated;
select pg_temp.actor('owner');
-- Busca com filtros
select is((pg_temp.search('{}')->>'total')::int,6,'lista só a igreja escolhida');
select is(pg_temp.names('{"gender":"Masculino"}'),'Bruno Lima,Caio Reis','filtro por gênero');
select is(pg_temp.names('{"baptized":true}'),'Ana Souza,Caio Reis','filtro por batismo');
select is(pg_temp.names('{"ageMin":18,"ageMax":40}'),'Ana Souza','faixa etária');
select is(pg_temp.names('{"ageMax":17}'),'Bruno Lima','menores de idade');
select is(pg_temp.names(jsonb_build_object('cell',pg_temp.x('cellA'))),'Caio Reis','filtro por célula');
select is(pg_temp.names(jsonb_build_object('network',pg_temp.x('netMae'))),'ANA  SOUZA,Ana Souza,Caio Reis','rede inclui as sub-redes');
select is(pg_temp.names(jsonb_build_object('network',pg_temp.x('netFilha'))),'ANA  SOUZA,Ana Souza','sub-rede sozinha');
select is(pg_temp.names('{"tag":"louvor","status":"Membro"}'),'Ana Souza,Caio Reis','marcador e etapa');
select is(pg_temp.names('{"q":"97777"}'),'Bruno Lima','busca por telefone');
select is(jsonb_array_length(pg_temp.search('{}',2,4)->'ids'),2,'paginação');
select throws_ok($$select pg_temp.search('{"x":1}')$$,'22023',null,'filtro desconhecido recusado');
select throws_ok($$select pg_temp.search('{"cell":"abc"}')$$,'22023',null,'célula inválida recusada');

-- Duplicados
select is((select count(*)::int from jsonb_array_elements(pg_temp.dup('list')->'pairs') p
  where array[p#>>'{a,id}',p#>>'{b,id}']<@array[pg_temp.x('ana')::text,pg_temp.x('ana2')::text]),1,'Ana e ANA SOUZA aparecem como possível duplicado');
select ok((select p->'reasons' from jsonb_array_elements(pg_temp.dup('list')->'pairs') p where array[p#>>'{a,id}',p#>>'{b,id}']<@array[pg_temp.x('ana')::text,pg_temp.x('ana2')::text]) ?& array['name','phone'],'motivos: nome e telefone');
select ok((select p->'reasons' from jsonb_array_elements(pg_temp.dup('list')->'pairs') p where array[p#>>'{a,id}',p#>>'{b,id}']<@array[pg_temp.x('ana2')::text,pg_temp.x('bruno')::text]) ? 'cpf','mesmo CPF com nomes diferentes');
select ok((select p#>>'{b,cpf}' from jsonb_array_elements(pg_temp.dup('list')->'pairs') p where p#>>'{b,id}'=pg_temp.x('ana2')::text or p#>>'{a,id}'=pg_temp.x('ana2')::text limit 1) not like '%456%','CPF aparece mascarado');
select pg_temp.dup('dismiss',jsonb_build_object('keep',pg_temp.x('ana2'),'remove',pg_temp.x('bruno')));
select ok(not exists(select 1 from jsonb_array_elements(pg_temp.dup('list')->'pairs') p where array[p#>>'{a,id}',p#>>'{b,id}']<@array[pg_temp.x('ana2')::text,pg_temp.x('bruno')::text]),'par dispensado some da lista');
select throws_ok(format($$select pg_temp.dup('merge','{"keep":"%s","remove":"%s"}')$$,pg_temp.x('l1'),pg_temp.x('l2')),'55000',null,'não unifica duas pessoas com acesso ao app');
select is((pg_temp.dup('merge',jsonb_build_object('keep',pg_temp.x('ana'),'remove',pg_temp.x('ana2')))->>'ok')::boolean,true,'unifica');
select is(pg_temp.count_rows(format('select count(*) from public.people where id=%L',pg_temp.x('ana2'))),0::bigint,'cadastro duplicado removido');
select is((pg_temp.person('ana')).cpf,'123.456.789-01','dado que faltava foi copiado');
select is((pg_temp.person('ana')).tags,array['louvor','novos'],'marcadores somados');
select is((pg_temp.person('ana')).journey_status,'Membro','fica a etapa mais avançada');
select is(pg_temp.count_rows(format('select count(*) from public.church_cell_participants where person_id=%L',pg_temp.x('ana'))),1::bigint,'participação repetida na célula vira uma só');
select is(pg_temp.count_rows(format($q$select count(*) from public.audit_logs where entity_type='person' and entity_id=%L and action='person.updated'$q$,pg_temp.x('ana'))),1::bigint,'histórico do duplicado vem junto');

-- Histórico
select ok((select bool_or(e->>'title'='Cadastro duplicado unificado') from jsonb_array_elements(public.person_timeline(pg_temp.x('org'),pg_temp.x('ana'))) e),'histórico mostra a unificação');
select ok((select bool_or(e->>'title'='Entrou na célula' and e->>'detail'='Célula Brisa') from jsonb_array_elements(public.person_timeline(pg_temp.x('org'),pg_temp.x('ana'))) e),'histórico mostra a célula');
select ok((select bool_or(e->>'title'='Cadastro criado') from jsonb_array_elements(public.person_timeline(pg_temp.x('org'),pg_temp.x('caio'))) e),'histórico começa no cadastro');

-- Novos convertidos
select is((pg_temp.conv('save',jsonb_build_object('person',pg_temp.x('bruno'),'followup',pg_temp.x('caio'),'note','Ligar no sábado'))->>'ok')::boolean,true,'registra decisão (hoje)');
select is((pg_temp.person('bruno')).converted_at,pg_temp.today(),'data da decisão');
select is(pg_temp.conv('list')#>>'{items,0,followupName}','Caio Reis','responsável pelo acompanhamento');
select is(pg_temp.conv('list')#>>'{counts,pending}','1','aguardando contato');
select pg_temp.conv('save',jsonb_build_object('person',pg_temp.x('bruno'),'status','in_cell'));
select is(pg_temp.conv('list')#>>'{items,0,status}','in_cell','etapa do acompanhamento');
select is(pg_temp.conv('list')#>>'{items,0,note}','Ligar no sábado','observação mantida');
select is(pg_temp.names('{"converts":true}'),'Bruno Lima','filtro de novos convertidos');
select throws_ok(format($$select pg_temp.conv('save','{"person":"%s","status":"x"}')$$,pg_temp.x('bruno')),'22023',null,'etapa inválida');
select throws_ok(format($$select pg_temp.conv('save','{"person":"%s","convertedAt":"2999-01-01"}')$$,pg_temp.x('bruno')),'22023',null,'data futura recusada');

-- Ações em lote
select is((pg_temp.bulk('journey',jsonb_build_object('ids',jsonb_build_array(pg_temp.x('bruno'),pg_temp.x('caio')),'value','Membro'))->>'updated')::int,1,'muda etapa só de quem precisa');
select is((pg_temp.person('bruno')).journey_status,'Membro','etapa alterada');
select is((pg_temp.bulk('tag',jsonb_build_object('ids',jsonb_build_array(pg_temp.x('bruno'),pg_temp.x('caio')),'value','Retiro 2026'))->>'updated')::int,2,'adiciona marcador');
select is((pg_temp.bulk('untag',jsonb_build_object('ids',jsonb_build_array(pg_temp.x('caio')),'value','Retiro 2026'))->>'updated')::int,1,'remove marcador');
select is((pg_temp.person('bruno')).tags,array['Retiro 2026'],'marcador gravado');
select ok((select bool_or(e->>'title'='Etapa alterada em lote') from jsonb_array_elements(public.person_timeline(pg_temp.x('org'),pg_temp.x('bruno'))) e),'lote aparece no histórico');
select is((pg_temp.bulk('notify_preview',jsonb_build_object('ids',jsonb_build_array(pg_temp.x('bruno'))))->>'selected')::int,1,'prévia do comunicado');
select is((pg_temp.bulk('notify',jsonb_build_object('ids',jsonb_build_array(pg_temp.x('bruno'),pg_temp.x('caio')),'title','Ensaio extra','body','Sábado às 15h na sede.','request',pg_temp.x('req1')))->>'ok')::boolean,true,'comunicado criado');
select is(pg_temp.count_rows(format($q$select count(*) from private.push_campaigns where request_id=%L and audience ? 'people' and status='scheduled'$q$,pg_temp.x('req1'))),1::bigint,'notificação para as pessoas escolhidas');
select throws_ok(format($$select pg_temp.bulk('journey','{"ids":["%s"],"value":"Líder"}')$$,pg_temp.x('bruno')),'22023',null,'etapa inválida em lote');
select throws_ok(format($$select pg_temp.bulk('tag','{"ids":["%s"],"value":"x"}')$$,pg_temp.x('outra')),'42501',null,'lote só com pessoas da igreja selecionada');

-- Acesso
select pg_temp.actor('sec');
select is((pg_temp.search('{}')->>'total')::int,5,'secretaria busca na igreja dela');
select throws_ok($$select public.people_search(pg_temp.x('org'),pg_temp.x('unit2'),'{}',1,25)$$,'42501',null,'secretaria não busca em outra igreja');
select pg_temp.actor('member');
select throws_ok($$select pg_temp.search('{}')$$,'42501',null,'membro comum não busca');
select throws_ok($$select pg_temp.dup('list')$$,'42501',null,'membro comum não vê duplicados');
select throws_ok(format($$select public.person_timeline(pg_temp.x('org'),'%s')$$,pg_temp.x('caio')),'42501',null,'membro comum não vê histórico');
select throws_ok($$select pg_temp.conv('list')$$,'42501',null,'membro comum não vê convertidos');
reset role;
select ok(not has_function_privilege('anon','public.people_bulk(uuid,uuid,text,jsonb)','EXECUTE'),'lote não é anônimo');
select * from finish();
rollback;
