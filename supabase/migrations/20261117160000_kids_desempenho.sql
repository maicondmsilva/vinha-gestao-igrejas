-- Kids · desempenho: fotos em lote e índices das chaves estrangeiras usadas em filtros e junções.

-- Fotos de várias crianças numa consulta só (antes: uma chamada por criança).
-- Mesma regra da foto individual: só quem opera o Kids nesta igreja; devolve {perfil: caminho} apenas de quem tem foto.
create or replace function public.kids_child_photos(p_org uuid, p_unit uuid, p_profiles uuid[]) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
begin
 if coalesce(array_length(p_profiles,1),0)=0 then return '{}'::jsonb; end if;
 if array_length(p_profiles,1)>100 then raise exception 'kids_photos_limit' using errcode='22023'; end if;
 if not private.kids_op_allowed(p_org,p_unit,null,'read') then return '{}'::jsonb; end if;
 return coalesce((select jsonb_object_agg(k.id,p.photo_path)
  from private.kids_profiles k join public.people p on p.id=k.person_id
  where k.id=any(p_profiles) and k.organization_id=p_org and k.unit_id=p_unit and coalesce(p.photo_path,'')<>''),'{}'::jsonb);
end $$;
revoke all on function public.kids_child_photos(uuid,uuid,uuid[]) from public,anon;
grant execute on function public.kids_child_photos(uuid,uuid,uuid[]) to authenticated;

create index if not exists kids_guardian_calls_org_idx on private.kids_guardian_calls(organization_id);
create index if not exists kids_guardian_calls_unit_idx on private.kids_guardian_calls(unit_id);
create index if not exists kids_guardians_approved_by_idx on private.kids_guardians(approved_by);
create index if not exists kids_guardians_created_by_idx on private.kids_guardians(created_by);
create index if not exists kids_history_actor_idx on private.kids_history(actor_id);
create index if not exists kids_profiles_created_by_idx on private.kids_profiles(created_by);
create index if not exists kids_projectors_org_idx on private.kids_projectors(organization_id);
create index if not exists kids_session_series_org_idx on private.kids_session_series(organization_id);
create index if not exists kids_session_series_unit_idx on private.kids_session_series(unit_id);
create index if not exists kids_stations_unit_idx on private.kids_stations(unit_id);
create index if not exists kids_team_class_idx on private.kids_team(class_id);
create index if not exists kids_team_member_idx on private.kids_team(member_id);
create index if not exists kids_team_org_idx on private.kids_team(organization_id);
create index if not exists kids_team_person_idx on private.kids_team(person_id);
