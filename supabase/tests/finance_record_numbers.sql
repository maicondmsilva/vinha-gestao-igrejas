reset role;
select ok(not has_function_privilege('authenticated','public.finance_receiver_manual_key(uuid,uuid,uuid,jsonb)','execute'),'cliente não fabrica validação técnica de chave');
select ok(not has_table_privilege('authenticated','private.record_counters','update'),'contador não é editável pelo cliente');
select ok(not has_function_privilege('anon','public.record_numbering(uuid,text,jsonb)','execute'),'visitante não consulta códigos');
select is((select count(*) from private.finance_record_numbers where organization_id=current_setting('f4.org')::uuid),(select count(*) from private.finance_entries where organization_id=current_setting('f4.org')::uuid),'todos os lançamentos têm código');
select is((select count(distinct number) from private.finance_record_numbers where organization_id=current_setting('f4.org')::uuid and unit_id=current_setting('f4.unit')::uuid),(select count(*) from private.finance_record_numbers where organization_id=current_setting('f4.org')::uuid and unit_id=current_setting('f4.unit')::uuid),'códigos financeiros não repetem na igreja');
select is((select min(number)::text from private.finance_record_numbers where organization_id=current_setting('f4.org')::uuid and unit_id=current_setting('f4.unit')::uuid),'1','sequência financeira começa em 1');
insert into public.people(id,organization_id,unit_id,full_name) values
('ab510000-0000-4000-8000-000000000001',current_setting('f4.org')::uuid,current_setting('f4.unit')::uuid,'Membro fictício um'),
('ab510000-0000-4000-8000-000000000002',current_setting('f4.org')::uuid,'cf400000-0000-4000-8000-000000000002','Membro fictício dois');
select is((select ministry_number::text from private.member_record_numbers where person_id='ab510000-0000-4000-8000-000000000002'),'2','número geral avança entre igrejas');
select is((select unit_number::text from private.member_record_numbers where person_id='ab510000-0000-4000-8000-000000000002'),'1','igreja possui sequência própria');
set local role authenticated;
select is(public.record_numbering(current_setting('f4.org')::uuid,'set_mode','{"mode":"unit"}')->>'mode','unit','proprietário altera preferência do ministério');
select is(public.record_numbering(current_setting('f4.org')::uuid,'people','{"ids":["ab510000-0000-4000-8000-000000000002"]}')->'codes'->>'ab510000-0000-4000-8000-000000000002','1','código exibido respeita preferência por igreja');
select is(public.record_numbering(current_setting('f4.org')::uuid,'set_mode','{"mode":"ministry"}')->>'mode','ministry','preferência geral restaurada sem recriar pessoas');
select is(public.record_numbering(current_setting('f4.org')::uuid,'people','{"ids":["ab510000-0000-4000-8000-000000000002"]}')->'codes'->>'ab510000-0000-4000-8000-000000000002','2','mesma pessoa exibe número geral');
select public.finance_f1(current_setting('f4.org')::uuid,array[current_setting('f4.unit')::uuid],'entry',jsonb_build_object('id','ab520000-0000-4000-8000-000000000001','kind','income','amountCents','10000','description','Previsão fictícia','account','df400000-0000-4000-8000-000000000001','category','df400000-0000-4000-8000-000000000002','competence',current_date,'due',current_date,'method','pix'));
select set_config('records.edit',jsonb_build_object('id','ab530000-0000-4000-8000-000000000001','title','ab520000-0000-4000-8000-000000000001','version',1,'amountCents','12000','description','Previsão revisada','account','df400000-0000-4000-8000-000000000001','category','df400000-0000-4000-8000-000000000002','center','','competence',current_date,'due',current_date+1,'method','pix','notes','Revisão fictícia')::text,true);
select lives_ok($$select public.finance_revise_pending(current_setting('f4.org')::uuid,current_setting('f4.unit')::uuid,current_setting('records.edit')::jsonb)$$,'edição de previsão manual autorizada');
select lives_ok($$select public.finance_revise_pending(current_setting('f4.org')::uuid,current_setting('f4.unit')::uuid,current_setting('records.edit')::jsonb)$$,'repetição do pedido não repete edição');
select throws_ok($$select public.finance_revise_pending(current_setting('f4.org')::uuid,current_setting('f4.unit')::uuid,current_setting('records.edit')::jsonb||'{"id":"ab530000-0000-4000-8000-000000000002"}')$$,'40001',null,'edição com versão antiga recusada');
reset role;
select is((select version from private.finance_entries where id='ab520000-0000-4000-8000-000000000001'),2,'versão incrementada uma vez');
select is((select amount_cents::text from private.finance_entries where id='ab520000-0000-4000-8000-000000000001'),'12000','novo valor registrado');
select is((select count(*)::integer from private.finance_provider_accounts where receiver_id='ff400000-0000-4000-8000-000000000001'),1,'provedor conectado ganhou conta sem duplicação');
select lives_ok($$select private.finance_receiver_manual_key('af400000-0000-4000-8000-000000000001',current_setting('f4.org')::uuid,current_setting('f4.unit')::uuid,'{"provider":"safe2pay","environment":"sandbox","version":0,"sealed":"synthetic-encrypted-payload-only-not-real-key"}')$$,'chave manual protegida aceita no serviço autorizado');
select is((select status from private.finance_receivers where organization_id=current_setting('f4.org')::uuid and provider='safe2pay'),'reauthorize','chave sem prova não ativa recebimentos');
select is((select count(*)::integer from private.finance_provider_accounts a join private.finance_receivers r on r.id=a.receiver_id where r.organization_id=current_setting('f4.org')::uuid and r.provider='safe2pay'),0,'chave pendente não gera conta ativa fictícia');
