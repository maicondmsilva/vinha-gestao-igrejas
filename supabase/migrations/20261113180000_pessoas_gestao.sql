-- Pessoas · gestão: cadastros duplicados (detecção e unificação), busca com filtros (célula, rede, gênero,
-- faixa etária, batismo, marcador, novos convertidos), histórico do membro, ações em lote e novos convertidos.

-- ── Novos convertidos: data da decisão e acompanhamento ──────────────────────────────────────────────
alter table public.people add column if not exists converted_at date;
alter table public.people add column if not exists followup_status text;
alter table public.people add column if not exists followup_person uuid references public.people(id) on delete set null;
alter table public.people add column if not exists followup_note text;
alter table public.people add column if not exists followup_at timestamptz;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='people_followup_status_check') then
  alter table public.people add constraint people_followup_status_check
   check (followup_status is null or followup_status in ('pending','contacted','in_cell','integrated','stopped'));
 end if;
 if not exists(select 1 from pg_constraint where conname='people_followup_note_check') then
  alter table public.people add constraint people_followup_note_check check (followup_note is null or char_length(followup_note)<=500);
 end if;
end $$;
create index if not exists people_converted_idx on public.people(organization_id,unit_id,converted_at) where converted_at is not null;

-- Quem pode consultar listas de Pessoas de uma igreja (mesma regra dos aniversariantes).
create or replace function private.people_list_allowed(p_org uuid, p_unit uuid) returns boolean
language sql stable security definer set search_path to '' as $$
 select exists(select 1 from public.organization_units u join public.organizations o on o.id=u.organization_id and o.status in ('active','trial')
   where u.id=p_unit and u.organization_id=p_org)
  and (private.has_organization_role(p_org,array['owner','pastor','admin']::public.membership_role[])
   or (private.has_organization_role(p_org,array['secretary','leader']::public.membership_role[]) and private.can_access_unit(p_org,p_unit))
   or private.can(p_org,p_unit,'people.members','view') or private.can(p_org,p_unit,'people.visitors','view'))
$$;

-- Nome comparável: minúsculas, sem acento e com um espaço só entre as palavras.
create or replace function private.person_norm_name(p text) returns text
language sql immutable set search_path to '' as $$
 select btrim(regexp_replace(translate(lower(coalesce(p,'')),'áàâãäéèêëíìîïóòôõöúùûüçñý','aaaaaeeeeiiiiooooouuuucny'),'\s+',' ','g'))
$$;

