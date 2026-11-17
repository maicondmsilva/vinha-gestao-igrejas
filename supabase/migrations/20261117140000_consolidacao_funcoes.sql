-- Consolidação das funções que mais receberam ajustes (docs/ANALISE-ARQUITETURA-LAYOUT-SEGURANCA.md, item 3).
-- 1) Caixa de notificações do app: 12 camadas (cada uma chamava a anterior renomeada) viram UMA função.
--    Alterações futuras acrescentam o novo bloco direto aqui (ou em nova migração com a função inteira),
--    sem renomear a versão anterior.
-- 2) Versões canônicas, com o texto completo, das funções ajustadas por substituição de trechos:
--    pastoral_staff, pastoral_member, people_search, pastoral_row e ministry_language_save.
--    Próximas mudanças partem deste texto, não de buscar e trocar trechos.
-- Comportamento igual ao atual (mesmos testes). Única diferença intencional: a caixa passa a escolher
-- as 100 notificações mais recentes de todas as fontes juntas (antes cada camada cortava em 100 por conta própria).

create or replace function private.member_inbox_rows(p_org uuid, p_unit uuid)
returns table(message_key text, title text, body text, occurred_at timestamptz, target text, target_id uuid)
language sql stable security definer set search_path to '' as $function$
 select * from (
  select * from (
   -- Conteúdos, eventos, ingressos, revisão de cadastro e transferência de igreja
   select 'post:'||p.id as message_key,p.title,p.body,p.created_at as occurred_at,'content'::text as target,p.id as target_id from private.member_publications p
 join public.organization_units u on u.id=p.unit_id and u.organization_id=p.organization_id and u.status='active'
 where p.organization_id=p_org and p.unit_id=p_unit and p.published and p.created_at>now()-interval '90 days'
 union all
 select 'event:'||e.id||':'||e.version,e.title,case when e.status='cancelled' then 'Evento cancelado pela igreja.' else 'Programação publicada ou atualizada. Confira data e local.' end,e.updated_at,'agenda',e.id
 from private.church_app_events e where e.organization_id=p_org and e.unit_id=p_unit and e.status in('published','cancelled') and e.updated_at>now()-interval '90 days' and private.member_event_enabled(p_org,p_unit)
 union all
 select 'ticket:'||r.id||':'||r.version||':'||e.version,e.title,case when e.status='cancelled' then 'Evento cancelado. Seu ticket não permite entrada.' when r.status='cancelled' then 'Sua inscrição foi cancelada.' when r.checked_in_at is not null then 'Sua entrada foi confirmada.' else 'Sua inscrição gratuita está confirmada. Consulte seu ticket.' end,greatest(r.updated_at,e.updated_at),'ticket',r.id
 from private.church_app_registrations r join private.church_app_events e on e.id=r.event_id where r.organization_id=p_org and r.user_id=auth.uid()
 union all
 select 'profile:'||r.id||':'||r.status,'Revisão do cadastro',coalesce(r.reason,'Sua solicitação foi revisada.'),r.reviewed_at,'profile',r.id from private.member_profile_requests r where r.organization_id=p_org and r.user_id=auth.uid() and r.status<>'pending'
 union all
 select 'transfer:'||r.id||':'||r.status,'Transferência de igreja',case when r.status='approved' then 'Transferência aprovada. ' when r.status='rejected' then 'Transferência recusada. ' else 'Solicitação cancelada. ' end||r.reason,r.reviewed_at,'church',r.id from private.member_church_transfers r where r.organization_id=p_org and r.user_id=auth.uid() and r.status<>'pending'
   union all
   -- Comunidade: pedidos de oração, testemunhos e participação em ministérios
   select 'prayer:'||id||':'||version,'Pedido de oração atualizado',case status when 'care' then 'A equipe está acompanhando seu pedido.' when 'completed' then 'A equipe concluiu o acompanhamento.' else 'Pedido cancelado.' end,updated_at,'prayers',id from private.community_prayers where organization_id=p_org and user_id=auth.uid() and status<>'pending'
 union all select 'testimony:'||id||':'||version,'Seu testemunho',case status when 'published' then 'Seu testemunho foi aprovado e publicado.' when 'rejected' then 'Sua publicação não foi aprovada. Consulte o motivo.' else 'Publicação retirada a seu pedido.' end,updated_at,'testimonies',id from private.community_testimonies where organization_id=p_org and user_id=auth.uid() and status<>'pending'
 union all select 'participation:'||id||':'||version,'Participação em ministério',case status when 'approved' then 'Sua participação foi aprovada.' when 'rejected' then 'Solicitação revisada. Consulte o motivo.' else 'Sua participação foi encerrada.' end,updated_at,'groups',id from private.community_participation where organization_id=p_org and user_id=auth.uid() and status<>'pending'
   union all
   -- Jornadas concluídas, solicitações de família/Kids e participação em células
   select 'learning:'||e.id||':'||e.version,'Leitura e jornada concluída',p.title||' — todas as etapas foram marcadas como concluídas.',e.completed_at,'learning',e.program_id from private.learning_enrollments e join private.learning_programs p on p.id=e.program_id where e.organization_id=p_org and e.user_id=auth.uid() and e.completed_at is not null
 union all select 'family:'||r.id||':'||r.version,case when r.kind='cell.leave' then 'Solicitação de grupo atualizada' else 'Solicitação Kids atualizada' end,'A igreja revisou sua solicitação. Consulte a decisão na sua área privada.',r.updated_at,case when r.kind='cell.leave' then 'cells' else 'kids' end,r.id from private.member_family_requests r where r.organization_id=p_org and r.user_id=auth.uid() and r.status in('approved','rejected')
 union all select 'cell-participation:'||r.id||':'||r.version,'Participação em grupo atualizada','Consulte sua solicitação e os grupos da igreja.',r.updated_at,'cells',r.cell_id from private.cell_referrals r where r.organization_id=p_org and r.created_by=auth.uid() and r.status in('accepted','rejected')
   union all
   -- Mensagens de eventos
   select 'event-message:'||m.id::text,m.title,m.body,m.scheduled_at,'agenda'::text,m.event_id from private.event_messages m join private.church_app_events e on e.id=m.event_id where m.organization_id=p_org and m.state='scheduled' and m.scheduled_at<=now() and m.scheduled_at>now()-interval '90 days' and e.status in('published','cancelled') and private.event_message_authorized(m) and private.member_event_enabled(e.organization_id,e.unit_id) and private.event_message_matches(m,auth.uid())
   union all
   -- Cadastro que precisa de ajuste
   select 'profile-review:'||r.id::text,
   'Seu cadastro precisa de ajuste'::text,
   'O que precisa ajustar: '||(select string_agg(x,', ') from jsonb_array_elements_text(private.member_profile_rejected_fields(r.payload,r.accepted_fields)) x)
    ||'. Motivo: '||coalesce(r.reason,'')||'. Toque para corrigir seu cadastro.',
   r.reviewed_at,'profile'::text,r.id
  from private.member_profile_requests r
  where r.organization_id=p_org and r.user_id=auth.uid() and r.status in ('rejected','partial')
   and r.reviewed_at>now()-interval '90 days'
   and jsonb_array_length(private.member_profile_rejected_fields(r.payload,r.accepted_fields))>0
   and not exists(select 1 from private.member_profile_requests n where n.organization_id=r.organization_id and n.user_id=r.user_id and n.created_at>r.created_at)
   union all
   -- Pedido de familiar não aprovado
   select 'relative-review:'||r.id::text,'Pedido de familiar não aprovado'::text,
   'O pedido para incluir '||coalesce(r.data->>'name','um familiar')||' não foi aprovado. Motivo: '||coalesce(r.reason,'')||'. Você pode enviar um novo pedido.',
   r.updated_at,'profile'::text,r.id
  from private.member_family_requests r
  where r.organization_id=p_org and r.user_id=auth.uid() and r.kind='relative' and r.status='rejected' and r.updated_at>now()-interval '90 days'
   union all
   -- Agenda pastoral: confirmação ou recusa
   select 'pastoral:'||ap.id::text||':'||ap.status,
   case when ap.status='confirmed' and ap.origin='staff' then 'Marcamos um horário com você' when ap.status='confirmed' then 'Seu horário foi confirmado' else 'Não foi possível atender neste horário' end,
   'Com '||coalesce(p.full_name,'a equipe pastoral')||' em '||to_char(ap.starts_at at time zone private.unit_timezone(ap.unit_id),'DD/MM "às" HH24:MI')||case when ap.status='declined' then '. Escolha outro dia no app.' else '.' end,
   ap.updated_at,'pastoral'::text,ap.id
  from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people p on p.id=at.person_id
  where ap.organization_id=p_org and ap.user_id=auth.uid() and ap.status in('confirmed','declined') and ap.updated_at>now()-interval '60 days'
   and not(ap.status='confirmed' and ap.origin='member' and at.auto_confirm and ap.created_at=ap.updated_at)
   union all
   -- Chamado da sala Kids para o responsável
   select 'kids-call:'||k.id::text,'Sala Kids: chamado para '||split_part(p.full_name,' ',1),
   'A equipe chamou você: '||private.kids_call_reason(k.reason)||case when k.message<>'' then ' — '||k.message else '' end||'. Toque para responder.',
   k.created_at,'kids'::text,k.id
  from private.kids_guardian_calls k join private.kids_profiles kp on kp.id=k.profile_id join public.people p on p.id=kp.person_id
  where k.organization_id=p_org and k.created_at>now()-interval '12 hours'
   and exists(select 1 from private.kids_guardians g join public.people gp on gp.id=g.person_id where g.profile_id=k.profile_id and g.status='approved' and gp.auth_user_id=auth.uid())
   union all
   -- Kids: escala de quem serve, reservas abertas e lembrete do dia
   -- Quem serve: a partir de 36 h antes.
  select 'kids-serve:'||x.id::text,
   case when (s.starts_at at time zone private.unit_timezone(s.unit_id))::date=(now() at time zone private.unit_timezone(s.unit_id))::date then 'Você serve hoje no Kids' else 'Você serve no Kids em breve' end,
   s.name||' · '||to_char(s.starts_at at time zone private.unit_timezone(s.unit_id),'DD/MM HH24:MI')||coalesce(' · '||r.name,'')||case when x.confirmed_at is null then '. Toque para confirmar.' else '. Presença confirmada.' end,
   greatest(s.starts_at-interval '36 hours',s.created_at),'kidsTeam'::text,x.id
  from private.kids_assignments x join private.kids_sessions s on s.id=x.session_id join public.organization_memberships m on m.id=x.member_id
   left join private.kids_session_rooms g on g.id=x.group_id left join private.kids_rooms r on r.id=g.room_id
  where x.organization_id=p_org and m.user_id=auth.uid() and x.active and s.status in('draft','open') and s.starts_at>now() and s.starts_at<now()+interval '36 hours'
  union all
  -- Famílias com criança no Kids desta igreja: reservas abertas.
  select 'kids-open:'||s.id::text,'Reservas abertas no Kids',
   s.name||' · '||to_char(s.starts_at at time zone private.unit_timezone(s.unit_id),'DD/MM HH24:MI')||'. Reserve a vaga da sua criança pelo app.',
   coalesce(s.bookable_from,s.created_at),'kids'::text,s.id
  from private.kids_sessions s
  where s.organization_id=p_org and s.unit_id=p_unit and s.series_id is not null and s.starts_at>now() and s.status in('draft','open') and coalesce(s.bookable_from,now())<=now()
   and exists(select 1 from private.kids_guardians kg join public.people gp on gp.id=kg.person_id join private.kids_profiles kp on kp.id=kg.profile_id
    where gp.auth_user_id=auth.uid() and kg.status='approved' and kp.organization_id=p_org and kp.unit_id=p_unit)
  union all
  -- Quem reservou: no dia.
  select 'kids-today:'||r.id::text,'Hoje tem Kids',
   split_part(c.full_name,' ',1)||' tem vaga reservada em '||s.name||' às '||to_char(s.starts_at at time zone private.unit_timezone(s.unit_id),'HH24:MI')||coalesce(' · '||rm.name,'')||'.',
   date_trunc('day',now() at time zone private.unit_timezone(s.unit_id)) at time zone private.unit_timezone(s.unit_id),'kids'::text,r.id
  from private.kids_member_reservations r join private.kids_sessions s on s.id=r.session_id join private.kids_profiles kp on kp.id=r.profile_id join public.people c on c.id=kp.person_id
   left join private.kids_session_rooms g on g.id=r.group_id left join private.kids_rooms rm on rm.id=g.room_id
  where r.organization_id=p_org and r.user_id=auth.uid() and r.status='reserved' and s.ends_at>now()
   and (s.starts_at at time zone private.unit_timezone(s.unit_id))::date=(now() at time zone private.unit_timezone(s.unit_id))::date
   union all
   -- Kids: responsável temporário autorizado
   select 'kids-temp:'||g.id::text||':'||g.version,'Você pode buscar '||split_part(c.full_name,' ',1)||' no Kids',
   coalesce(split_part(b.full_name,' ',1),'O responsável')||' autorizou você até '||to_char(g.valid_until,'DD/MM')||'. Na saída, mostre o QR Code da reserva que aparece na Área Kids.',
   g.approved_at,'kids'::text,g.profile_id
  from private.kids_guardians g join public.people me on me.id=g.person_id join private.kids_profiles k on k.id=g.profile_id join public.people c on c.id=k.person_id left join public.people b on b.id=g.granted_by
  where g.organization_id=p_org and g.temporary and g.status='approved' and g.valid_until>=current_date and me.auth_user_id=auth.uid()
   union all
   -- Mensagens da liderança
   select 'leader-msg:'||m.id::text,'Mensagem de '||split_part(f.full_name,' ',1),left(m.body,140),m.created_at,'leadership'::text,m.id
  from private.leadership_messages m join public.people me on me.id=m.to_person join public.people f on f.id=m.from_person
  where m.organization_id=p_org and me.auth_user_id=auth.uid() and m.created_at>now()-interval '60 days'
   union all
   -- Agenda: convites, lembretes, respostas ao atendente e Integração Visitante
   -- Convite do atendente aguardando aceite.
  select 'pastoral-invite:'||ap.id::text,'Convite para um atendimento',
   coalesce(p.full_name,'A liderança')||' convidou você para '||to_char(ap.starts_at at time zone private.unit_timezone(ap.unit_id),'DD/MM "às" HH24:MI')||'. Toque para aceitar ou recusar.',
   ap.created_at,'pastoral'::text,ap.id
  from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people p on p.id=at.person_id
  where ap.organization_id=p_org and ap.user_id=auth.uid() and ap.status='confirmed' and ap.origin='staff' and not ap.member_ack and ap.starts_at>now()
  union all
  -- Lembrete 24 h antes.
  select 'pastoral-remind:'||ap.id::text,'Atendimento amanhã',
   'Com '||coalesce(p.full_name,'a liderança')||' às '||to_char(ap.starts_at at time zone private.unit_timezone(ap.unit_id),'HH24:MI')||'.',
   ap.starts_at-interval '24 hours','pastoral'::text,ap.id
  from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people p on p.id=at.person_id
  where ap.organization_id=p_org and ap.user_id=auth.uid() and ap.status='confirmed' and ap.member_ack and now() between ap.starts_at-interval '24 hours' and ap.starts_at
  union all
  -- Para quem atende: o membro aceitou, recusou ou pediu outro horário.
  select 'pastoral-att:'||ap.id::text||':'||ap.status||':'||ap.member_ack::text,
   case when ap.status='confirmed' then split_part(m.full_name,' ',1)||' aceitou o atendimento' else split_part(m.full_name,' ',1)||' não poderá ir' end,
   to_char(ap.starts_at at time zone private.unit_timezone(ap.unit_id),'DD/MM "às" HH24:MI')||case when ap.status='cancelled' and ap.decided_reason<>'' then ' · '||ap.decided_reason else '' end,
   ap.updated_at,'pastoralTeam'::text,ap.id
  from private.pastoral_appointments ap join private.pastoral_attendants at on at.id=ap.attendant_id join public.people att on att.id=at.person_id join public.people m on m.id=ap.person_id
  where ap.organization_id=p_org and att.auth_user_id=auth.uid() and ap.origin='staff' and ap.updated_at>now()-interval '30 days'
   and ((ap.status='confirmed' and ap.member_ack and ap.updated_at>ap.created_at) or (ap.status='cancelled' and ap.decided_reason like 'O membro%'))
  union all
  -- Para o acompanhante da Integração Visitante.
  select 'integration:'||v.id::text||':'||coalesce(v.followup_person::text,''),'Você vai acompanhar '||split_part(v.full_name,' ',1),
   'Faça o primeiro contato e registre no app em Integração Visitante.',v.followup_at,'integration'::text,v.id
  from public.people v join public.people me on me.id=v.followup_person
  where v.organization_id=p_org and me.auth_user_id=auth.uid() and v.followup_started is not null and coalesce(v.followup_status,'pending') in('pending','contacted') and v.followup_at>now()-interval '30 days'
  ) b
  -- Convite do atendente aguardando aceite aparece como convite, não como "confirmado".
  where b.message_key not like 'pastoral:%:confirmed' or not exists(
   select 1 from private.pastoral_appointments x where 'pastoral:'||x.id::text||':confirmed'=b.message_key and x.origin='staff' and not x.member_ack)
 ) x order by occurred_at desc nulls last, message_key limit 100
