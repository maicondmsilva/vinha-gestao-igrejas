-- Agenda pastoral · busca de pessoas para "quem atende" e "marcar com membro".
-- Secretaria e administração buscam na igreja; quem atende sem permissão ampla só encontra participantes das suas células.
create or replace function private.pastoral_people(p_org uuid, p_unit uuid, p_query text)
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare wide boolean; q text=btrim(coalesce(p_query,''));
begin
 if auth.uid() is null or length(q)<2 or length(q)>80 then raise exception 'invalid_pastoral' using errcode='22023';end if;
 wide:=private.can(p_org,p_unit,'pastoral.agenda','edit') or private.can(p_org,p_unit,'pastoral.settings','edit');
 if not wide and not exists(select 1 from private.pastoral_attendants a where a.organization_id=p_org and a.unit_id=p_unit and private.pastoral_self(a.id)) then raise exception 'pastoral_denied' using errcode='42501';end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'phone',coalesce(p.phone,'')) order by p.full_name) from (
  select p.* from public.people p
  where p.organization_id=p_org and p.status='active' and p.full_name ilike '%'||replace(replace(q,'%',''),'_','')||'%'
   and (wide and p.unit_id=p_unit or exists(select 1 from private.pastoral_attendants a join public.church_cells c on c.leader_person_id=a.person_id join public.church_cell_participants cp on cp.cell_id=c.id and cp.status='active'
     where a.organization_id=p_org and a.unit_id=p_unit and private.pastoral_self(a.id) and cp.person_id=p.id))
  order by p.full_name limit 20) p),'[]'::jsonb));
end $function$;
revoke all on function private.pastoral_people(uuid,uuid,text) from public,anon,authenticated;
create or replace function public.pastoral_people(p_org uuid, p_unit uuid, p_query text) returns jsonb
language sql stable security definer set search_path to '' as $$ select private.pastoral_people(p_org,p_unit,p_query) $$;
revoke all on function public.pastoral_people(uuid,uuid,text) from public,anon;
grant execute on function public.pastoral_people(uuid,uuid,text) to authenticated;