-- ── Busca com filtros (lista e exportação) ───────────────────────────────────────────────────────────
-- p_filters: q, status, group, cell, network (inclui sub-redes), gender, ageMin, ageMax, baptized, tag, converts.
create or replace function private.people_search(p_org uuid, p_unit uuid, p_filters jsonb, p_page integer, p_limit integer)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare f jsonb:=coalesce(p_filters,'{}'); v_q text; v_today date; v_total int; v_ids jsonb; v_pattern text;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if jsonb_typeof(f)<>'object' or f-array['q','status','group','cell','network','gender','ageMin','ageMax','baptized','tag','converts']<>'{}'::jsonb
  or p_page is null or p_page<1 or p_page>10000 or p_limit is null or p_limit<1 or p_limit>100 then raise exception 'invalid_filters' using errcode='22023'; end if;
 if (f ? 'cell' and coalesce(f->>'cell','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or (f ? 'network' and coalesce(f->>'network','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or (f ? 'ageMin' and coalesce(f->>'ageMin','') !~ '^\d{1,3}$') or (f ? 'ageMax' and coalesce(f->>'ageMax','') !~ '^\d{1,3}$')
  or (f ? 'baptized' and jsonb_typeof(f->'baptized')<>'boolean') or (f ? 'converts' and jsonb_typeof(f->'converts')<>'boolean')
  or length(coalesce(f->>'q',''))>100 or length(coalesce(f->>'group',''))>160 or length(coalesce(f->>'tag',''))>80 or length(coalesce(f->>'gender',''))>30
  or (f ? 'status' and f->>'status' not in ('Membro','Em integração','Visitante')) then raise exception 'invalid_filters' using errcode='22023'; end if;
 if not private.people_list_allowed(p_org,p_unit) then raise exception 'people_access_denied' using errcode='42501'; end if;
 v_today:=(now() at time zone coalesce(private.unit_timezone(p_unit),'America/Sao_Paulo'))::date;
 v_q:=nullif(btrim(coalesce(f->>'q','')),'');
 v_pattern:='%'||replace(replace(replace(lower(coalesce(v_q,'')),'\','\\'),'%','\%'),'_','\_')||'%';
 with recursive nets as (
   select n.id from public.church_cell_networks n where f ? 'network' and n.id=(f->>'network')::uuid and n.organization_id=p_org
   union select np.network_id from public.church_cell_network_parents np join nets on np.parent_id=nets.id),
 found as (
  select p.id,p.created_at from public.people p
  where p.organization_id=p_org and p.unit_id=p_unit and private.person_record_view(p.id)
   and (v_q is null or lower(p.full_name) like v_pattern or lower(coalesce(p.email,'')) like v_pattern or coalesce(p.phone,'') like v_pattern
        or (regexp_replace(v_q,'\D','','g')<>'' and length(regexp_replace(v_q,'\D','','g'))>=4 and regexp_replace(coalesce(p.phone,''),'\D','','g') like '%'||regexp_replace(v_q,'\D','','g')||'%'))
   and (not f ? 'status' or p.journey_status=f->>'status')
   and (nullif(f->>'group','') is null or p.group_name=f->>'group')
   and (nullif(f->>'gender','') is null or p.gender=f->>'gender')
   and (not f ? 'baptized' or coalesce(p.baptized,false)=(f->>'baptized')::boolean)
   and (nullif(f->>'tag','') is null or p.tags @> array[f->>'tag'])
   and (not coalesce((f->>'converts')::boolean,false) or p.converted_at is not null)
   and (not f ? 'ageMin' or p.birth_date<=v_today-make_interval(years=>(f->>'ageMin')::int))
   and (not f ? 'ageMax' or p.birth_date>v_today-make_interval(years=>(f->>'ageMax')::int+1))
   and (not f ? 'cell' or exists(select 1 from public.church_cell_participants c where c.person_id=p.id and c.organization_id=p_org and c.status='active' and c.cell_id=(f->>'cell')::uuid))
   and (not f ? 'network' or exists(select 1 from public.church_cell_participants c join public.church_cell_network_links l on l.cell_id=c.cell_id and l.organization_id=p_org
        where c.person_id=p.id and c.organization_id=p_org and c.status='active' and l.network_id in (select id from nets))))
 select count(*)::int,coalesce((select jsonb_agg(x.id order by x.created_at desc,x.id desc) from (select id,created_at from found order by created_at desc,id desc offset (p_page-1)*p_limit limit p_limit) x),'[]')
  into v_total,v_ids from found;
 return jsonb_build_object('total',v_total,'ids',v_ids);
end $$;

-- ── Cadastros duplicados ─────────────────────────────────────────────────────────────────────────────
create table if not exists private.person_duplicate_dismissals(
 organization_id uuid not null references public.organizations(id) on delete cascade,
 person_a uuid not null references public.people(id) on delete cascade,
 person_b uuid not null references public.people(id) on delete cascade,
 dismissed_by uuid, created_at timestamptz not null default now(),
 primary key(person_a,person_b), check(person_a<person_b));
alter table private.person_duplicate_dismissals enable row level security;
revoke all on private.person_duplicate_dismissals from public,anon,authenticated;

create or replace function private.person_duplicate_card(p_id uuid) returns jsonb
language sql stable security definer set search_path to '' as $$
 select jsonb_build_object('id',p.id,'name',p.full_name,'email',coalesce(p.email,''),'phone',coalesce(p.phone,''),'birthDate',p.birth_date,
  'cpf',case when coalesce(p.cpf,'')='' then '' else '***.***.***-'||right(regexp_replace(p.cpf,'\D','','g'),2) end,
  'journey',p.journey_status,'status',p.status,'createdAt',p.created_at,'login',p.auth_user_id is not null,'unit',u.name,
  'cells',(select count(*) from public.church_cell_participants c where c.person_id=p.id and c.status='active'),
  'finance',(select count(*) from private.finance_entries e where e.person_id=p.id))
 from public.people p left join public.organization_units u on u.id=p.unit_id where p.id=p_id
$$;

create or replace function private.people_duplicates(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_keep public.people; v_drop public.people; v_a uuid; v_b uuid; r record; v_tid tid; v_moved int:=0; v_merged int:=0; n int;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if jsonb_typeof(coalesce(p_data,'{}'))<>'object' then raise exception 'invalid_duplicates' using errcode='22023'; end if;
 if not private.people_list_allowed(p_org,p_unit) then raise exception 'people_access_denied' using errcode='42501'; end if;
 if p_action='list' then
  return jsonb_build_object('pairs',coalesce((
   with base as (
    select p.id,p.unit_id,private.person_norm_name(p.full_name) n,split_part(private.person_norm_name(p.full_name),' ',1) f,
     nullif(regexp_replace(coalesce(p.cpf,''),'\D','','g'),'') c,
     case when length(regexp_replace(coalesce(p.phone,''),'\D','','g'))>=10 then right(regexp_replace(p.phone,'\D','','g'),10) end ph,p.birth_date b
    from public.people p where p.organization_id=p_org and p.status in ('active','pending','inactive') and private.person_record_view(p.id)),
   hits as (
    select a.id a,b.id b,'cpf' why from base a join base b on a.c=b.c and a.id<b.id
    union all select a.id,b.id,'phone' from base a join base b on a.ph=b.ph and a.f=b.f and a.id<b.id
    union all select a.id,b.id,'name' from base a join base b on a.n=b.n and a.id<b.id and (a.b is null or b.b is null or a.b=b.b)
    union all select a.id,b.id,'birth' from base a join base b on a.b=b.b and a.f=b.f and a.n<>b.n and a.id<b.id),
   pairs as (
    select h.a,h.b,array_agg(distinct h.why order by h.why) why from hits h
    join base pa on pa.id=h.a join base pb on pb.id=h.b
    where (pa.unit_id=p_unit or pb.unit_id=p_unit)
     and not exists(select 1 from private.person_duplicate_dismissals d where d.person_a=h.a and d.person_b=h.b)
    group by h.a,h.b)
   select jsonb_agg(jsonb_build_object('a',private.person_duplicate_card(x.a),'b',private.person_duplicate_card(x.b),'reasons',to_jsonb(x.why))
    order by cardinality(x.why) desc,x.a,x.b)
   from (select * from pairs order by cardinality(why) desc,a,b limit 100) x),'[]'::jsonb));
 end if;
 if p_action not in ('merge','dismiss') then raise exception 'invalid_duplicates' using errcode='22023'; end if;
 if coalesce(p_data->>'keep','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_data->>'remove','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or p_data->>'keep'=p_data->>'remove' then raise exception 'invalid_duplicates' using errcode='22023'; end if;
 if not private.has_organization_role(p_org,array['owner','pastor','admin','secretary']::public.membership_role[]) then
  raise exception 'people_access_denied' using errcode='42501'; end if;
 select * into v_keep from public.people where id=(p_data->>'keep')::uuid and organization_id=p_org for update;
 select * into v_drop from public.people where id=(p_data->>'remove')::uuid and organization_id=p_org for update;
 if v_keep.id is null or v_drop.id is null or not private.person_record_manage(v_keep.id) or not private.person_record_manage(v_drop.id) then
  raise exception 'people_access_denied' using errcode='42501'; end if;
 if p_action='dismiss' then
  v_a:=least(v_keep.id,v_drop.id); v_b:=greatest(v_keep.id,v_drop.id);
  insert into private.person_duplicate_dismissals(organization_id,person_a,person_b,dismissed_by) values(p_org,v_a,v_b,auth.uid()) on conflict do nothing;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,auth.uid(),'person.duplicate_dismissed','person',v_keep.id::text,jsonb_build_object('other',v_drop.id,'name',v_drop.full_name));
  return jsonb_build_object('ok',true);
 end if;
 if v_keep.auth_user_id is not null and v_drop.auth_user_id is not null then raise exception 'merge_both_logins' using errcode='55000'; end if;
 -- Libera os dados únicos do cadastro que sai antes de completar o que fica.
 update public.people set email=null,cpf=null,auth_user_id=null,updated_at=now() where id=v_drop.id;
 update public.people set
  email=coalesce(nullif(btrim(email),''),nullif(btrim(v_drop.email),'')), cpf=coalesce(nullif(cpf,''),nullif(v_drop.cpf,'')),
  auth_user_id=coalesce(auth_user_id,v_drop.auth_user_id), app_role=case when auth_user_id is null and v_drop.auth_user_id is not null then v_drop.app_role else app_role end,
  phone=coalesce(nullif(phone,''),v_drop.phone), birth_date=coalesce(birth_date,v_drop.birth_date), gender=coalesce(nullif(gender,''),v_drop.gender),
  marital_status=coalesce(nullif(marital_status,''),v_drop.marital_status), photo_path=coalesce(photo_path,v_drop.photo_path),
  group_name=coalesce(nullif(group_name,''),v_drop.group_name), first_visit_at=least(first_visit_at,v_drop.first_visit_at),
  joined_at=least(joined_at,v_drop.joined_at), baptized=coalesce(baptized,false) or coalesce(v_drop.baptized,false),
  baptism_date=coalesce(baptism_date,v_drop.baptism_date), marriage_date=coalesce(marriage_date,v_drop.marriage_date),
  converted_at=least(converted_at,v_drop.converted_at), followup_status=coalesce(followup_status,v_drop.followup_status),
  followup_person=coalesce(followup_person,nullif(v_drop.followup_person,v_keep.id)), followup_note=coalesce(followup_note,v_drop.followup_note),
  is_pastor=is_pastor or v_drop.is_pastor,
  tags=(select coalesce(array_agg(distinct t order by t),'{}') from unnest(coalesce(tags,'{}')||coalesce(v_drop.tags,'{}')) t),
  journey_status=case when journey_status='Membro' or v_drop.journey_status='Membro' then 'Membro'
                      when journey_status='Em integração' or v_drop.journey_status='Em integração' then 'Em integração' else journey_status end,
  status=case when status='active' or v_drop.status='active' then 'active' else status end, updated_at=now()
 where id=v_keep.id;
 -- Leva para o cadastro que fica tudo o que aponta para o que sai; o que já existe igual no que fica é descartado.
 for r in select distinct c.conrelid::regclass::text tbl,a.attname::text col
   from pg_constraint c cross join lateral unnest(c.conkey,c.confkey) k(src,dst)
   join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.src
   join pg_attribute pa on pa.attrelid=c.confrelid and pa.attnum=k.dst
   where c.contype='f' and c.confrelid='public.people'::regclass and pa.attname='id'
   order by 1,2 loop
  begin
   execute format('update %s set %I=$1 where %I=$2',r.tbl,r.col,r.col) using v_keep.id,v_drop.id;
   get diagnostics n=row_count; v_moved:=v_moved+n;
  exception when unique_violation or check_violation or exclusion_violation then
   for v_tid in execute format('select ctid from %s where %I=$1',r.tbl,r.col) using v_drop.id loop
    begin
     execute format('update %s set %I=$1 where ctid=$2',r.tbl,r.col) using v_keep.id,v_tid; v_moved:=v_moved+1;
    exception when unique_violation or check_violation or exclusion_violation then
     execute format('delete from %s where ctid=$1',r.tbl) using v_tid; v_merged:=v_merged+1;
    end;
   end loop;
  end;
 end loop;
 delete from private.person_relationships where person_id=related_person_id;
 update public.audit_logs set entity_id=v_keep.id::text where organization_id=p_org and entity_type='person' and entity_id=v_drop.id::text;
 delete from public.people where id=v_drop.id;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_org,auth.uid(),'person.merged','person',v_keep.id::text,jsonb_build_object('removed',v_drop.id,'name',v_drop.full_name,'moved',v_moved,'merged',v_merged));
 return jsonb_build_object('ok',true,'keep',v_keep.id,'moved',v_moved,'merged',v_merged);
end $$;

-- ── Histórico do membro ──────────────────────────────────────────────────────────────────────────────
create or replace function private.person_timeline(p_org uuid, p_person uuid)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare p public.people;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 select * into p from public.people where id=p_person and organization_id=p_org;
 if p.id is null or not private.person_record_view(p.id)
  or not private.has_organization_role(p_org,array['owner','pastor','admin','secretary','leader','finance']::public.membership_role[]) and not private.can(p_org,p.unit_id,'people.members','view') and not private.can(p_org,p.unit_id,'people.visitors','view') then
  raise exception 'people_access_denied' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(e order by e->>'at' desc,e->>'title') from (
  select jsonb_build_object('at',to_jsonb(p.created_at),'kind','record','title','Cadastro criado','detail',null) e
  union all select jsonb_build_object('at',to_jsonb(p.first_visit_at),'kind','visit','title','Primeira visita','detail',null) where p.first_visit_at is not null
  union all select jsonb_build_object('at',to_jsonb(p.converted_at),'kind','faith','title','Decisão por Jesus','detail',null) where p.converted_at is not null
  union all select jsonb_build_object('at',to_jsonb(p.baptism_date),'kind','faith','title','Batismo','detail',null) where p.baptism_date is not null
  union all select jsonb_build_object('at',to_jsonb(p.joined_at),'kind','journey','title','Entrada como membro','detail',null) where p.joined_at is not null and p.journey_status='Membro'
  union all select jsonb_build_object('at',to_jsonb(p.marriage_date),'kind','family','title','Casamento','detail',null) where p.marriage_date is not null
  union all select jsonb_build_object('at',to_jsonb(l.created_at),'kind',case when l.action like 'people.family%' then 'family' else 'record' end,
    'title',case l.action when 'person.created' then 'Cadastro registrado na ficha' when 'person.updated' then 'Ficha atualizada'
      when 'person.merged' then 'Cadastro duplicado unificado' when 'person.duplicate_dismissed' then 'Marcado como pessoa diferente de um possível duplicado'
      when 'people.bulk.journey' then 'Etapa alterada em lote' when 'people.bulk.tag' then 'Marcador adicionado em lote' when 'people.bulk.untag' then 'Marcador removido em lote'
      when 'people.convert.updated' then 'Acompanhamento de novo convertido atualizado'
      else case when l.action like 'people.family%' then 'Vínculo familiar atualizado' else 'Registro: '||l.action end end,
    'detail',nullif(concat_ws(' · ',nullif(pr.full_name,''),l.metadata->>'name',l.metadata->>'to',l.metadata->>'tag',l.metadata->>'status'),''))
   from public.audit_logs l left join public.profiles pr on pr.id=l.actor_user_id
   where l.organization_id=p_org and l.entity_type='person' and l.entity_id=p.id::text
  union all select jsonb_build_object('at',to_jsonb(c.created_at),'kind','cell','title','Entrou na célula','detail',cc.name)
   from public.church_cell_participants c join public.church_cells cc on cc.id=c.cell_id where c.person_id=p.id and c.organization_id=p_org
  union all select jsonb_build_object('at',to_jsonb(c.updated_at),'kind','cell','title','Saiu da célula','detail',cc.name)
   from public.church_cell_participants c join public.church_cells cc on cc.id=c.cell_id where c.person_id=p.id and c.organization_id=p_org and c.status='inactive'
  union all select jsonb_build_object('at',to_jsonb(v.visit_date),'kind','cell','title','Visitou a célula','detail',cc.name)
   from public.church_cell_visits v join public.church_cells cc on cc.id=v.cell_id where v.person_id=p.id and v.organization_id=p_org
  union all select jsonb_build_object('at',to_jsonb(t.created_at),'kind','cell','title','Transferência de célula',
    'detail',concat_ws(' → ',s.name,d.name)||case t.status when 'accepted' then ' (aprovada)' when 'rejected' then ' (recusada)' when 'pending' then ' (aguardando)' when 'cancelled' then ' (cancelada)' else '' end)
   from public.church_cell_transfers t left join public.church_cells s on s.id=t.source_cell_id left join public.church_cells d on d.id=t.target_cell_id
   where t.person_id=p.id and t.organization_id=p_org
  union all select jsonb_build_object('at',to_jsonb(t.created_at),'kind','journey','title','Transferência de igreja',
    'detail',concat_ws(' → ',s.name,d.name)||case t.status when 'approved' then ' (aprovada)' when 'rejected' then ' (recusada)' when 'pending' then ' (aguardando)' when 'cancelled' then ' (cancelada)' else '' end)
   from private.member_church_transfers t left join public.organization_units s on s.id=t.source_unit left join public.organization_units d on d.id=t.target_unit
   where t.person_id=p.id and t.organization_id=p_org
  union all select jsonb_build_object('at',to_jsonb(r.created_at),'kind','app',
    'title',case r.kind when 'registration' then 'Cadastro feito pelo aplicativo' when 'relative' then 'Pedido de familiar pelo aplicativo' else 'Atualização de dados pelo aplicativo' end,
    'detail',case r.status when 'approved' then 'aprovado' when 'partial' then 'aprovado em parte' when 'rejected' then 'recusado' when 'pending' then 'aguardando análise' else r.status end)
   from private.member_profile_requests r where r.person_id=p.id and r.organization_id=p_org
  union all select jsonb_build_object('at',to_jsonb(max(i.invited_at)),'kind','service','title','Escalas',
    'detail',count(*)||' convite(s) de escala · '||count(*) filter (where i.response='accepted')||' aceito(s) · '||count(*) filter (where i.presence='present')||' presença(s)')
   from private.scale_invites i where i.person_id=p.id and i.organization_id=p_org having count(*)>0
 ) x where e->>'at' is not null),'[]'::jsonb);
end $$;

-- ── Novos convertidos ────────────────────────────────────────────────────────────────────────────────
create or replace function private.people_converts(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_today date; v_days int; p public.people; v_status text; v_follow uuid; v_date date;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if jsonb_typeof(coalesce(p_data,'{}'))<>'object' then raise exception 'invalid_convert' using errcode='22023'; end if;
 if not private.people_list_allowed(p_org,p_unit) then raise exception 'people_access_denied' using errcode='42501'; end if;
 v_today:=(now() at time zone coalesce(private.unit_timezone(p_unit),'America/Sao_Paulo'))::date;
 if p_action='list' then
  v_days:=coalesce(nullif(p_data->>'days','')::int,90);
  if v_days not in (30,90,180,365) then raise exception 'invalid_convert' using errcode='22023'; end if;
  return (with list as (
    select pp.*,
     (select string_agg(cc.name,', ' order by cc.name) from public.church_cell_participants c join public.church_cells cc on cc.id=c.cell_id
       where c.person_id=pp.id and c.status='active') cells
    from public.people pp
    where pp.organization_id=p_org and pp.unit_id=p_unit and pp.converted_at is not null and pp.status not in ('rejected','deceased')
     and (pp.converted_at>=v_today-v_days or coalesce(pp.followup_status,'pending') in ('pending','contacted')) and private.person_record_view(pp.id))
   select jsonb_build_object('today',v_today,
    'counts',jsonb_build_object('total',count(*),'pending',count(*) filter (where coalesce(followup_status,'pending')='pending'),
      'contacted',count(*) filter (where followup_status='contacted'),'in_cell',count(*) filter (where followup_status='in_cell'),
      'integrated',count(*) filter (where followup_status='integrated'),'stopped',count(*) filter (where followup_status='stopped'),
      'late',count(*) filter (where coalesce(followup_status,'pending')='pending' and converted_at<v_today-7)),
    'items',coalesce(jsonb_agg(jsonb_build_object('person',l.id,'name',l.full_name,'phone',coalesce(l.phone,''),'convertedAt',l.converted_at,
      'days',v_today-l.converted_at,'status',coalesce(l.followup_status,'pending'),'followup',l.followup_person,
      'followupName',(select f.full_name from public.people f where f.id=l.followup_person),'note',coalesce(l.followup_note,''),
      'cells',coalesce(l.cells,''),'journey',l.journey_status,'updatedAt',l.followup_at) order by l.converted_at desc,l.full_name),'[]'::jsonb))
   from list l);
 end if;
 if p_action<>'save' then raise exception 'invalid_convert' using errcode='22023'; end if;
 if p_data-array['person','convertedAt','status','followup','note']<>'{}'::jsonb
  or coalesce(p_data->>'person','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or (nullif(p_data->>'followup','') is not null and p_data->>'followup' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or (nullif(p_data->>'convertedAt','') is not null and p_data->>'convertedAt' !~ '^\d{4}-\d{2}-\d{2}$')
  or length(coalesce(p_data->>'note',''))>500 then raise exception 'invalid_convert' using errcode='22023'; end if;
 select * into p from public.people where id=(p_data->>'person')::uuid and organization_id=p_org and unit_id=p_unit for update;
 if p.id is null or not private.person_record_manage(p.id) then raise exception 'people_access_denied' using errcode='42501'; end if;
 v_status:=coalesce(nullif(p_data->>'status',''),p.followup_status,'pending');
 if v_status not in ('pending','contacted','in_cell','integrated','stopped') then raise exception 'invalid_convert' using errcode='22023'; end if;
 v_date:=case when p_data ? 'convertedAt' then nullif(p_data->>'convertedAt','')::date else p.converted_at end;
 if v_date is null and not p_data ? 'convertedAt' then v_date:=v_today; end if;
 if v_date is not null and (v_date>v_today or v_date<v_today-36500) then raise exception 'invalid_convert' using errcode='22023'; end if;
 v_follow:=case when p_data ? 'followup' then nullif(p_data->>'followup','')::uuid else p.followup_person end;
 if v_follow is not null and (v_follow=p.id or not exists(select 1 from public.people f where f.id=v_follow and f.organization_id=p_org and f.status='active')) then
  raise exception 'invalid_convert' using errcode='22023'; end if;
 update public.people set converted_at=v_date,followup_status=case when v_date is null then null else v_status end,followup_person=case when v_date is null then null else v_follow end,
  followup_note=case when v_date is null then null when p_data ? 'note' then nullif(btrim(p_data->>'note'),'') else followup_note end,followup_at=now(),updated_at=now()
 where id=p.id;
 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
  values(p_org,auth.uid(),'people.convert.updated','person',p.id::text,jsonb_build_object('status',case v_status when 'pending' then 'aguardando contato' when 'contacted' then 'contato feito'
   when 'in_cell' then 'em célula' when 'integrated' then 'integrado' else 'sem retorno' end,'convertedAt',v_date));
 return jsonb_build_object('ok',true);
end $$;

-- ── Ações em lote ────────────────────────────────────────────────────────────────────────────────────
create or replace function private.people_bulk(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}')
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_ids uuid[]; v_value text; v_n int:=0; v_units jsonb; v_push jsonb; v_aud jsonb;
begin
 if auth.uid() is null then raise exception 'authentication_required' using errcode='28000'; end if;
 if jsonb_typeof(coalesce(p_data,'{}'))<>'object' or jsonb_typeof(p_data->'ids')<>'array'
  or jsonb_array_length(p_data->'ids') not between 1 and (case when p_action in ('notify','notify_preview') then 250 else 500 end)
  or exists(select 1 from jsonb_array_elements(p_data->'ids') v where jsonb_typeof(v)<>'string' or v#>>'{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or p_action not in ('journey','tag','untag','notify','notify_preview') then raise exception 'invalid_bulk' using errcode='22023'; end if;
 if not private.people_list_allowed(p_org,p_unit) then raise exception 'people_access_denied' using errcode='42501'; end if;
 select array_agg(distinct v::uuid) into v_ids from jsonb_array_elements_text(p_data->'ids') v;
 if (select count(*) from public.people p where p.id=any(v_ids) and p.organization_id=p_org and p.unit_id=p_unit and private.person_record_manage(p.id))<>cardinality(v_ids) then
  raise exception 'people_bulk_denied' using errcode='42501'; end if;
 if p_action='journey' then
  v_value:=p_data->>'value';
  if v_value is null or v_value not in ('Visitante','Em integração','Membro') then raise exception 'invalid_bulk' using errcode='22023'; end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   select p_org,auth.uid(),'people.bulk.journey','person',p.id::text,jsonb_build_object('from',p.journey_status,'to',v_value)
   from public.people p where p.id=any(v_ids) and p.journey_status is distinct from v_value;
  update public.people set journey_status=v_value,joined_at=case when v_value='Membro' then coalesce(joined_at,now()) else joined_at end,updated_at=now()
   where id=any(v_ids) and journey_status is distinct from v_value;
  get diagnostics v_n=row_count;
  return jsonb_build_object('ok',true,'updated',v_n);
 elsif p_action in ('tag','untag') then
  v_value:=btrim(coalesce(p_data->>'value',''));
  if length(v_value) not between 1 and 40 then raise exception 'invalid_bulk' using errcode='22023'; end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   select p_org,auth.uid(),'people.bulk.'||p_action,'person',p.id::text,jsonb_build_object('tag',v_value)
   from public.people p where p.id=any(v_ids) and (case when p_action='tag' then not coalesce(p.tags,'{}') @> array[v_value] else coalesce(p.tags,'{}') @> array[v_value] end);
  update public.people set tags=case when p_action='tag' then coalesce(tags,'{}')||v_value else array_remove(tags,v_value) end,updated_at=now()
   where id=any(v_ids) and (case when p_action='tag' then not coalesce(tags,'{}') @> array[v_value] else coalesce(tags,'{}') @> array[v_value] end);
  get diagnostics v_n=row_count;
  return jsonb_build_object('ok',true,'updated',v_n);
 end if;
 -- Comunicado: notificação no aplicativo para as pessoas escolhidas que usam o app.
 select jsonb_agg(u.id order by u.id) into v_units from public.organization_units u where u.organization_id=p_org and u.status='active' and private.push_unit(p_org,u.id);
 if v_units is null then raise exception 'push_denied' using errcode='42501'; end if;
 v_aud:=jsonb_build_object('people',to_jsonb(v_ids));
 if p_action='notify_preview' then
  v_push:=private.push_admin(p_org,p_unit,'preview',null,null,jsonb_build_object('targets',v_units,'audience',v_aud));
  return v_push||jsonb_build_object('selected',cardinality(v_ids));
 end if;
 v_push:=private.push_admin(p_org,p_unit,'create',null,null,jsonb_build_object('targets',v_units,'audience',v_aud,'title',p_data->'title','body',p_data->'body',
  'mode','now','request',p_data->'request'));
 return jsonb_build_object('ok',true,'campaign',v_push->'campaign','repeated',coalesce(v_push->'repeated','false'::jsonb));
end $$;

-- Público "pessoas escolhidas" nas notificações (usado pelo comunicado em lote).
do $$
declare d text; n int;
begin
 d:=pg_get_functiondef('private.push_audience_check(jsonb)'::regprocedure);
 if position('people_audience_check' in d)=0 then
  n:=(length(d)-length(replace(d,'''event'',''birthdayToday'')','')))/length('''event'',''birthdayToday'')');
  if n<>1 then raise exception 'push_audience_check: trecho esperado não encontrado (%)',n; end if;
  d:=replace(d,'''event'',''birthdayToday'')','''event'',''birthdayToday'',''people'')');
  n:=(length(d)-length(replace(d,'end $function$','')))/length('end $function$');
  if n<>1 then raise exception 'push_audience_check: final não encontrado (%)',n; end if;
  d:=replace(d,'end $function$',' -- people_audience_check
 if p ? ''people'' and (jsonb_typeof(p->''people'')<>''array'' or jsonb_array_length(p->''people'') not between 1 and 250
  or exists(select 1 from jsonb_array_elements(p->''people'') v where jsonb_typeof(v)<>''string'' or v#>>''{}'' !~ ''^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'')) then raise exception ''invalid_push_audience'' using errcode=''22023'';end if;
end $function$');
  execute d;
 end if;
 d:=pg_get_functiondef('private.push_audience(uuid,uuid[],jsonb)'::regprocedure);
 if position('people_audience' in d)=0 then
  n:=(length(d)-length(replace(d,'''tags'',''baptized'',''birthdayToday'']','')))/length('''tags'',''baptized'',''birthdayToday'']');
  if n<>1 then raise exception 'push_audience: trecho esperado não encontrado (%)',n; end if;
  d:=replace(d,'''tags'',''baptized'',''birthdayToday'']','''tags'',''baptized'',''birthdayToday'',''people'']');
  n:=(length(d)-length(replace(d,'  and (not p_audience ? ''roles''','')))/length('  and (not p_audience ? ''roles''');
  if n<>1 then raise exception 'push_audience: trecho de funções não encontrado (%)',n; end if;
  d:=replace(d,'  and (not p_audience ? ''roles''','  and (not p_audience ? ''people'' or p.id::text in(select jsonb_array_elements_text(p_audience->''people''))) -- people_audience
  and (not p_audience ? ''roles''');
  execute d;
 end if;
end $$;

-- ── Funções públicas ─────────────────────────────────────────────────────────────────────────────────
create or replace function public.people_search(p_org uuid, p_unit uuid, p_filters jsonb, p_page integer, p_limit integer) returns jsonb
language sql stable security invoker set search_path to '' as $$ select private.people_search(p_org,p_unit,p_filters,p_page,p_limit) $$;
create or replace function public.people_duplicates(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path to '' as $$ select private.people_duplicates(p_org,p_unit,p_action,p_data) $$;
create or replace function public.person_timeline(p_org uuid, p_person uuid) returns jsonb
language sql stable security invoker set search_path to '' as $$ select private.person_timeline(p_org,p_person) $$;
create or replace function public.people_converts(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path to '' as $$ select private.people_converts(p_org,p_unit,p_action,p_data) $$;
create or replace function public.people_bulk(p_org uuid, p_unit uuid, p_action text, p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path to '' as $$ select private.people_bulk(p_org,p_unit,p_action,p_data) $$;

revoke all on function private.people_list_allowed(uuid,uuid) from public,anon,service_role;
revoke all on function private.person_norm_name(text) from public,anon;
revoke all on function private.person_duplicate_card(uuid) from public,anon,authenticated,service_role;
do $$ declare f text; begin
 foreach f in array array['people_search(uuid,uuid,jsonb,integer,integer)','people_duplicates(uuid,uuid,text,jsonb)','person_timeline(uuid,uuid)',
   'people_converts(uuid,uuid,text,jsonb)','people_bulk(uuid,uuid,text,jsonb)'] loop
  execute format('revoke all on function private.%s from public,anon,service_role',f);
  execute format('revoke all on function public.%s from public,anon,service_role',f);
  execute format('grant execute on function private.%s to authenticated',f);
  execute format('grant execute on function public.%s to authenticated',f);
 end loop;
end $$;
grant execute on function private.people_list_allowed(uuid,uuid) to authenticated;
