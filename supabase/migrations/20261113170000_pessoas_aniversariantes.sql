-- Pessoas · aniversariantes do dia, da semana (próximos 7 dias) e do mês, de nascimento e de casamento.
-- Datas no fuso da igreja. Mostra só pessoas que quem consulta pode ver.

-- Próxima data de aniversário a partir de um dia (29/02 vira 28/02 em anos não bissextos).
create or replace function private.next_anniversary(p_date date, p_from date) returns date
language sql immutable set search_path to '' as $$
 select case when d>=p_from then d else
   make_date(extract(year from p_from)::int+1,extract(month from p_date)::int,least(extract(day from p_date)::int,extract(day from (make_date(extract(year from p_from)::int+1,extract(month from p_date)::int,1)+interval '1 month - 1 day'))::int)) end
 from (select make_date(extract(year from p_from)::int,extract(month from p_date)::int,
   least(extract(day from p_date)::int,extract(day from (make_date(extract(year from p_from)::int,extract(month from p_date)::int,1)+interval '1 month - 1 day'))::int)) d) x
$$;

create or replace function private.people_birthdays(p_org uuid, p_unit uuid, p_range text)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare v_today date; v_from date; v_to date; v_month_end date;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if p_range is null or p_range not in ('today','week','month') then raise exception 'invalid_range' using errcode='22023'; end if;
 if not exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id and o.status in ('active','trial')
   where u.id=p_unit and u.organization_id=p_org) then raise exception 'people_access_denied' using errcode='42501'; end if;
 if not (private.has_organization_role(p_org,array['owner','pastor','admin']::public.membership_role[])
   or (private.has_organization_role(p_org,array['secretary','leader']::public.membership_role[]) and private.can_access_unit(p_org,p_unit))
   or private.can(p_org,p_unit,'people.members','view') or private.can(p_org,p_unit,'people.visitors','view')) then
  raise exception 'people_access_denied' using errcode='42501';
 end if;
 v_today:=(now() at time zone coalesce(private.unit_timezone(p_unit),'America/Sao_Paulo'))::date;
 v_month_end:=(date_trunc('month',v_today)+interval '1 month - 1 day')::date;
 v_from:=case p_range when 'month' then date_trunc('month',v_today)::date else v_today end;
 v_to:=case p_range when 'today' then v_today when 'week' then v_today+6 else v_month_end end;
 return jsonb_build_object('today',v_today,'from',v_from,'to',v_to,
  'counts',(select jsonb_build_object(
    'today',count(*) filter (where x.next=v_today),
    'week',count(*) filter (where x.next between v_today and v_today+6),
    'month',count(*) filter (where x.next_m between date_trunc('month',v_today)::date and v_month_end))
   from (select private.next_anniversary(e.d,v_today) next,private.next_anniversary(e.d,date_trunc('month',v_today)::date) next_m
    from public.people p cross join lateral (values(p.birth_date),(p.marriage_date)) e(d)
    where p.organization_id=p_org and p.unit_id=p_unit and p.status not in ('rejected','deceased','inactive') and e.d is not null
     and private.person_record_view(p.id)) x),
  'items',coalesce((select jsonb_agg(jsonb_build_object('person',x.id,'name',x.full_name,'kind',x.kind,'date',x.next,
     'years',extract(year from x.next)::int-extract(year from x.d)::int,'phone',x.phone,'journey',x.journey_status) order by x.next,x.full_name)
   from (select p.id,p.full_name,p.phone,p.journey_status,e.kind,e.d,private.next_anniversary(e.d,v_from) next
    from public.people p cross join lateral (values('birthday',p.birth_date),('wedding',p.marriage_date)) e(kind,d)
    where p.organization_id=p_org and p.unit_id=p_unit and p.status not in ('rejected','deceased','inactive') and e.d is not null
     and private.person_record_view(p.id)) x
   where x.next between v_from and v_to),'[]'::jsonb));
end $$;

create or replace function public.people_birthdays(p_org uuid, p_unit uuid, p_range text) returns jsonb
language sql stable security invoker set search_path to '' as $$ select private.people_birthdays(p_org,p_unit,p_range) $$;
revoke all on function private.next_anniversary(date,date) from public,anon;
revoke all on function private.people_birthdays(uuid,uuid,text) from public,anon,service_role;
revoke all on function public.people_birthdays(uuid,uuid,text) from public,anon,service_role;
grant execute on function private.people_birthdays(uuid,uuid,text) to authenticated;
grant execute on function public.people_birthdays(uuid,uuid,text) to authenticated;
