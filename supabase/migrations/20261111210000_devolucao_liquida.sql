-- Devolução de pagamento online sai pelo LÍQUIDO.
-- Ex.: pagou R$ 10,00, taxa R$ 0,30, entrou R$ 9,70. Na devolução total sai R$ 9,70 (o
-- provedor devolve a taxa). Em devolução parcial, a taxa volta na proporção do valor devolvido
-- (devolver R$ 5,00 de R$ 10,00 tira R$ 4,85). A composição guarda o bruto devolvido e a taxa
-- devolvida. O campo de taxa que o provedor continua informando após o estorno não decide mais
-- o valor da devolução (o Mercado Pago mantém a taxa original no pagamento estornado).

-- Taxa que volta na devolução, acumulada até o total devolvido, menos o que já voltou antes.
create function private.digital_refund_fee_share(p_receipt uuid,p_gross bigint,p_refund_total bigint,p_refund_delta bigint) returns bigint
language sql stable security definer set search_path='' as $$
 with f as (
  select coalesce((select e.fee_cents from private.finance_digital_links l join private.finance_entries e on e.id=l.entry_id where l.receipt_id=p_receipt and l.kind='gross' order by e.created_at limit 1),0) f0,
   coalesce((select -sum(e.fee_cents)::bigint from private.finance_digital_links l join private.finance_entries e on e.id=l.entry_id where l.receipt_id=p_receipt and l.kind='refund' and e.base_cents is not null),0) so_far
 )
 select greatest(0,least(least(f0,round(f0::numeric*least(p_refund_total,p_gross)/greatest(p_gross,1))::bigint)-so_far,p_refund_delta-1)) from f
$$;
revoke all on function private.digital_refund_fee_share(uuid,bigint,bigint,bigint) from public,anon,authenticated,service_role;

-- Taxa que de fato ficou com o provedor (taxa original menos a devolvida nas devoluções).
create function private.digital_fee_kept(p_receipt uuid) returns bigint
language sql stable security definer set search_path='' as $$
 select greatest(0,
  coalesce((select e.fee_cents from private.finance_digital_links l join private.finance_entries e on e.id=l.entry_id where l.receipt_id=p_receipt and l.kind='gross' order by e.created_at limit 1),0)
  +coalesce((select sum(e.fee_cents)::bigint from private.finance_digital_links l join private.finance_entries e on e.id=l.entry_id where l.receipt_id=p_receipt and l.kind='refund' and e.base_cents is not null),0))
$$;
revoke all on function private.digital_fee_kept(uuid) from public,anon,authenticated,service_role;

do $digital$
declare d text;old_block text;new_block text;old_update text;
begin
 d:=pg_get_functiondef('private.digital_apply(uuid)'::regprocedure);
 old_block:=$old$  if r.posted_gross=0 then perform private.digital_post_net(o,r.id,'gross',gross,fee,day);
  else
   if refund>r.posted_refund and fee<r.posted_fee and r.posted_fee-fee<refund-r.posted_refund then returned:=r.posted_fee-fee;end if;
   if refund>r.posted_refund then perform private.digital_post_net(o,r.id,'refund',refund-r.posted_refund,-returned,(r.occurred_at at time zone 'America/Sao_Paulo')::date);end if;
   if fee>r.posted_fee then perform private.digital_post(o,r.id,'fee',fee-r.posted_fee,(r.occurred_at at time zone 'America/Sao_Paulo')::date);
   elsif r.posted_fee-fee>returned then perform private.digital_post(o,r.id,'fee_credit',r.posted_fee-fee-returned,(r.occurred_at at time zone 'America/Sao_Paulo')::date);end if;
  end if;$old$;
 new_block:=$new$  if r.posted_gross=0 then perform private.digital_post_net(o,r.id,'gross',gross,fee,day);
  elsif refund>r.posted_refund then
   returned:=private.digital_refund_fee_share(r.id,gross,refund,refund-r.posted_refund);
   perform private.digital_post_net(o,r.id,'refund',refund-r.posted_refund,-returned,(r.occurred_at at time zone 'America/Sao_Paulo')::date);
  elsif refund=0 and fee>r.posted_fee then perform private.digital_post(o,r.id,'fee',fee-r.posted_fee,(r.occurred_at at time zone 'America/Sao_Paulo')::date);
  elsif refund=0 and fee<r.posted_fee then perform private.digital_post(o,r.id,'fee_credit',r.posted_fee-fee,(r.occurred_at at time zone 'America/Sao_Paulo')::date);
  end if;$new$;
 if (length(d)-length(replace(d,old_block,'')))/length(old_block)<>1 then raise exception 'digital_apply_changed';end if;
 d:=replace(d,old_block,new_block);
 old_update:='set posted_gross=gross,posted_fee=fee,posted_refund=refund,review_reason=null where id=r.id';
 if (length(d)-length(replace(d,old_update,'')))/length(old_update)<>1 then raise exception 'digital_apply_update_changed';end if;
 d:=replace(d,old_update,'set posted_gross=gross,posted_fee=case when refund>0 then private.digital_fee_kept(r.id) else fee end,posted_refund=refund,review_reason=null where id=r.id');
 execute d;
end $digital$;

-- Corrige devoluções já lançadas pelo bruto (sem composição): passam ao líquido, com a taxa
-- devolvida na composição. A mudança de valor fica no histórico do lançamento; o lote contábil
-- acompanha. Devoluções estornadas ou conciliadas não são tocadas.
do $fix$
declare x record;ret bigint;net bigint;
begin
 alter table private.finance_entries disable trigger digital_entry_guard;
 for x in select e.*,l.receipt_id,o.gross order_gross
  from private.finance_digital_links l join private.finance_entries e on e.id=l.entry_id
  join private.finance_digital_receipts r on r.id=l.receipt_id join private.finance_digital_orders o on o.id=r.order_id
  where l.kind='refund' and e.base_cents is null and e.reversal_id is null and e.status='posted'
   and not exists(select 1 from private.finance_reconciliation_book_items b where b.journal_id=e.journal_id and b.active)
  order by l.receipt_id,e.created_at,e.id loop
  ret:=private.digital_refund_fee_share(x.receipt_id,x.order_gross,
   (select coalesce(sum(coalesce(e3.base_cents,e3.amount_cents)),0)::bigint from private.finance_digital_links l3 join private.finance_entries e3 on e3.id=l3.entry_id where l3.receipt_id=x.receipt_id and l3.kind='refund' and (e3.base_cents is not null or e3.id=x.id)),
   x.amount_cents);
  if ret<=0 then continue;end if;
  net:=x.amount_cents-ret;
  update private.finance_entries set amount_cents=net,base_cents=x.amount_cents,fee_cents=-ret where id=x.id;
  update public.church_ledger_lines set delta_cents=case when delta_cents>0 then net else -net end where journal_id=x.journal_id;
  update public.church_ledger_periods set generation=generation+1 where organization_id=x.organization_id and unit_id=x.unit_id;
  update private.finance_digital_receipts set posted_fee=private.digital_fee_kept(x.receipt_id) where id=x.receipt_id;
 end loop;
 alter table private.finance_entries enable trigger digital_entry_guard;
end $fix$;