$function$;
revoke all on function private.member_inbox_rows(uuid,uuid) from public,anon,authenticated;

drop function if exists private.member_inbox_before_agenda2(uuid,uuid);
drop function if exists private.member_inbox_before_roles(uuid,uuid);
drop function if exists private.member_inbox_before_kids_temporary(uuid,uuid);
drop function if exists private.member_inbox_before_kids_reminders(uuid,uuid);
drop function if exists private.member_inbox_before_kids_calls(uuid,uuid);
drop function if exists private.member_inbox_before_pastoral(uuid,uuid);
drop function if exists private.member_inbox_before_relative_review(uuid,uuid);
drop function if exists private.member_inbox_before_profile_review(uuid,uuid);
drop function if exists private.member_inbox_before_event_operations(uuid,uuid);
drop function if exists private.member_inbox_before_learning(uuid,uuid);
drop function if exists private.member_inbox_before_community(uuid,uuid);

-- ── Versões canônicas ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ministry_language_save(p_organization uuid, p_version integer, p_labels jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare previous public.ministry_language; v integer;
begin
 perform private.require_confirmed_self_service_email();
 perform 1 from public.organizations where id=p_organization for update;
 perform 1 from public.organization_memberships where organization_id=p_organization and user_id=auth.uid() for share;
 if not private.has_organization_role(p_organization,array['owner','admin']::public.membership_role[])
 or not exists(select 1 from public.organizations where id=p_organization and status in ('active','trial')) then raise exception 'language_access_denied' using errcode='42501';end if;
 if p_version is null or p_version<0 or p_labels is null or jsonb_typeof(p_labels)<>'object' or pg_column_size(p_labels)>8192 then raise exception 'invalid_language' using errcode='22023';end if;
 if exists(select 1 from jsonb_each(p_labels)e where e.key<>all(array['pessoas.cargo','pessoas.cargos','inicio','pessoas','familias','aplicativo','kids','igrejas','usuarios','eventos','celulas','escalas','louvor','comunicacao','transmissoes','financeiro','relatorios','configuracoes','celulas.geral','celulas.redes','celulas.supervisor','celulas.singular','celulas.plural','celulas.cadastro','celulas.encontros','celulas.participantes','celulas.visitantes','celulas.relatorios','celulas.categorias','celulas.responsavel','celulas.local','celulas.indicacoes','celulas.materiais','celulas.consolidado','celulas.pendencias','celulas.supervisao'])
 or jsonb_typeof(e.value)<>'string' or length(btrim(e.value#>>'{}')) not between 2 and 48 or (e.value#>>'{}') ~ '[[:cntrl:]]') then raise exception 'invalid_language' using errcode='22023';end if;
 select * into previous from public.ministry_language where organization_id=p_organization for update;
 if coalesce(previous.version,0)<>p_version then
  if previous.version=p_version+1 and previous.updated_by=auth.uid() and previous.labels=p_labels then return public.ministry_language_read(p_organization);end if;
  raise exception 'language_version_conflict' using errcode='40001';
 end if;
 insert into public.ministry_language(organization_id,labels,updated_by) values(p_organization,p_labels,auth.uid())
 on conflict(organization_id) do update set labels=excluded.labels,updated_by=excluded.updated_by,version=public.ministry_language.version+1,updated_at=clock_timestamp() returning version into v;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_organization,auth.uid(),'language.updated','ministry_language',p_organization::text,jsonb_build_object('version',v,'keys',(select jsonb_agg(key) from jsonb_object_keys(p_labels)key)));
 return public.ministry_language_read(p_organization);
end $function$;

CREATE OR REPLACE FUNCTION private.pastoral_member(p_org uuid, p_unit uuid, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid=auth.uid(); me uuid; a private.pastoral_attendants; ap private.pastoral_appointments; tz text; m date; d date; mins integer; st timestamptz; days jsonb='[]'; n integer; open_count integer; v integer;
begin
 if actor is null then raise exception 'member_login_required' using errcode='42501';end if;
 if p_action is null or p_action not in('attendants','month','day','request','mine','cancel','ack','decline') or p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>8000 then raise exception 'invalid_pastoral' using errcode='22023';end if;
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 me:=private.pastoral_person(p_org);
 perform private.pastoral_expire(p_org);
 if p_action='attendants' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'name',p.full_name,'role',x.role_label,'about',x.about,'durations',x.durations,'kinds',x.kinds,'modes',x.modes,'autoConfirm',x.auto_confirm,'rules',jsonb_build_object('minHours',x.min_notice_hours,'cancelHours',x.cancel_hours,'maxOpen',x.max_open),
    'myLeader',me is not null and exists(select 1 from public.church_cells c join public.church_cell_participants cp on cp.cell_id=c.id and cp.status='active' and cp.person_id=me where c.leader_person_id=x.person_id and c.status='active'),
    'pastor',coalesce((to_jsonb(p)->>'is_pastor')::boolean,false)) order by 2)
   from private.pastoral_attendants x join public.people p on p.id=x.person_id where x.organization_id=p_org and x.unit_id=p_unit and x.active and p.status='active' and private.pastoral_audience_ok(x.id,me) and x.person_id is distinct from me and exists(select 1 from private.pastoral_hours h where h.attendant_id=x.id)),'[]'::jsonb),
   'linked',me is not null,'rules',jsonb_build_object('minHours',24,'cancelHours',12,'maxOpen',2));
 elsif p_action='mine' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(private.pastoral_row(ap2,false) order by ap2.starts_at desc) from (select * from private.pastoral_appointments z where z.organization_id=p_org and (z.user_id=actor or me is not null and z.person_id=me) and z.starts_at>now()-interval '180 days' order by z.starts_at desc limit 50) ap2),'[]'::jsonb));
 end if;

 if p_action in('month','day','request') then
  select * into a from private.pastoral_attendants where id=nullif(p_data->>'attendant','')::uuid and organization_id=p_org and unit_id=p_unit and active;
  if a.id is null or not private.pastoral_audience_ok(a.id,me) then raise exception 'pastoral_unavailable' using errcode='22023';end if;
  mins:=(p_data->>'minutes')::integer;
  if mins is null or not mins=any(a.durations) then raise exception 'invalid_pastoral' using errcode='22023';end if;
  tz:=private.unit_timezone(p_unit);
 end if;

 if p_action='month' then
  if coalesce(p_data->>'month','') !~ '^\d{4}-(0[1-9]|1[0-2])$' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  m:=(p_data->>'month'||'-01')::date;
  for d in select g::date from generate_series(m,(m+interval '1 month'-interval '1 day')::date,interval '1 day') g loop
   if d<(now() at time zone tz)::date then days:=days||jsonb_build_object('date',d,'state','past','slots',0);continue;end if;
   if d>(now() at time zone tz)::date+60 then days:=days||jsonb_build_object('date',d,'state','closed','slots',0);continue;end if;
   if not exists(select 1 from private.pastoral_hours h where h.attendant_id=a.id and h.weekday=extract(dow from d)::int) or exists(select 1 from private.pastoral_blocks b where b.attendant_id=a.id and d between b.starts_on and b.ends_on) then
    days:=days||jsonb_build_object('date',d,'state','none','slots',0);continue;end if;
   select count(*) into n from private.pastoral_slots(a.id,d,mins,true);
   days:=days||jsonb_build_object('date',d,'state',case when n>0 then 'available' else 'full' end,'slots',n);
  end loop;
  return jsonb_build_object('month',p_data->>'month','timezone',tz,'days',days);
 elsif p_action='day' then
  if coalesce(p_data->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  d:=(p_data->>'date')::date;
  if d>(now() at time zone tz)::date+60 then return jsonb_build_object('date',d,'slots','[]'::jsonb);end if;
  return jsonb_build_object('date',d,'timezone',tz,'slots',coalesce((select jsonb_agg(jsonb_build_object('startsAt',s,'label',to_char(s at time zone tz,'HH24:MI')) order by s) from private.pastoral_slots(a.id,d,mins,true) s),'[]'::jsonb));
 elsif p_action='request' then
  if me is null then raise exception 'pastoral_profile_required' using errcode='42501';end if;
  if not(p_data?&array['id','attendant','minutes','startsAt','kind','mode','message']) or p_data-array['id','attendant','minutes','startsAt','kind','mode','message']<>'{}'
   or coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or length(coalesce(p_data->>'message',''))>500 or (p_data->>'message') ~ '[\x00-\x08\x0b\x0c\x0e-\x1f]'
   or not (p_data->>'kind')=any(a.kinds) or not (p_data->>'mode')=any(a.modes) then raise exception 'invalid_pastoral' using errcode='22023';end if;
  select * into ap from private.pastoral_appointments where id=(p_data->>'id')::uuid;
  if ap.id is not null then if ap.user_id=actor then return jsonb_build_object('ok',true,'id',ap.id,'status',ap.status,'version',ap.version);end if;raise exception 'invalid_pastoral' using errcode='22023';end if;
  st:=(p_data->>'startsAt')::timestamptz;
  perform pg_advisory_xact_lock(hashtextextended('pastoral:'||a.id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('pastoral-user:'||actor::text,0));
  select count(*) into open_count from private.pastoral_appointments where organization_id=p_org and user_id=actor and status in('requested','confirmed') and ends_at>now();
  if open_count>=a.max_open then raise exception 'pastoral_open_limit' using errcode='54000';end if;
  if not exists(select 1 from private.pastoral_slots(a.id,(st at time zone tz)::date,mins,true) s where s=st) then raise exception 'pastoral_slot_taken' using errcode='40001';end if;
  insert into private.pastoral_appointments(id,organization_id,unit_id,attendant_id,person_id,user_id,kind,mode,starts_at,ends_at,status,origin,member_ack,message,created_by)
   values((p_data->>'id')::uuid,p_org,p_unit,a.id,me,actor,p_data->>'kind',p_data->>'mode',st,st+make_interval(mins=>mins),case when a.auto_confirm then 'confirmed' else 'requested' end,'member',true,btrim(p_data->>'message'),actor) returning * into ap;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.request','pastoral_appointment',ap.id::text,jsonb_build_object('unit_id',p_unit,'attendant',a.id,'status',ap.status));
  return jsonb_build_object('ok',true,'id',ap.id,'status',ap.status,'version',ap.version);
 else -- cancel / ack
  if coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or jsonb_typeof(p_data->'version')<>'number' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  select * into ap from private.pastoral_appointments where id=(p_data->>'id')::uuid and organization_id=p_org for update;
  if ap.id is null or not(ap.user_id=actor or me is not null and ap.person_id=me) then raise exception 'pastoral_denied' using errcode='42501';end if;
  if ap.version<>(p_data->>'version')::integer then raise exception 'pastoral_changed' using errcode='40001';end if;
  if p_action='cancel' then
   if ap.status not in('requested','confirmed') then raise exception 'pastoral_changed' using errcode='40001';end if;
   if ap.starts_at<now()+(select make_interval(hours=>z.cancel_hours) from private.pastoral_attendants z where z.id=ap.attendant_id) then raise exception 'pastoral_cancel_late' using errcode='22023';end if;
   update private.pastoral_appointments set status='cancelled',version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
  elsif p_action='decline' then
   -- Convite do atendente: o membro recusa ou pede outro horário; o horário fica livre.
   if ap.status<>'confirmed' or ap.member_ack or ap.origin<>'staff' or length(coalesce(p_data->>'reason',''))>200 then raise exception 'pastoral_changed' using errcode='40001';end if;
   update private.pastoral_appointments set status='cancelled',decided_reason=left(case when coalesce((p_data->>'other')::boolean,false) then 'O membro pediu outro horário' else 'O membro recusou o convite' end||coalesce(': '||nullif(btrim(p_data->>'reason'),''),''),200),
    version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
  else
   if ap.status<>'confirmed' or ap.member_ack then raise exception 'pastoral_changed' using errcode='40001';end if;
   update private.pastoral_appointments set member_ack=true,version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.member_'||p_action,'pastoral_appointment',ap.id::text,jsonb_build_object('unit_id',ap.unit_id));
  return jsonb_build_object('ok',true,'id',ap.id,'version',v);
 end if;
end $function$;

CREATE OR REPLACE FUNCTION private.pastoral_row(ap private.pastoral_appointments, p_notes boolean)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select jsonb_build_object('id',ap.id,'reported',exists(select 1 from private.pastoral_reports rr where rr.appointment_id=ap.id),'attendantId',ap.attendant_id,'attendant',coalesce(pp.full_name,''),'role',coalesce(at.role_label,''),'personId',ap.person_id,'person',coalesce(m.full_name,''),
  'kind',ap.kind,'mode',ap.mode,'startsAt',ap.starts_at,'endsAt',ap.ends_at,'status',ap.status,'origin',ap.origin,'memberAck',ap.member_ack,'message',ap.message,'link',ap.link,'reason',ap.decided_reason,
  'notes',case when p_notes then ap.notes else '' end,'version',ap.version,
  'address',case when ap.mode='visita' and ap.status='confirmed' then concat_ws(', ',nullif(m.street,''),nullif(m.number,''),nullif(m.district,''),nullif(m.city,'')) else '' end)
 from private.pastoral_attendants at join public.people pp on pp.id=at.person_id
  left join lateral (select pe.full_name,pa.street,pa.number,pa.district,pa.city from public.people pe left join public.person_addresses pa on pa.person_id=pe.id and pa.organization_id=pe.organization_id where pe.id=ap.person_id order by pa.updated_at desc nulls last limit 1) m on true
 where at.id=ap.attendant_id
$function$;

CREATE OR REPLACE FUNCTION private.pastoral_staff(p_org uuid, p_unit uuid, p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid=auth.uid(); a private.pastoral_attendants; ap private.pastoral_appointments; att uuid; tz text; v integer; mins integer; st timestamptz; person uuid; x jsonb; fr timestamptz; tt timestamptz;
 can_view boolean; can_edit boolean; can_settings boolean; can_notes boolean;
begin
 if actor is null then raise exception 'pastoral_denied' using errcode='42501';end if;
 if p_action is null or p_action not in('overview','save_attendant','hours','block','unblock','decide','schedule','status','note','slots') or p_data is null or jsonb_typeof(p_data)<>'object' or pg_column_size(p_data)>16000 then raise exception 'invalid_pastoral' using errcode='22023';end if;
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id where u.id=p_unit and u.organization_id=p_org and u.status='active' and o.status in('active','trial')) then raise exception 'pastoral_denied' using errcode='42501';end if;
 perform private.pastoral_expire(p_org);can_view:=private.can(p_org,p_unit,'pastoral.agenda','view');can_edit:=private.can(p_org,p_unit,'pastoral.agenda','edit');can_settings:=private.can(p_org,p_unit,'pastoral.settings','edit');can_notes:=private.can(p_org,p_unit,'pastoral.notes','view');
 tz:=private.unit_timezone(p_unit);

 if p_action='overview' then
  fr:=coalesce(nullif(p_data->>'from','')::timestamptz,now()-interval '7 days');tt:=coalesce(nullif(p_data->>'to','')::timestamptz,now()+interval '35 days');
  if tt<fr or tt-fr>interval '120 days' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  if not(can_view or can_settings or exists(select 1 from private.pastoral_attendants z where z.organization_id=p_org and z.unit_id=p_unit and private.pastoral_self(z.id))) then raise exception 'pastoral_denied' using errcode='42501';end if;
  return jsonb_build_object('timezone',tz,'canEdit',can_edit,'canSettings',can_settings,
   'attendants',coalesce((select jsonb_agg(jsonb_build_object('id',z.id,'personId',z.person_id,'name',p.full_name,'role',z.role_label,'about',z.about,'autoConfirm',z.auto_confirm,'durations',z.durations,'kinds',z.kinds,'modes',z.modes,'active',z.active,'version',z.version,'self',private.pastoral_self(z.id),
     'hours',coalesce((select jsonb_agg(jsonb_build_object('weekday',h.weekday,'starts',to_char(h.starts,'HH24:MI'),'ends',to_char(h.ends,'HH24:MI')) order by h.weekday,h.starts) from private.pastoral_hours h where h.attendant_id=z.id),'[]'::jsonb),
     'blocks',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'from',b.starts_on,'to',b.ends_on,'reason',b.reason) order by b.starts_on) from private.pastoral_blocks b where b.attendant_id=z.id and b.ends_on>=current_date),'[]'::jsonb)) order by p.full_name)
    from private.pastoral_attendants z join public.people p on p.id=z.person_id where z.organization_id=p_org and z.unit_id=p_unit and (can_view or can_settings or private.pastoral_self(z.id))),'[]'::jsonb),
   'items',coalesce((select jsonb_agg(private.pastoral_row(q,private.pastoral_self(q.attendant_id) or can_notes) order by q.starts_at) from private.pastoral_appointments q
    where q.organization_id=p_org and q.unit_id=p_unit and q.starts_at between fr and tt and (can_view or private.pastoral_self(q.attendant_id))),'[]'::jsonb));
 end if;

 if p_action='save_attendant' then
  if not can_settings then raise exception 'pastoral_denied' using errcode='42501';end if;
  if not(p_data?&array['id','person','role','about','autoConfirm','durations','kinds','modes','active','version']) or p_data-array['id','person','role','about','autoConfirm','durations','kinds','modes','active','version']<>'{}' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  person:=(p_data->>'person')::uuid;
  if not exists(select 1 from public.people where id=person and organization_id=p_org and status='active') then raise exception 'invalid_pastoral' using errcode='22023';end if;
  select * into a from private.pastoral_attendants where id=(p_data->>'id')::uuid for update;
  if a.id is null then
   if (p_data->>'version')::int<>0 then raise exception 'pastoral_changed' using errcode='40001';end if;
   insert into private.pastoral_attendants(id,organization_id,unit_id,person_id,role_label,about,auto_confirm,durations,kinds,modes,active,created_by)
    values((p_data->>'id')::uuid,p_org,p_unit,person,btrim(p_data->>'role'),btrim(p_data->>'about'),(p_data->>'autoConfirm')::boolean,
     array(select jsonb_array_elements_text(p_data->'durations')::smallint),array(select jsonb_array_elements_text(p_data->'kinds')),array(select jsonb_array_elements_text(p_data->'modes')),(p_data->>'active')::boolean,actor) returning version into v;
  else
   if a.organization_id<>p_org or a.unit_id<>p_unit then raise exception 'pastoral_denied' using errcode='42501';end if;
   if a.version<>(p_data->>'version')::int then raise exception 'pastoral_changed' using errcode='40001';end if;
   update private.pastoral_attendants set person_id=person,role_label=btrim(p_data->>'role'),about=btrim(p_data->>'about'),auto_confirm=(p_data->>'autoConfirm')::boolean,
    durations=array(select jsonb_array_elements_text(p_data->'durations')::smallint),kinds=array(select jsonb_array_elements_text(p_data->'kinds')),modes=array(select jsonb_array_elements_text(p_data->'modes')),
    active=(p_data->>'active')::boolean,version=version+1,updated_at=clock_timestamp() where id=a.id returning version into v;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.attendant_saved','pastoral_attendant',p_data->>'id',jsonb_build_object('unit_id',p_unit));
  return jsonb_build_object('ok',true,'id',p_data->>'id','version',v);
 end if;

 att:=nullif(p_data->>'attendant','')::uuid;
 if p_action in('hours','block','unblock','schedule','slots') then
  select * into a from private.pastoral_attendants where id=att and organization_id=p_org and unit_id=p_unit for update;
  if a.id is null then raise exception 'pastoral_denied' using errcode='42501';end if;
 end if;

 if p_action in('hours','block','unblock') then
  if not(private.pastoral_self(a.id) or can_settings) then raise exception 'pastoral_denied' using errcode='42501';end if;
  if p_action='hours' then
   -- Substitui a semana inteira: [{weekday,starts,ends}], até 21 faixas, sem sobreposição no mesmo dia.
   if jsonb_typeof(p_data->'hours')<>'array' or jsonb_array_length(p_data->'hours')>21 then raise exception 'invalid_pastoral' using errcode='22023';end if;
   for x in select value from jsonb_array_elements(p_data->'hours') loop
    if (x->>'weekday') !~ '^[0-6]$' or coalesce(x->>'starts','') !~ '^([01]\d|2[0-3]):[0-5]\d$' or coalesce(x->>'ends','') !~ '^([01]\d|2[0-3]):[0-5]\d$' or (x->>'ends')::time<=(x->>'starts')::time then raise exception 'invalid_pastoral' using errcode='22023';end if;
   end loop;
   if exists(select 1 from jsonb_array_elements(p_data->'hours') h1,jsonb_array_elements(p_data->'hours') h2 where h1<>h2 and h1->>'weekday'=h2->>'weekday' and (h1->>'starts')::time<(h2->>'ends')::time and (h2->>'starts')::time<(h1->>'ends')::time) then raise exception 'invalid_pastoral' using errcode='22023';end if;
   delete from private.pastoral_hours where attendant_id=a.id;
   insert into private.pastoral_hours(attendant_id,weekday,starts,ends) select a.id,(h->>'weekday')::smallint,(h->>'starts')::time,(h->>'ends')::time from jsonb_array_elements(p_data->'hours') h;
  elsif p_action='block' then
   if coalesce(p_data->>'from','') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(p_data->>'to','') !~ '^\d{4}-\d{2}-\d{2}$' or length(coalesce(p_data->>'reason',''))>120 then raise exception 'invalid_pastoral' using errcode='22023';end if;
   insert into private.pastoral_blocks(attendant_id,starts_on,ends_on,reason) values(a.id,(p_data->>'from')::date,(p_data->>'to')::date,btrim(coalesce(p_data->>'reason','')));
  else
   delete from private.pastoral_blocks where id=nullif(p_data->>'id','')::uuid and attendant_id=a.id;
  end if;
  update private.pastoral_attendants set version=version+1,updated_at=clock_timestamp() where id=a.id returning version into v;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.'||p_action,'pastoral_attendant',a.id::text,jsonb_build_object('unit_id',p_unit));
  return jsonb_build_object('ok',true,'id',a.id,'version',v);
 end if;

 if p_action='slots' then
  if not(private.pastoral_self(a.id) or can_edit) then raise exception 'pastoral_denied' using errcode='42501';end if;
  mins:=(p_data->>'minutes')::integer;
  if mins is null or mins not in(15,30,45,60,90,120) or coalesce(p_data->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  return jsonb_build_object('slots',coalesce((select jsonb_agg(jsonb_build_object('startsAt',s,'label',to_char(s at time zone tz,'HH24:MI')) order by s) from private.pastoral_slots(a.id,(p_data->>'date')::date,mins,false) s),'[]'::jsonb));
 end if;

 if p_action='schedule' then
  -- Equipe marca com um membro (ex.: visita). Sem a regra das 24 h, mas sem sobrepor horários.
  if not(private.pastoral_self(a.id) or can_edit) then raise exception 'pastoral_denied' using errcode='42501';end if;
  if not(p_data?&array['id','attendant','person','minutes','startsAt','kind','mode','message','link']) or p_data-array['id','attendant','person','minutes','startsAt','kind','mode','message','link']<>'{}'
   or coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or (p_data->>'minutes')::int not in(15,30,45,60,90,120) or (p_data->>'kind') not in('conversa','aconselhamento','oracao','visita','outro') or (p_data->>'mode') not in('presencial','online','visita')
   or length(coalesce(p_data->>'message',''))>500 or length(coalesce(p_data->>'link',''))>300 or (p_data->>'link')<>'' and (p_data->>'link') !~ '^https://' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  person:=(p_data->>'person')::uuid;
  if not exists(select 1 from public.people where id=person and organization_id=p_org and status='active') then raise exception 'invalid_pastoral' using errcode='22023';end if;
  -- Líder de célula sem permissão geral só marca com participantes das suas células.
  if not can_edit and not coalesce((select to_jsonb(p)->>'is_pastor' from public.people p where p.id=a.person_id),'false')::boolean
   and not exists(select 1 from public.church_cells c join public.church_cell_participants cp on cp.cell_id=c.id and cp.status='active' where c.leader_person_id=a.person_id and cp.person_id=person) then raise exception 'pastoral_denied' using errcode='42501';end if;
  select * into ap from private.pastoral_appointments where id=(p_data->>'id')::uuid;
  if ap.id is not null then return jsonb_build_object('ok',true,'id',ap.id,'version',ap.version);end if;
  st:=(p_data->>'startsAt')::timestamptz;
  if st<now() or st>now()+interval '180 days' then raise exception 'invalid_pastoral' using errcode='22023';end if;
  -- O atendente também respeita a própria disponibilidade (horários, datas, bloqueios e a sua agenda).
  if not exists(select 1 from private.pastoral_slots(a.id,(st at time zone private.unit_timezone(a.unit_id))::date,(p_data->>'minutes')::int,false) s where s=st) then raise exception 'pastoral_outside_hours' using errcode='22023';end if;
  begin
   insert into private.pastoral_appointments(id,organization_id,unit_id,attendant_id,person_id,user_id,kind,mode,starts_at,ends_at,status,origin,member_ack,message,link,created_by)
    values((p_data->>'id')::uuid,p_org,p_unit,a.id,person,(select auth_user_id from public.people where id=person),p_data->>'kind',p_data->>'mode',st,st+make_interval(mins=>(p_data->>'minutes')::int),'confirmed','staff',(select auth_user_id is null from public.people where id=person) or st<=now()+interval '12 hours',btrim(p_data->>'message'),p_data->>'link',actor) returning * into ap;
  exception when exclusion_violation then raise exception 'pastoral_slot_taken' using errcode='40001';
  end;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.schedule','pastoral_appointment',ap.id::text,jsonb_build_object('unit_id',p_unit,'attendant',a.id));
  return jsonb_build_object('ok',true,'id',ap.id,'version',ap.version);
 end if;

 -- decide / status / note: atendimento existente
 if coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or jsonb_typeof(p_data->'version')<>'number' then raise exception 'invalid_pastoral' using errcode='22023';end if;
 select * into ap from private.pastoral_appointments where id=(p_data->>'id')::uuid and organization_id=p_org and unit_id=p_unit for update;
 if ap.id is null then raise exception 'pastoral_denied' using errcode='42501';end if;
 if ap.version<>(p_data->>'version')::int then raise exception 'pastoral_changed' using errcode='40001';end if;
 if p_action='note' then
  if not private.pastoral_self(ap.attendant_id) then raise exception 'pastoral_denied' using errcode='42501';end if;
  if length(coalesce(p_data->>'notes',''))>4000 then raise exception 'invalid_pastoral' using errcode='22023';end if;
  update private.pastoral_appointments set notes=coalesce(p_data->>'notes',''),version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
 else
  if not(private.pastoral_self(ap.attendant_id) or private.can(p_org,p_unit,'pastoral.agenda','approve') or can_edit) then raise exception 'pastoral_denied' using errcode='42501';end if;
  if p_action='decide' then
   if ap.status<>'requested' or p_data->>'decision' not in('confirm','decline') or length(coalesce(p_data->>'reason',''))>200 or length(coalesce(p_data->>'link',''))>300 or coalesce(p_data->>'link','')<>'' and (p_data->>'link') !~ '^https://' then raise exception 'invalid_pastoral' using errcode='22023';end if;
   update private.pastoral_appointments set status=case when p_data->>'decision'='confirm' then 'confirmed' else 'declined' end,decided_reason=btrim(coalesce(p_data->>'reason','')),link=coalesce(nullif(p_data->>'link',''),link),version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
  else
   if p_data->>'status' not in('done','missed','cancelled') or ap.status not in('requested','confirmed') or p_data->>'status' in('done','missed') and ap.starts_at>now() then raise exception 'invalid_pastoral' using errcode='22023';end if;
   update private.pastoral_appointments set status=p_data->>'status',decided_reason=btrim(coalesce(p_data->>'reason','')),version=version+1,updated_at=clock_timestamp() where id=ap.id returning version into v;
  end if;
 end if;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,actor,'pastoral.'||p_action,'pastoral_appointment',ap.id::text,jsonb_build_object('unit_id',p_unit));
 return jsonb_build_object('ok',true,'id',ap.id,'version',v);
