-- Contribua · cartões de contribuição personalizáveis (identidade Vinha).
-- A igreja cria quantos cartões quiser (Dízimo, Oferta, Missões…), com imagem, cor, frase e valores sugeridos.
-- O pagamento usa a conta recebedora marcada como PRINCIPAL da igreja (produção, configurada).
-- Cada cartão tem uma finalidade financeira (criada sozinha na conta da principal), para a contabilidade sair certa.

create table if not exists private.giving_cards(
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id),
 unit_id uuid not null,
 purpose_id uuid not null references private.finance_purposes(id),
 title text not null check(length(btrim(title)) between 2 and 40),
 subtitle text not null default '' check(length(subtitle)<=160),
 image text not null default '' check(length(image)<=2000),
 color text not null default '#285c45' check(color ~ '^#[0-9a-fA-F]{6}$'),
 amounts integer[] not null default '{}' check(cardinality(amounts)<=6),
 position integer not null default 0,
 active boolean not null default true,
 version integer not null default 1,
 created_by uuid references auth.users(id),
 updated_at timestamptz not null default clock_timestamp(),
 foreign key(unit_id,organization_id) references public.organization_units(id,organization_id)
);
create index if not exists giving_cards_unit on private.giving_cards(organization_id,unit_id,position);
alter table private.giving_cards enable row level security;
revoke all on private.giving_cards from public,anon,authenticated;

-- Conta principal da igreja (produção, pronta para receber).
create or replace function private.giving_primary(p_org uuid,p_unit uuid) returns private.finance_receivers
language sql stable security definer set search_path to '' as $$
 select r.* from private.finance_receivers r
 where r.organization_id=p_org and r.is_primary and r.environment='production' and r.status='configured' and r.holder_confirmed and r.payments_enabled and r.webhook_configured
  and cardinality(r.methods)>0 and r.expires_at>clock_timestamp() and p_unit=any(r.beneficiary_units) and private.receiver_actor_allowed(r.created_by,p_org,r.unit_id)
 order by (r.unit_id=p_unit) desc limit 1
$$;
revoke all on function private.giving_primary(uuid,uuid) from public,anon,authenticated;

-- A finalidade do cartão recebe pela conta principal (sem precisar publicar no catálogo).
do $$ declare d text; begin
 d:=pg_get_functiondef('private.member_payment_receiver(uuid,uuid,uuid)'::regprocedure);
 if position('giving_cards' in d)=0 then
  if position(' return result;' in d)=0 then raise exception 'member_payment_receiver: trecho não encontrado';end if;
  d:=replace(d,' return result;',' if result is null and exists(select 1 from private.giving_cards g where g.purpose_id=p_purpose and g.organization_id=p_org and g.unit_id=p_unit and g.active) then
  select r.id into result from private.finance_purposes p, private.giving_primary(p_org,p_unit) r
   where p.id=p_purpose and p.organization_id=p_org and p.unit_id=p_unit and p.active and r.id is not null and r.account_id=p.account_id;
 end if;
 return result;');
  execute d;
 end if;
end $$;

-- App: os cartões ativos que podem receber.
do $$ declare d text; begin
 d:=pg_get_functiondef('private.member_payments(uuid,uuid,text,jsonb)'::regprocedure);
 if position('''cards''' in d)=0 then
  if position('return jsonb_build_object(''purposes'',' in d)=0 then raise exception 'member_payments: trecho não encontrado';end if;
  d:=replace(d,'return jsonb_build_object(''purposes'',','return jsonb_build_object(''cards'',coalesce((select jsonb_agg(jsonb_build_object(''id'',g.id,''purpose'',g.purpose_id,''title'',g.title,''subtitle'',g.subtitle,''image'',g.image,''color'',g.color,''amounts'',to_jsonb(g.amounts)) order by g.position,g.title)
   from private.giving_cards g where g.organization_id=p_org and g.unit_id=p_unit and g.active and private.member_payment_receiver(p_org,p_unit,g.purpose_id) is not null),''[]''),''purposes'',');
  execute d;
 end if;
end $$;

