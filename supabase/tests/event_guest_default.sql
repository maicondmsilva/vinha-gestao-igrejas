begin;
create extension if not exists pgtap with schema extensions;
select plan(2);
select col_default_is('private','event_ticket_settings','allow_guests','true',
 'novos eventos e vendas aceitam compra sem conta por padrão');
select col_not_null('private','event_ticket_settings','allow_guests',
 'a política de visitantes continua obrigatória');
select * from finish();
rollback;
