-- Kids · Fase 3: aviso no app quando a criança entra e sai, aniversariantes e crianças ausentes.
begin;
set local lock_timeout='5s';

-- 1) Mensagens de push com texto próprio. As campanhas continuam com título e texto; um aviso individual
--    (ex.: "Ana entrou na Sala Arca") guarda o seu texto na própria mensagem.
alter table private.push_messages add column if not exists title text check(title is null or length(title) between 2 and 65);
alter table private.push_messages add column if not exists body text check(body is null or length(body) between 2 and 240);
alter table private.push_campaigns drop constraint if exists push_campaigns_source_check;
alter table private.push_campaigns add constraint push_campaigns_source_check check(source in('manual','live','birthday','kids'));

-- O envio usa o texto da mensagem quando existe.
do $$
declare def text;
begin
 def:=pg_get_functiondef('private.push_engine(text,jsonb)'::regprocedure);
 if position('''title'',camp.title,''body'',camp.body' in def)=0 then raise exception 'push_engine: trecho do envio não encontrado'; end if;
 def:=replace(def,'''title'',camp.title,''body'',camp.body','''title'',coalesce(u.title,camp.title),''body'',coalesce(u.body,camp.body)');
 execute def;
 -- A lista de campanhas do painel não mostra os avisos automáticos do Kids.
 def:=pg_get_functiondef('private.push_admin(uuid,uuid,text,uuid,integer,jsonb)'::regprocedure);
 if (length(def)-length(replace(def,'x.organization_id=p_org and private.push_unit(p_org,x.owner_unit)','')))/length('x.organization_id=p_org and private.push_unit(p_org,x.owner_unit)')<>2 then
  raise exception 'push_admin: trecho da lista não encontrado';
 end if;
 def:=replace(def,'x.organization_id=p_org and private.push_unit(p_org,x.owner_unit)','x.organization_id=p_org and x.source<>''kids'' and private.push_unit(p_org,x.owner_unit)');
 execute def;
end $$;

-- 2) Aviso à família. Vale para toda entrada e saída (painel, estação, QR, totem), porque nasce na própria presença.
--    Recebem os responsáveis aprovados e permanentes da criança que usam o app; nunca dados de saúde.
create or replace function private.kids_family_notice() returns trigger
language plpgsql security definer set search_path to '' as $$
declare child text; room text; adult text; zone text; camp uuid; run uuid; t text; b text;
begin
 if tg_op='INSERT' and new.status<>'present' then return new; end if;
 if tg_op='UPDATE' and not (old.status='present' and new.status='out') then return new; end if;
 select split_part(btrim(p.full_name),' ',1) into child from private.kids_profiles k join public.people p on p.id=k.person_id where k.id=new.profile_id;
 select r.name into room from private.kids_session_rooms g join private.kids_rooms r on r.id=g.room_id where g.id=new.group_id;
 zone:=coalesce(private.unit_timezone(new.unit_id),'America/Sao_Paulo');
 if tg_op='INSERT' then
  t:=left(coalesce(child,'Criança')||' chegou ao Kids',65);
  b:=left('Entrada às '||to_char(new.checked_in_at at time zone zone,'HH24:MI')||coalesce(' na '||room,'')||'. Guarde o comprovante para a retirada.',240);
 else
  select split_part(btrim(p.full_name),' ',1) into adult from public.people p where p.id=new.pickup_guardian;
  t:=left(coalesce(child,'Criança')||' saiu do Kids',65);
  b:=left('Retirada às '||to_char(coalesce(new.checked_out_at,clock_timestamp()) at time zone zone,'HH24:MI')||coalesce(' com '||adult,'')||'. Se não reconhece esta retirada, fale com a equipe agora.',240);
 end if;
 if not exists(select 1 from private.kids_guardians g join public.people p on p.id=g.person_id
   join private.member_push_devices d on d.user_id=p.auth_user_id and d.organization_id=new.organization_id and d.enabled and d.token is not null
   where g.profile_id=new.profile_id and g.status='approved' and not g.temporary) then return new; end if;
 insert into private.push_campaigns(organization_id,owner_unit,title,body,link,targets,source,source_key,status)
  values(new.organization_id,new.unit_id,'Avisos do Kids','Entrada e saída das crianças','{"screen":"kids"}',array[new.unit_id],'kids','kids:'||new.unit_id,'sent')
  on conflict(organization_id,source,source_key) do update set updated_at=clock_timestamp() returning id into camp;
 insert into private.push_runs(campaign_id,scheduled_for) values(camp,clock_timestamp()) on conflict do nothing returning id into run;
 if run is null then return new; end if;
 insert into private.push_messages(run_id,device_id,user_id,title,body)
  select distinct on (d.id) run,d.id,d.user_id,t,b
  from private.kids_guardians g join public.people p on p.id=g.person_id
  join private.member_push_devices d on d.user_id=p.auth_user_id and d.organization_id=new.organization_id and d.enabled and d.token is not null
  where g.profile_id=new.profile_id and g.status='approved' and not g.temporary
  on conflict do nothing;
 update private.push_runs set recipients=(select count(*) from private.push_messages where run_id=run) where id=run;
 return new;
