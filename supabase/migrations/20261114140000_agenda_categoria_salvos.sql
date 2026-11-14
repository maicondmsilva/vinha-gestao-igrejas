-- Agenda do app: categoria do evento (nome e cor) para filtrar, e eventos salvos pelo membro ("Salvos").

do $$
declare d text; n int; a text; b text;
begin
 d:=pg_get_functiondef('member_app_api.agenda'::regproc);
 if position('agenda_category' in d)=0 then
  a:='e.cover_url as cover,';b:='e.cover_url as cover,coalesce(k.name,'''') as category,coalesce(k.color,'''') as category_color,/* agenda_category */';
  n:=(length(d)-length(replace(d,a,'')))/length(a);if n<>1 then raise exception 'agenda: capa não encontrada (%)',n;end if;d:=replace(d,a,b);
  a:='left join private.member_event_prices price on price.event_id=e.id';b:='left join private.member_event_prices price on price.event_id=e.id left join private.programming_categories k on k.id=e.category_id';
  n:=(length(d)-length(replace(d,a,'')))/length(a);if n<>1 then raise exception 'agenda: preço não encontrado (%)',n;end if;d:=replace(d,a,b);
  execute d;
 end if;
end $$;

create table if not exists private.member_saved_events(
 user_id uuid not null references auth.users(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 event_id uuid not null,
 created_at timestamptz not null default now(),
 primary key(user_id,event_id)
);
create index if not exists member_saved_events_org on private.member_saved_events(organization_id,user_id);
create index if not exists member_saved_events_event on private.member_saved_events(event_id);
alter table private.member_saved_events enable row level security;
revoke all on private.member_saved_events from public,anon,authenticated;

-- Salvos: lista, salvar ou tirar. Só a própria conta, só eventos publicados da organização, até 200 por pessoa.
create or replace function private.member_saved_events(p_org uuid, p_action text, p_event uuid)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare actor uuid=auth.uid();
begin
 if actor is null then raise exception 'member_login_required' using errcode='42501';end if;
 if p_action not in('list','save','remove') or p_action<>'list' and p_event is null then raise exception 'invalid_saved_event' using errcode='22023';end if;
 if not exists(select 1 from public.organizations o where o.id=p_org and o.status in('active','trial')) then raise exception 'member_unit_denied' using errcode='42501';end if;
 if p_action='save' then
  if not exists(select 1 from private.church_app_events e where e.id=p_event and e.organization_id=p_org and e.status='published') then raise exception 'invalid_saved_event' using errcode='22023';end if;
  if (select count(*) from private.member_saved_events where user_id=actor)>=200 then raise exception 'saved_events_limit' using errcode='54000';end if;
  insert into private.member_saved_events(user_id,organization_id,event_id) values(actor,p_org,p_event) on conflict do nothing;
 elsif p_action='remove' then
  delete from private.member_saved_events where user_id=actor and organization_id=p_org and event_id=p_event;
 end if;
 return jsonb_build_object('ok',true,'items',coalesce((select jsonb_agg(s.event_id order by s.created_at desc) from private.member_saved_events s where s.user_id=actor and s.organization_id=p_org),'[]'::jsonb));
end $function$;
revoke all on function private.member_saved_events(uuid,text,uuid) from public,anon,authenticated;
create or replace function public.member_saved_events(p_org uuid, p_action text default 'list', p_event uuid default null) returns jsonb
language sql security definer set search_path to '' as $$ select private.member_saved_events(p_org,p_action,p_event) $$;
revoke all on function public.member_saved_events(uuid,text,uuid) from public,anon;
grant execute on function public.member_saved_events(uuid,text,uuid) to authenticated;
