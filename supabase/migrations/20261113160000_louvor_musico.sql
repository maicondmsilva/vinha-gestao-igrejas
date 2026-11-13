-- Louvor · visão do músico no aplicativo do voluntário.
-- Quem está escalado no culto (convite ativo e não recusado) vê o repertório publicado,
-- com a cifra e o tom do dia, e pode confirmar presença no ensaio.

create table if not exists private.worship_rehearsals(
 service_id uuid not null references private.scale_services(id) on delete cascade,
 person_id uuid not null references public.people(id) on delete cascade,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 confirmed_at timestamptz not null default now(),
 primary key(service_id,person_id)
);
alter table private.worship_rehearsals enable row level security;
revoke all on private.worship_rehearsals from public,anon,authenticated,service_role;

-- O culto em que esta pessoa está escalada (convite ativo e não recusado).
create or replace function private.worship_musician_invited(p_service uuid, p_person uuid) returns boolean
language sql stable security definer set search_path to '' as $$
 select exists(select 1 from private.scale_invites i where i.service_id=p_service and i.person_id=p_person and i.active and i.response<>'declined')
$$;
revoke all on function private.worship_musician_invited(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function private.worship_musician(p_org uuid, p_action text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_person uuid; s private.scale_services; sl private.worship_setlists;
begin
 perform private.require_confirmed_self_service_email();
 p_data:=coalesce(p_data,'{}'::jsonb);
 if p_action is null or p_action not in ('list','view','rehearsal') then raise exception 'invalid_action' using errcode='22023'; end if;
 perform 1 from public.organizations where id=p_org and status in ('active','trial');
 if not found then raise exception 'worship_access_denied' using errcode='42501'; end if;
 select p.id into v_person from public.people p where p.organization_id=p_org and p.auth_user_id=auth.uid() and p.status='active' order by p.created_at limit 1;
 if v_person is null then raise exception 'worship_access_denied' using errcode='42501'; end if;

 if p_action='list' then
  return jsonb_build_object('items',coalesce((select jsonb_agg(x.item order by x.starts_at) from (
   select sv.starts_at,jsonb_build_object('service',sv.id,'title',sv.title,'startsAt',sv.starts_at,'arrivalAt',sv.arrival_at,'timezone',sv.timezone,
     'songs',(select count(*) from private.worship_setlist_items it where it.setlist_id=wl.id),
     'roles',(select coalesce(jsonb_agg(distinct r.name),'[]'::jsonb) from private.scale_invites i join private.scale_roles r on r.id=i.role_id where i.service_id=sv.id and i.person_id=v_person and i.active and i.response<>'declined'),
     'rehearsalConfirmed',exists(select 1 from private.worship_rehearsals w where w.service_id=sv.id and w.person_id=v_person)) item
   from private.scale_services sv join private.worship_setlists wl on wl.service_id=sv.id and wl.status='published'
   where sv.organization_id=p_org and sv.status='published' and sv.ends_at>now()-interval '6 hours'
    and private.worship_musician_invited(sv.id,v_person)
   order by sv.starts_at limit 10) x),'[]'::jsonb));
 end if;

 select * into s from private.scale_services where id=nullif(p_data->>'service','')::uuid and organization_id=p_org;
 select * into sl from private.worship_setlists where service_id=s.id and status='published';
 if s.id is null or sl.id is null or s.status<>'published' or not private.worship_musician_invited(s.id,v_person) then
  raise exception 'worship_access_denied' using errcode='42501';
 end if;

 if p_action='rehearsal' then
  if coalesce((p_data->>'confirmed')::boolean,false) then
   insert into private.worship_rehearsals(service_id,person_id,organization_id) values(s.id,v_person,p_org) on conflict do nothing;
  else
   delete from private.worship_rehearsals where service_id=s.id and person_id=v_person;
  end if;
  return jsonb_build_object('ok',true);
 end if;

 return jsonb_build_object('service',s.id,'title',s.title,'startsAt',s.starts_at,'arrivalAt',s.arrival_at,'timezone',s.timezone,'notes',sl.notes,
  'rehearsalConfirmed',exists(select 1 from private.worship_rehearsals w where w.service_id=s.id and w.person_id=v_person),
  'rehearsalCount',(select count(*) from private.worship_rehearsals w where w.service_id=s.id),
  'items',coalesce((select jsonb_agg(jsonb_build_object('position',it.position,'title',so.title,'artist',so.artist,'originalKey',so.original_key,
     'dayKey',coalesce(nullif(it.song_key,''),so.original_key),'bpm',so.bpm,'timeSignature',so.time_signature,'chart',so.chart,'links',so.links,
     'minister',mp.full_name,'notes',it.notes) order by it.position)
   from private.worship_setlist_items it join private.worship_songs so on so.id=it.song_id left join public.people mp on mp.id=it.minister_person_id
   where it.setlist_id=sl.id),'[]'::jsonb));
end $$;

create or replace function public.worship_musician(p_org uuid, p_action text, p_data jsonb) returns jsonb
language sql security invoker set search_path to '' as $$ select private.worship_musician(p_org,p_action,p_data) $$;
revoke all on function private.worship_musician(uuid,text,jsonb) from public,anon,service_role;
revoke all on function public.worship_musician(uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.worship_musician(uuid,text,jsonb) to authenticated;
grant execute on function public.worship_musician(uuid,text,jsonb) to authenticated;