-- Painel: gerenciar os cartões (administração da igreja com acesso de gestão e módulo financeiro).
create or replace function private.giving_admin(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare c private.giving_cards; prim private.finance_receivers; base private.finance_purposes; pid uuid; cat uuid; v int; amts int[]; v_origin text;
begin
 if auth.uid() is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'giving_invalid' using errcode='22023';end if;
 if not private.has_organization_role(p_org,array['owner','admin']::public.membership_role[]) or not private.can_access_unit(p_org,p_unit,array['manage','admin']::public.unit_access_level[])
  or not private.target_unit_module_enabled(p_org,p_unit,'finance') then raise exception 'giving_denied' using errcode='42501';end if;
 prim:=private.giving_primary(p_org,p_unit);
 if p_action='list' then
  return jsonb_build_object(
   'primary',case when prim.id is null then null else jsonb_build_object('provider',prim.provider,'methods',to_jsonb(prim.methods),'holder',prim.holder) end,
   'cards',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'title',g.title,'subtitle',g.subtitle,'image',g.image,'color',g.color,'amounts',to_jsonb(g.amounts),'position',g.position,'active',g.active,'version',g.version,
     'category',p.category_id,'ready',private.member_payment_receiver(p_org,p_unit,g.purpose_id) is not null) order by g.position,g.title)
    from private.giving_cards g join private.finance_purposes p on p.id=g.purpose_id where g.organization_id=p_org and g.unit_id=p_unit),'[]'),
   'categories',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'name',k.name) order by k.name) from private.finance_catalog k
    where k.organization_id=p_org and (k.unit_id=p_unit or k.unit_id is null) and k.kind='category' and k.direction='income' and k.active and k.parent_id is null),'[]'));
 elsif p_action='save' then
  if coalesce(p_data->>'id','') !~ '^[0-9a-f-]{36}$' or length(btrim(coalesce(p_data->>'title',''))) not between 2 and 40 or length(coalesce(p_data->>'subtitle',''))>160
   or coalesce(p_data->>'color','') !~ '^#[0-9a-fA-F]{6}$' or jsonb_typeof(p_data->'amounts')<>'array' or jsonb_typeof(p_data->'active')<>'boolean'
   or (coalesce(p_data->>'image','')<>'' and not private.ministry_public_url(p_data->>'image')) then raise exception 'giving_invalid' using errcode='22023';end if;
  select array_agg(x::int order by x::int) into amts from jsonb_array_elements_text(p_data->'amounts') x;
  amts:=coalesce(amts,'{}');
  if cardinality(amts)>6 or exists(select 1 from unnest(amts) a where a<100 or a>10000000) then raise exception 'giving_invalid' using errcode='22023';end if;
  cat:=nullif(p_data->>'category','')::uuid;
  if cat is null or not private.digital_catalog(p_org,p_unit,cat,'category','income') or exists(select 1 from private.finance_catalog where id=cat and parent_id is not null) then raise exception 'giving_category' using errcode='22023';end if;
  select * into c from private.giving_cards where id=(p_data->>'id')::uuid for update;
  if c.id is not null and (c.organization_id<>p_org or c.unit_id<>p_unit) then raise exception 'giving_denied' using errcode='42501';end if;
  if coalesce(c.version,0)<>coalesce((p_data->>'version')::int,0) then raise exception 'giving_changed' using errcode='40001';end if;
  v_origin:=case when lower(p_data->>'title') like '%d_zimo%' then 'tithe' when lower(p_data->>'title') like '%oferta%' then 'offering' when lower(p_data->>'title') ~ 'campanha|constru|miss' then 'campaign' else 'donation' end;
  if c.id is null then
   if prim.id is null then raise exception 'giving_no_primary' using errcode='22023';end if;
   -- Categorias de taxa, devolução e crédito: as mesmas de uma finalidade já usada pela igreja.
   select * into base from private.finance_purposes where organization_id=p_org and unit_id=p_unit and active order by (finance_purposes.origin<>'event') desc,name limit 1;
   if base.id is null then raise exception 'giving_no_purpose' using errcode='22023';end if;
   pid:=extensions.gen_random_uuid();
   insert into private.finance_purposes(id,organization_id,unit_id,name,origin,account_id,category_id,subcategory_id,center_id,fee_category,refund_category,credit_category,created_by,active)
    values(pid,p_org,p_unit,'Contribua · '||btrim(p_data->>'title'),v_origin,prim.account_id,cat,null,base.center_id,base.fee_category,base.refund_category,base.credit_category,auth.uid(),true);
   insert into private.giving_cards(id,organization_id,unit_id,purpose_id,title,subtitle,image,color,amounts,position,active,created_by)
    values((p_data->>'id')::uuid,p_org,p_unit,pid,btrim(p_data->>'title'),coalesce(p_data->>'subtitle',''),coalesce(p_data->>'image',''),p_data->>'color',amts,
     coalesce((select max(position)+1 from private.giving_cards where organization_id=p_org and unit_id=p_unit),0),(p_data->>'active')::boolean,auth.uid())
    returning version into v;
  else
   update private.finance_purposes set name='Contribua · '||btrim(p_data->>'title'),category_id=cat,subcategory_id=null,
    account_id=case when prim.id is not null then prim.account_id else account_id end,active=true,version=version+1 where id=c.purpose_id;
   update private.giving_cards set title=btrim(p_data->>'title'),subtitle=coalesce(p_data->>'subtitle',''),image=coalesce(p_data->>'image',''),color=p_data->>'color',amounts=amts,
    active=(p_data->>'active')::boolean,version=version+1,updated_at=clock_timestamp() where id=c.id returning version into v;
  end if;
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'giving.card_saved','giving_card',p_data->>'id');
  return jsonb_build_object('ok',true,'version',v);
 elsif p_action='delete' then
  select * into c from private.giving_cards where id=nullif(p_data->>'id','')::uuid and organization_id=p_org and unit_id=p_unit for update;
  if c.id is null then return jsonb_build_object('ok',true);end if;
  delete from private.giving_cards where id=c.id;
  -- A finalidade fica (guarda o histórico das contribuições), só deixa de receber pelo app.
  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id) values(p_org,auth.uid(),'giving.card_deleted','giving_card',c.id::text);
  return jsonb_build_object('ok',true);
 elsif p_action='reorder' then
  if jsonb_typeof(p_data->'ids')<>'array' then raise exception 'giving_invalid' using errcode='22023';end if;
  update private.giving_cards g set position=x.ord-1 from jsonb_array_elements_text(p_data->'ids') with ordinality x(id,ord)
   where g.id=x.id::uuid and g.organization_id=p_org and g.unit_id=p_unit;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'giving_invalid' using errcode='22023';
end $$;
revoke all on function private.giving_admin(uuid,uuid,text,jsonb) from public,anon,authenticated;
create or replace function public.giving_admin(p_org uuid,p_unit uuid,p_action text,p_data jsonb default '{}') returns jsonb
language sql security definer set search_path to '' as $$select private.giving_admin(p_org,p_unit,p_action,p_data)$$;
revoke all on function public.giving_admin(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.giving_admin(uuid,uuid,text,jsonb) to authenticated;
