-- Células e redes em cartões: capa (imagem) opcional para cada célula e cada rede.
-- A imagem fica em bucket privado; o painel mostra por link temporário. Quem edita a célula (ou a rede) troca a capa.
begin;
set local lock_timeout='5s';

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('vinha-cell-covers','vinha-cell-covers',false,3145728,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=3145728,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

create table if not exists private.cell_covers(
 kind text not null check(kind in('cell','network')),
 target_id uuid not null,
 organization_id uuid not null references public.organizations(id) on delete cascade,
 unit_id uuid not null references public.organization_units(id) on delete cascade,
 path text not null check(length(path) between 10 and 300),
 pending_path text check(pending_path is null or length(pending_path) between 10 and 300),
 version integer not null default 1,
 updated_by uuid references auth.users(id),
 updated_at timestamptz not null default clock_timestamp(),
 primary key(kind,target_id)
);
create index if not exists cell_covers_unit_idx on private.cell_covers(organization_id,unit_id);
create index if not exists cell_covers_updated_by_idx on private.cell_covers(updated_by);
alter table private.cell_covers enable row level security;
revoke all on private.cell_covers from public,anon,authenticated;

-- Ações: list (capas da igreja), read (caminho de uma capa), prepare/finish (trocar), remove.
create or replace function public.cell_cover(p_org uuid,p_unit uuid,p_kind text,p_id uuid,p_action text,p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path to '' as $$
declare c private.cell_covers; target_ok boolean; path text; old text;
begin
 if p_action not in('list','read','prepare','finish','remove') then raise exception 'invalid_cover' using errcode='22023'; end if;
 if not (coalesce(private.cell_directory_allowed(p_org,p_unit),false) or coalesce(private.cell_people_allowed(p_org,p_unit),false)) then
  raise exception 'cell_access_denied' using errcode='42501';
 end if;
 if p_action='list' then
  return jsonb_build_object('covers',coalesce((select jsonb_object_agg(x.kind||':'||x.target_id,x.version)
   from private.cell_covers x where x.organization_id=p_org and x.unit_id=p_unit and x.path not like 'pending/%'),'{}'::jsonb));
 end if;
 if p_kind not in('cell','network') or p_id is null then raise exception 'invalid_cover' using errcode='22023'; end if;
 target_ok:=case when p_kind='cell' then exists(select 1 from public.church_cells where id=p_id and organization_id=p_org and unit_id=p_unit)
  else exists(select 1 from public.church_cell_networks where id=p_id and organization_id=p_org and unit_id=p_unit) end;
 if not target_ok then raise exception 'cover_not_found' using errcode='P0002'; end if;
 select * into c from private.cell_covers where kind=p_kind and target_id=p_id;
 if p_action='read' then return jsonb_build_object('path',c.path,'version',c.version); end if;
 if not private.cell_manage_allowed(p_org,p_unit,case when p_kind='cell' then 'cells.cells' else 'cells.networks' end) then
  raise exception 'cell_access_denied' using errcode='42501';
 end if;
 if p_action='prepare' then
  if coalesce(p_data->>'ext','') not in('jpg','png','webp') then raise exception 'invalid_cover' using errcode='22023'; end if;
  path:=p_org||'/'||p_unit||'/'||p_kind||'/'||p_id||'/'||extensions.gen_random_uuid()||'.'||(p_data->>'ext');
  if c.target_id is null then
   insert into private.cell_covers(kind,target_id,organization_id,unit_id,path,pending_path,version,updated_by)
    values(p_kind,p_id,p_org,p_unit,'pending/'||path,path,0,auth.uid());
  else update private.cell_covers set pending_path=path,updated_by=auth.uid(),updated_at=clock_timestamp() where kind=p_kind and target_id=p_id; end if;
  return jsonb_build_object('path',path);
 end if;
 if p_action='finish' then
  if c.pending_path is null or c.pending_path<>(p_data->>'path') then raise exception 'invalid_cover' using errcode='22023'; end if;
  old:=case when c.path like 'pending/%' then null else c.path end;
  update private.cell_covers set path=c.pending_path,pending_path=null,version=c.version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where kind=p_kind and target_id=p_id;
  return jsonb_build_object('ok',true,'version',c.version+1,'old',old);
 end if;
 -- remove
 delete from private.cell_covers where kind=p_kind and target_id=p_id;
 return jsonb_build_object('ok',true,'old',case when c.path like 'pending/%' then null else c.path end);
end $$;
revoke all on function public.cell_cover(uuid,uuid,text,uuid,text,jsonb) from public,anon;
grant execute on function public.cell_cover(uuid,uuid,text,uuid,text,jsonb) to authenticated;
commit;
