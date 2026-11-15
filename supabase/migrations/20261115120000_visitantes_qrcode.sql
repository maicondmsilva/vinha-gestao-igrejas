-- Visitantes: cadastro rápido por QR Code (página pública por igreja) ou pela equipe no Vinha Equipe.
-- Cada cadastro vira (ou atualiza) uma pessoa em Pessoas como "Visitante", com acompanhamento pendente,
-- e cada visita fica registrada com as respostas para a equipe de integração acompanhar.

create table if not exists private.visitor_entries(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 person_id uuid not null references public.people(id) on delete cascade,
 source text not null check(source in('qr','staff')),
 answers jsonb not null default '{}'::jsonb check(jsonb_typeof(answers)='object' and length(answers::text)<=2000),
 created_by uuid,
 created_at timestamptz not null default now()
);
create index if not exists visitor_entries_unit on private.visitor_entries(unit_id,created_at desc);
create index if not exists visitor_entries_person on private.visitor_entries(person_id,created_at desc);
alter table private.visitor_entries enable row level security;
revoke all on private.visitor_entries from public,anon,authenticated;

create or replace function private.visitor_digits(p text) returns text language sql immutable set search_path to '' as $$ select regexp_replace(coalesce(p,''),'\D','','g') $$;

-- Cabeçalho da página pública: nome da igreja e cor (só igrejas ativas).
create or replace function public.visitor_page(p_unit uuid) returns jsonb
language sql stable security definer set search_path to '' as $$
 select coalesce((select jsonb_build_object('found',true,'church',u.name,'ministry',o.name,'color',coalesce(o.primary_color,''))
  from public.organization_units u join public.organizations o on o.id=u.organization_id
  where u.id=p_unit and u.status='active' and o.status in('active','trial')),jsonb_build_object('found',false))
$$;
revoke all on function public.visitor_page(uuid) from public;
grant execute on function public.visitor_page(uuid) to anon,authenticated;

-- Grava o visitante. p_source='qr' (página pública) ou 'staff' (equipe, já conferida pelo chamador).
create or replace function private.visitor_save(p_unit uuid, p_data jsonb, p_source text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare u public.organization_units; v_name text; v_phone text; v_email text; pid uuid; answers jsonb; recent int;
begin
 select * into u from public.organization_units where id=p_unit and status='active';
 if u.id is null or not exists(select 1 from public.organizations where id=u.organization_id and status in('active','trial')) then raise exception 'visitor_unit_denied' using errcode='42501';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or length(p_data::text)>3000 then raise exception 'invalid_visitor' using errcode='22023';end if;
 v_name:=btrim(regexp_replace(coalesce(p_data->>'name',''),'\s+',' ','g'));
 v_phone:=private.visitor_digits(p_data->>'phone');
 v_email:=lower(btrim(coalesce(p_data->>'email','')));
 if length(v_name)<3 or length(v_name)>120 or v_name !~ '\s' then raise exception 'visitor_name' using errcode='22023';end if;
 if length(v_phone) not between 10 and 13 then raise exception 'visitor_phone' using errcode='22023';end if;
 if v_email<>'' and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'visitor_email' using errcode='22023';end if;
 if p_source='qr' and coalesce((p_data->>'consent')::boolean,false) is not true then raise exception 'visitor_consent' using errcode='22023';end if;
 answers:=jsonb_strip_nulls(jsonb_build_object(
  'firstTime',case when jsonb_typeof(p_data->'firstTime')='boolean' then p_data->'firstTime' end,
  'heard',case when p_data->>'heard' in('friend','family','social','passing','event','online','other') then p_data->>'heard' end,
  'contact',case when jsonb_typeof(p_data->'contact')='boolean' then p_data->'contact' end,
  'visit',case when jsonb_typeof(p_data->'visit')='boolean' then p_data->'visit' end,
  'prayer',nullif(left(btrim(coalesce(p_data->>'prayer','')),500),''),
  'note',nullif(left(btrim(coalesce(p_data->>'note','')),300),'')));
 -- Proteção da página pública: no máximo 200 cadastros por igreja a cada 10 minutos.
 if p_source='qr' then
  select count(*) into recent from private.visitor_entries where unit_id=p_unit and created_at>now()-interval '10 minutes';
  if recent>=200 then raise exception 'visitor_rate' using errcode='54000';end if;
 end if;
 perform pg_advisory_xact_lock(hashtextextended('visitor:'||u.organization_id::text||':'||v_phone,0));
 select id into pid from public.people where organization_id=u.organization_id and private.visitor_digits(phone)=v_phone
  order by (status='active') desc, created_at limit 1;
 if pid is null then
  insert into public.people(organization_id,unit_id,full_name,phone,email,status,journey_status,first_visit_at,followup_status,tags)
   values(u.organization_id,u.id,v_name,v_phone,nullif(v_email,''),'active','Visitante',now(),'pending',array['Visitante'])
   returning id into pid;
 else
  update public.people set first_visit_at=coalesce(first_visit_at,now()),email=coalesce(email,nullif(v_email,'')),
   followup_status=case when journey_status='Visitante' and followup_status is null then 'pending' else followup_status end,updated_at=clock_timestamp()
   where id=pid;
 end if;
 -- Mesma pessoa no mesmo dia não gera visita repetida.
 if not exists(select 1 from private.visitor_entries where person_id=pid and unit_id=p_unit and created_at>now()-interval '12 hours') then
  insert into private.visitor_entries(organization_id,unit_id,person_id,source,answers,created_by) values(u.organization_id,p_unit,pid,p_source,answers,auth.uid());
 end if;
 if auth.uid() is not null then insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(u.organization_id,auth.uid(),'people.visitor_registered','person',pid::text,jsonb_build_object('unit_id',p_unit,'source',p_source));end if;
 return jsonb_build_object('ok',true,'firstName',split_part(v_name,' ',1),'person',case when p_source='staff' then pid end);
end $function$;
revoke all on function private.visitor_save(uuid,jsonb,text) from public,anon,authenticated;

create or replace function public.visitor_checkin(p_unit uuid, p_data jsonb) returns jsonb
language sql security definer set search_path to '' as $$ select private.visitor_save(p_unit,p_data,'qr')-'person' $$;
revoke all on function public.visitor_checkin(uuid,jsonb) from public;
grant execute on function public.visitor_checkin(uuid,jsonb) to anon,authenticated;

-- Equipe (Vinha Equipe ou painel): secretaria, pastores, administração ou quem tem "Visitantes › criar".
create or replace function public.visitor_staff(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $function$
begin
 if auth.uid() is null or not exists(select 1 from public.organization_units where id=p_unit and organization_id=p_org)
  or not (private.has_organization_role(p_org,array['owner','pastor','admin','secretary']::public.membership_role[]) or private.can(p_org,p_unit,'people.visitors','create')) then
  raise exception 'visitor_denied' using errcode='42501';end if;
 if p_action='save' then return private.visitor_save(p_unit,p_data,'staff');
 elsif p_action='recent' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('person',e.person_id,'name',p.full_name,'source',e.source,'at',e.created_at,'answers',e.answers) order by e.created_at desc)
   from (select * from private.visitor_entries where unit_id=p_unit and created_at>now()-interval '7 days' order by created_at desc limit 50) e join public.people p on p.id=e.person_id),'[]'::jsonb));
 end if;
 raise exception 'invalid_visitor' using errcode='22023';
