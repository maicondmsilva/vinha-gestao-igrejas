-- Relatórios financeiros por Célula e por Rede.
-- A célula vem do cadastro do membro ligado ao lançamento (participante ativo ou líder de uma
-- célula ativa); a rede é a da célula, e o filtro de rede inclui as sub-redes. Nada é gravado no
-- lançamento: se o membro mudar de célula, o relatório acompanha o cadastro atual.
-- Como revela a ligação entre pessoas e valores, segue a mesma regra do filtro por pessoa.

create function private.finance_person_cells(p_org uuid,p_person uuid)
returns table(cell_id uuid,cell_name text,network_id uuid,network_name text)
language sql stable security definer set search_path='' as $$
 select c.id,c.name,n.id,n.name
 from public.church_cells c
 left join public.church_cell_network_links l on l.cell_id=c.id and l.organization_id=c.organization_id
 left join public.church_cell_networks n on n.id=l.network_id and n.organization_id=c.organization_id and n.status='active'
 where p_person is not null and c.organization_id=p_org and c.status='active'
  and (c.leader_person_id=p_person or exists(select 1 from public.church_cell_participants p
   where p.cell_id=c.id and p.organization_id=p_org and p.person_id=p_person and p.status='active'))
$$;
revoke all on function private.finance_person_cells(uuid,uuid) from public,anon,authenticated,service_role;

create function private.finance_network_tree(p_org uuid,p_network uuid) returns setof uuid
language sql stable security definer set search_path='' as $$
 with recursive t(id) as (
  select p_network
  union
  select n.network_id from public.church_cell_network_parents n join t on n.parent_id=t.id where n.organization_id=p_org
 ) select id from t
$$;
revoke all on function private.finance_network_tree(uuid,uuid) from public,anon,authenticated,service_role;

alter function private.finance_f6(uuid,uuid[],text,jsonb) rename to finance_f6_before_cells;
create function private.finance_f6(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r jsonb;v_cell uuid;v_network uuid;nets uuid[];v_rows jsonb;filtering boolean;
begin
 v_cell:=nullif(p_data->>'cell','')::uuid;v_network:=nullif(p_data->>'network','')::uuid;filtering:=v_cell is not null or v_network is not null;
 if p_action='report' and filtering and p_data->>'report' in('budget','divergences') then raise exception 'cell_filter_not_supported' using errcode='22023';end if;
 r:=private.finance_f6_before_cells(p_org,p_units,p_action,p_data-'cell'-'network');
 if jsonb_typeof(r->'rows') is distinct from 'array' then return r;end if;
 if filtering and coalesce((r->>'individualAccess')::boolean,false)=false then raise exception 'individual_contributions_restricted' using errcode='42501';end if;
 if v_network is not null then select array_agg(x) into nets from private.finance_network_tree(p_org,v_network) x;end if;

 -- Célula e rede de cada linha (só para quem pode ver pessoas) e filtro antes de totais e exportações.
 select coalesce(jsonb_agg(x.value||case when coalesce((r->>'individualAccess')::boolean,false) then jsonb_build_object('cellName',m.cells,'networkName',m.networks) else '{}'::jsonb end order by x.ordinality),'[]')
 into v_rows
 from jsonb_array_elements(r->'rows') with ordinality x
 left join lateral (
  select string_agg(distinct pc.cell_name,', ') cells,string_agg(distinct pc.network_name,', ') networks,
   coalesce(bool_or(pc.cell_id=v_cell),false) in_cell,coalesce(bool_or(pc.network_id=any(nets)),false) in_net
  from private.finance_entries e cross join lateral private.finance_person_cells(p_org,e.person_id) pc
  where e.id=nullif(x.value->>'id','')::uuid and e.organization_id=p_org
 ) m on true
 where (v_cell is null or coalesce(m.in_cell,false)) and (v_network is null or coalesce(m.in_net,false));
 r:=jsonb_set(r,'{rows}',v_rows);

 if filtering then
  -- Pagamentos online (relatório do provedor) pela pessoa do pedido.
  if jsonb_typeof(r->'digital')='array' then
   r:=jsonb_set(r,'{digital}',coalesce((select jsonb_agg(d.value order by d.ordinality) from jsonb_array_elements(r->'digital') with ordinality d
    where exists(select 1 from private.finance_digital_receipts rec join private.finance_digital_orders o on o.id=rec.order_id
     cross join lateral private.finance_person_cells(p_org,o.person_id) pc
     where rec.id=nullif(d.value->>'id','')::uuid and o.organization_id=p_org
      and (v_cell is null or pc.cell_id=v_cell) and (v_network is null or pc.network_id=any(nets)))),'[]'));
  end if;
  -- Partidas contábeis só dos lançamentos que ficaram no relatório.
  if jsonb_typeof(r->'accounting')='array' then
   r:=jsonb_set(r,'{accounting}',coalesce((select jsonb_agg(a.value order by a.ordinality) from jsonb_array_elements(r->'accounting') with ordinality a
    where a.value->>'journal' in(select y.value->>'journal' from jsonb_array_elements(v_rows) y)),'[]'));
  end if;
 end if;

 return r||jsonb_build_object(
  'filters',coalesce(r->'filters','{}'::jsonb)||jsonb_build_object('cell',coalesce(p_data->>'cell',''),'network',coalesce(p_data->>'network','')),
  'cells',case when coalesce((r->>'individualAccess')::boolean,false) then (select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name),'[]') from public.church_cells c where c.organization_id=p_org and c.unit_id=any(p_units) and c.status='active') else '[]'::jsonb end,
  'networks',case when coalesce((r->>'individualAccess')::boolean,false) then (select coalesce(jsonb_agg(jsonb_build_object('id',n.id,'name',n.name) order by n.name),'[]') from public.church_cell_networks n where n.organization_id=p_org and n.unit_id=any(p_units) and n.status='active') else '[]'::jsonb end);
end $$;
revoke all on function private.finance_f6(uuid,uuid[],text,jsonb),private.finance_f6_before_cells(uuid,uuid[],text,jsonb) from public,anon,authenticated,service_role;
-- A função pública (invoker) continua chamando a função privada protegida.
grant execute on function private.finance_f6(uuid,uuid[],text,jsonb) to authenticated;
