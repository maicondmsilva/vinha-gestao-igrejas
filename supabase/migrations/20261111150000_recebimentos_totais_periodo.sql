-- Recebimentos digitais: totais do período inteiro, não só dos até 100 pagamentos da página.
-- Mesmos filtros da lista (igreja, produção, período pela criação do pedido) e só valores já
-- lançados (bruto, taxas e devoluções confirmados). A autorização continua na função interna.
create or replace function private.finance_digital(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r jsonb;items jsonb;totals jsonb;begin
 r:=private.finance_digital_before_readable_origin(p_org,p_unit,p_action,p_data);
 if p_action='list' then
  select coalesce(jsonb_agg(x.value||private.finance_order_origin(p_org,p_unit,(x.value->>'id')::uuid) order by x.ordinality),'[]') into items from jsonb_array_elements(r->'items') with ordinality x;
  r:=jsonb_set(r,'{items}',items);
  select jsonb_build_object('gross',coalesce(sum(rec.posted_gross),0)::text,'fees',coalesce(sum(rec.posted_fee),0)::text,'refunds',coalesce(sum(rec.posted_refund),0)::text,
   'net',coalesce(sum(rec.posted_gross-rec.posted_fee-rec.posted_refund),0)::text,'count',count(*),'review',count(*) filter(where rec.review_reason is not null))
  into totals
  from private.finance_digital_orders ord join private.finance_digital_receipts rec on rec.order_id=ord.id
  where ord.organization_id=p_org and ord.unit_id=p_unit and ord.environment='production'
   and (rec.posted_gross>0 or rec.snapshot->>'state' in('approved','partially_refunded','refunded'))
   and (nullif(p_data->>'from','') is null or (ord.created_at at time zone 'America/Sao_Paulo')::date>=(p_data->>'from')::date)
   and (nullif(p_data->>'to','') is null or (ord.created_at at time zone 'America/Sao_Paulo')::date<=(p_data->>'to')::date);
  r:=r||jsonb_build_object('totals',totals);
 end if;return r;
end$$;
revoke all on function private.finance_digital(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.finance_digital(uuid,uuid,text,jsonb) to authenticated;