end $function$;

CREATE OR REPLACE FUNCTION private.people_search(p_org uuid, p_unit uuid, p_filters jsonb, p_page integer, p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f jsonb:=coalesce(p_filters,'{}'); v_q text; v_today date; v_total int; v_ids jsonb; v_pattern text;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if jsonb_typeof(f)<>'object' or f-array['q','status','group','cell','network','gender','ageMin','ageMax','baptized','tag','converts','position','ministry','leaders']<>'{}'::jsonb
  or p_page is null or p_page<1 or p_page>10000 or p_limit is null or p_limit<1 or p_limit>100 then raise exception 'invalid_filters' using errcode='22023'; end if;
 if (f ? 'cell' and coalesce(f->>'cell','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or (f ? 'network' and coalesce(f->>'network','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or (f ? 'ageMin' and coalesce(f->>'ageMin','') !~ '^\d{1,3}$') or (f ? 'ageMax' and coalesce(f->>'ageMax','') !~ '^\d{1,3}$')
  or (f ? 'baptized' and jsonb_typeof(f->'baptized')<>'boolean') or (f ? 'converts' and jsonb_typeof(f->'converts')<>'boolean')
  or length(coalesce(f->>'q',''))>100 or length(coalesce(f->>'group',''))>160 or length(coalesce(f->>'tag',''))>80 or length(coalesce(f->>'gender',''))>30
  or (f ? 'status' and f->>'status' not in ('Membro','Em integração','Visitante','Criança')) then raise exception 'invalid_filters' using errcode='22023'; end if;
 if (f ? 'position' and coalesce(f->>'position','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') or (f ? 'ministry' and coalesce(f->>'ministry','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') or (f ? 'leaders' and jsonb_typeof(f->'leaders')<>'boolean') then raise exception 'invalid_filters' using errcode='22023'; end if;
 if not private.people_list_allowed(p_org,p_unit) then raise exception 'people_access_denied' using errcode='42501'; end if;
 v_today:=(now() at time zone coalesce(private.unit_timezone(p_unit),'America/Sao_Paulo'))::date;
 v_q:=nullif(btrim(coalesce(f->>'q','')),'');
 v_pattern:='%'||replace(replace(replace(lower(coalesce(v_q,'')),'\','\\'),'%','\%'),'_','\_')||'%';
 with recursive nets as (
   select n.id from public.church_cell_networks n where f ? 'network' and n.id=(f->>'network')::uuid and n.organization_id=p_org
   union select np.network_id from public.church_cell_network_parents np join nets on np.parent_id=nets.id),
 found as (
  select p.id,p.created_at from public.people p
  where p.organization_id=p_org and p.unit_id=p_unit and private.person_record_view(p.id)
   and (v_q is null or lower(p.full_name) like v_pattern or lower(coalesce(p.email,'')) like v_pattern or coalesce(p.phone,'') like v_pattern
        or (regexp_replace(v_q,'\D','','g')<>'' and length(regexp_replace(v_q,'\D','','g'))>=4 and regexp_replace(coalesce(p.phone,''),'\D','','g') like '%'||regexp_replace(v_q,'\D','','g')||'%'))
   and (not f ? 'status' or p.journey_status=f->>'status')
   and (nullif(f->>'group','') is null or p.group_name=f->>'group')
   and (nullif(f->>'gender','') is null or p.gender=f->>'gender')
   and (not f ? 'baptized' or coalesce(p.baptized,false)=(f->>'baptized')::boolean)
   and (nullif(f->>'tag','') is null or p.tags @> array[f->>'tag'])
   and (not coalesce((f->>'converts')::boolean,false) or p.converted_at is not null)
   and (not f ? 'position' or exists(select 1 from private.person_positions pp where pp.person_id=p.id and pp.until is null and pp.position_id=(f->>'position')::uuid))
   and (not f ? 'ministry' or exists(select 1 from private.group_assignments ga where ga.person_id=p.id and ga.until is null and ga.kind='ministry' and ga.group_id=(f->>'ministry')::uuid))
   and (not coalesce((f->>'leaders')::boolean,false) or exists(select 1 from private.group_assignments ga join private.group_functions gf on gf.id=ga.function_id where ga.person_id=p.id and ga.until is null and gf.leadership)
        or exists(select 1 from private.person_positions pp where pp.person_id=p.id and pp.until is null))
   and (not f ? 'ageMin' or p.birth_date<=v_today-make_interval(years=>(f->>'ageMin')::int))
   and (not f ? 'ageMax' or p.birth_date>v_today-make_interval(years=>(f->>'ageMax')::int+1))
   and (not f ? 'cell' or exists(select 1 from public.church_cell_participants c where c.person_id=p.id and c.organization_id=p_org and c.status='active' and c.cell_id=(f->>'cell')::uuid))
   and (not f ? 'network' or exists(select 1 from public.church_cell_participants c join public.church_cell_network_links l on l.cell_id=c.cell_id and l.organization_id=p_org
        where c.person_id=p.id and c.organization_id=p_org and c.status='active' and l.network_id in (select id from nets))))
 select count(*)::int,coalesce((select jsonb_agg(x.id order by x.created_at desc,x.id desc) from (select id,created_at from found order by created_at desc,id desc offset (p_page-1)*p_limit limit p_limit) x),'[]')
  into v_total,v_ids from found;
 return jsonb_build_object('total',v_total,'ids',v_ids);
end $function$;
