begin;
set local lock_timeout='5s';
-- Etapa 4 · PR 1: recorrência completa (anual; termina após N, em uma data ou sem término)
-- e assinatura da agenda da igreja em calendários (.ics).

create or replace function pg_temp.patch(p_fn regprocedure,p_old text,p_new text,p_expected integer default 1) returns void language plpgsql as $$
declare d text:=pg_get_functiondef(p_fn);n integer:=(length(d)-length(replace(d,p_old,'')))/greatest(length(p_old),1);
begin
 if n<>coalesce(p_expected,greatest(n,1)) then raise exception 'patch %: esperado % ocorrência(s) de [%], encontrado %',p_fn,p_expected,p_old,n;end if;
 execute replace(d,p_old,p_new);
end $$;

-- ── Recorrência ──────────────────────────────────────────────────────────────
-- Converte "termina em uma data" ou "sem término" (12 meses, até 120 datas) na quantidade de encontros
-- e confere o horizonte de 2 anos da agenda.
-- Mesma regra de shared/recurrence.ts.
create function private.programming_repeat_count(p_data jsonb) returns jsonb language plpgsql stable set search_path='' as $$
declare s timestamp;stp interval;lim timestamp;n integer;
begin
 if p_data->>'ends' not in('count','until','never') or (p_data->>'ends'='until')<>(p_data ? 'until') or (p_data ? 'until' and coalesce(p_data->>'until','') !~ '^\d{4}-\d{2}-\d{2}$')
  or p_data->>'ends'<>'count' and p_data ? 'count' then raise exception 'invalid_member_agenda' using errcode='22023';end if;
 if coalesce(p_data->>'repeat','none')='none' then return (p_data-array['ends','until'])||'{"count":1}'::jsonb;end if;
 stp:=case p_data->>'repeat' when 'daily' then interval '1 day' when 'weekly' then interval '7 days' when 'monthly' then interval '1 month' when 'yearly' then interval '1 year' end;
 if stp is null then raise exception 'invalid_member_agenda' using errcode='22023';end if;
 begin
  s:=(p_data->>'startsLocal')::timestamp;
  lim:=case p_data->>'ends' when 'until' then ((p_data->>'until')::date+1)::timestamp when 'never' then s+interval '12 months' end;
  n:=case when p_data->>'ends'='count' then (p_data->>'count')::integer end;
 exception when others then raise exception 'invalid_member_agenda' using errcode='22023';
 end;
 if p_data->>'ends'<>'count' then
  select count(*) into n from generate_series(0,120) i where s+stp*i<lim;
  if n<1 then raise exception 'programming_repeat_until' using errcode='22023';end if;
  if p_data->>'ends'='until' and n>120 then raise exception 'programming_repeat_too_long' using errcode='22023';end if;
  n:=least(n,120);
  -- Sem término respeita o horizonte da agenda (2 anos à frente): para antes, sem erro.
  if p_data->>'ends'='never' then select count(*) into n from generate_series(0,n-1) i where s+stp*i<=(now() at time zone 'UTC')+interval '2 years';end if;
 end if;
 if n is null or n not between 1 and 120 then raise exception 'invalid_member_agenda' using errcode='22023';end if;
 -- A agenda aceita datas até 2 anos à frente (member_agenda_admin): avisa com o motivo certo.
 if s+stp*(n-1)>(now() at time zone 'UTC')+interval '2 years' then raise exception 'programming_repeat_horizon' using errcode='22023';end if;
 return (p_data-array['ends','until'])||jsonb_build_object('count',n);
end $$;
revoke all on function private.programming_repeat_count(jsonb) from public,anon,authenticated,service_role;