end $function$;
revoke all on function public.visitor_staff(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.visitor_staff(uuid,uuid,text,jsonb) to authenticated;

-- Ficha da pessoa no painel: visitas registradas.
create or replace function public.person_visits(p_org uuid, p_person uuid) returns jsonb
language sql stable security definer set search_path to '' as $$
 select jsonb_build_object('items',coalesce(jsonb_agg(jsonb_build_object('at',e.created_at,'unit',u.name,'source',e.source,'answers',e.answers) order by e.created_at desc),'[]'::jsonb))
 from private.visitor_entries e join public.organization_units u on u.id=e.unit_id join public.people p on p.id=e.person_id
 where auth.uid() is not null and e.organization_id=p_org and e.person_id=p_person
  and (private.has_organization_role(p_org,array['owner','pastor','admin','secretary','leader']::public.membership_role[])
   or private.can(p_org,p.unit_id,'people.visitors','view') or private.can(p_org,p.unit_id,'people.members','view'))
$$;
revoke all on function public.person_visits(uuid,uuid) from public,anon;
grant execute on function public.person_visits(uuid,uuid) to authenticated;

-- Vinha Equipe: "Cadastrar visitante" aparece para quem pode cadastrar visitantes na igreja.
do $$ declare d text; begin
 d:=pg_get_functiondef('private.staff_access(uuid,text,jsonb)'::regprocedure);
 if position('''visitors'',' in d)=0 then
  if position('''kidsStations'',private.kids_station_manager(p_org,u.id))' in d)=0 then raise exception 'staff_access: trecho não encontrado';end if;
  execute replace(d,'''kidsStations'',private.kids_station_manager(p_org,u.id))',
   '''kidsStations'',private.kids_station_manager(p_org,u.id),''visitors'',(private.has_organization_role(p_org,array[''owner'',''pastor'',''admin'',''secretary'']::public.membership_role[]) or private.can(p_org,u.id,''people.visitors'',''create'')))');
 end if;
end $$;