exception when others then
 -- O aviso nunca impede a entrada ou a retirada.
 return new;
end $$;
revoke all on function private.kids_family_notice() from public,anon,authenticated;
drop trigger if exists kids_family_notice on private.kids_attendance;
create trigger kids_family_notice after insert or update of status on private.kids_attendance
 for each row execute function private.kids_family_notice();

-- 3) Aniversariantes (próximos 7 dias) e crianças ausentes (vinham e não vêm há 4 semanas), para quem opera o Kids.
create or replace function public.kids_insights(p_org uuid, p_unit uuid, p_kind text) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare today date;
begin
 if p_kind not in('birthdays','absent') then raise exception 'invalid_kids_insight' using errcode='22023'; end if;
 if not private.kids_op_allowed(p_org,p_unit,null,'read') then raise exception 'kids_denied' using errcode='42501'; end if;
 today:=(clock_timestamp() at time zone coalesce(private.unit_timezone(p_unit),'America/Sao_Paulo'))::date;
 if p_kind='birthdays' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(x order by x->>'in',x->>'name') from(
   select jsonb_build_object('profileId',k.id,'name',p.full_name,'date',to_char(p.birth_date,'DD/MM'),
     'age',extract(year from age(n.next,p.birth_date))::int,'in',(n.next-today)) x
   from private.kids_profiles k join public.people p on p.id=k.person_id
   cross join lateral (select (make_date(extract(year from today)::int,1,1)+(p.birth_date-make_date(extract(year from p.birth_date)::int,1,1))) as d) d0
   cross join lateral (select case when d0.d<today then (d0.d+interval '1 year')::date else d0.d end as next) n
   where k.organization_id=p_org and k.unit_id=p_unit and k.status='active' and p.status='active' and p.birth_date is not null
     and p.birth_date>today-interval '13 years' and n.next between today and today+6
   limit 60) s),'[]'::jsonb));
 end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(x order by x->>'last') from(
  select jsonb_build_object('profileId',k.id,'name',p.full_name,'last',to_char(max(a.checked_in_at)::date,'YYYY-MM-DD'),'visits',count(*),
   'guardians',(select string_agg(distinct split_part(gp.full_name,' ',1),', ') from private.kids_guardians g join public.people gp on gp.id=g.person_id
     where g.profile_id=k.id and g.status='approved' and not g.temporary)) x
  from private.kids_profiles k join public.people p on p.id=k.person_id
  join private.kids_attendance a on a.profile_id=k.id and a.checked_in_at>clock_timestamp()-interval '6 months'
  where k.organization_id=p_org and k.unit_id=p_unit and k.status='active' and p.status='active'
  group by k.id,p.full_name
  having count(*)>=2 and max(a.checked_in_at)<clock_timestamp()-interval '28 days'
  limit 100) s),'[]'::jsonb));
end $$;
revoke all on function public.kids_insights(uuid,uuid,text) from public,anon;
grant execute on function public.kids_insights(uuid,uuid,text) to authenticated;
commit;