select pg_temp.patch('private.programming_admin(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure,
 'and not private.event_manager(p_org,p_unit) then raise exception ''member_agenda_denied'' using errcode=''42501'';end if;
',
 'and not private.event_manager(p_org,p_unit) then raise exception ''member_agenda_denied'' using errcode=''42501'';end if;
 if p_action=''create'' and p_data ? ''ends'' then p_data:=private.programming_repeat_count(p_data);end if;
');
select pg_temp.patch('private.programming_admin_base_20261103(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure,
 'p_data->>''repeat'' not in(''none'',''daily'',''weekly'',''monthly'') or n not between 1 and 52',
 'p_data->>''repeat'' not in(''none'',''daily'',''weekly'',''monthly'',''yearly'') or n not between 1 and 120');
select pg_temp.patch('private.programming_admin_base_20261103(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure,
 'when ''monthly'' then interval ''1 month'' else interval ''0'' end',
 'when ''monthly'' then interval ''1 month'' when ''yearly'' then interval ''1 year'' else interval ''0'' end');

-- Página pública do evento informa o fuso da igreja (horários e "Adicionar ao calendário").
select pg_temp.patch('member_app_api.event_page(uuid)'::regprocedure,'''cover_url'',e.cover_url,''unit'',e.unit_id)','''cover_url'',e.cover_url,''unit'',e.unit_id,''timezone'',private.unit_timezone(e.unit_id))');

-- ── Assinatura da agenda (.ics) ─────────────────────────────────────────────
-- Um endereço secreto por igreja, criado e trocado pela gestão da agenda. Só eventos publicados entram,
-- os mesmos que já têm página pública.
create table private.agenda_feeds(
 unit_id uuid primary key references public.organization_units(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 token text not null unique check(token ~ '^[0-9a-f]{40}$'),
 created_by uuid references auth.users(id),
 created_at timestamptz not null default clock_timestamp()
);
create index agenda_feeds_org on private.agenda_feeds(organization_id);
create index agenda_feeds_created_by on private.agenda_feeds(created_by);
alter table private.agenda_feeds enable row level security;
revoke all on private.agenda_feeds from public,anon,authenticated,service_role;

create function private.agenda_feed_admin(p_org uuid,p_unit uuid,p_action text) returns jsonb language plpgsql security definer set search_path='' as $$
declare t text;
begin
 if not private.event_manager(p_org,p_unit) then raise exception 'member_agenda_denied' using errcode='42501';end if;
 if p_action='rotate' then
  perform 1 from public.organization_units where id=p_unit and organization_id=p_org for no key update;
  t:=encode(extensions.gen_random_bytes(20),'hex');
  insert into private.agenda_feeds(unit_id,organization_id,token,created_by) values(p_unit,p_org,t,auth.uid())
   on conflict(unit_id) do update set token=excluded.token,created_by=excluded.created_by,created_at=clock_timestamp();
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'agenda.feed.rotated','organization_unit',p_unit::text,'{}');
 elsif p_action='disable' then
  delete from private.agenda_feeds where unit_id=p_unit and organization_id=p_org;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata) values(p_org,auth.uid(),'agenda.feed.disabled','organization_unit',p_unit::text,'{}');
 elsif p_action<>'get' then raise exception 'invalid_member_agenda' using errcode='22023';
 end if;
 return jsonb_build_object('ok',true,'token',(select token from private.agenda_feeds where unit_id=p_unit and organization_id=p_org));
end $$;
revoke all on function private.agenda_feed_admin(uuid,uuid,text) from public,anon,authenticated,service_role;
create function public.agenda_feed_admin(p_org uuid,p_unit uuid,p_action text) returns jsonb language sql security definer set search_path='' as $$select private.agenda_feed_admin(p_org,p_unit,p_action)$$;
revoke all on function public.agenda_feed_admin(uuid,uuid,text) from public,anon;
grant execute on function public.agenda_feed_admin(uuid,uuid,text) to authenticated;

-- Leitura pública pelo endereço secreto: últimos 30 dias e próximos 12 meses, até 500 eventos.
create function private.agenda_feed(p_token text) returns jsonb language sql stable security definer set search_path='' as $$
 select case when f.unit_id is null then null else jsonb_build_object(
  'church',o.name,'unit',u.name,'timezone',private.unit_timezone(u.id),
  'events',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'title',e.title,'description',e.description,'starts_at',e.starts_at,'ends_at',e.ends_at,
    'location',e.location,'address',e.address,'status',e.status,'version',e.version,'updated_at',e.updated_at) order by e.starts_at)
   from (select * from private.church_app_events e where e.organization_id=f.organization_id and e.unit_id=f.unit_id and e.status in('published','cancelled')
    and e.starts_at between now()-interval '30 days' and now()+interval '12 months' order by e.starts_at limit 500) e),'[]')) end
 from (select 1) one
 left join private.agenda_feeds f on f.token=p_token and p_token ~ '^[0-9a-f]{40}$'
 left join public.organizations o on o.id=f.organization_id and o.status in('active','trial')
 left join public.organization_units u on u.id=f.unit_id and u.status='active'
 where f.unit_id is null or (o.id is not null and u.id is not null and private.member_event_enabled(f.organization_id,f.unit_id));
$$;
revoke all on function private.agenda_feed(text) from public,anon,authenticated,service_role;
create function public.agenda_feed(p_token text) returns jsonb language sql stable security definer set search_path='' as $$select private.agenda_feed(p_token)$$;
revoke all on function public.agenda_feed(text) from public;
grant execute on function public.agenda_feed(text) to anon,authenticated,service_role;

notify pgrst,'reload schema';
commit;
