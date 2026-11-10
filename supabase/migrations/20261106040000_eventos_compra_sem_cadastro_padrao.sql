begin;
set local lock_timeout='5s';
-- Etapa 1: links públicos de eventos e vendas aceitam compra sem conta por padrão.
-- A igreja continua podendo exigir conta em eventos exclusivos para membros pelo painel.
alter table private.event_ticket_settings alter column allow_guests set default true;
-- Eventos e vendas ainda abertos passam a aceitar visitantes; encerrados permanecem como estavam.
update private.event_ticket_settings s set allow_guests=true
 from private.church_app_events e
 where e.id=s.event_id and not s.allow_guests and e.ends_at>clock_timestamp();
notify pgrst,'reload schema';
commit;
