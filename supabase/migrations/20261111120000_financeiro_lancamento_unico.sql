-- Etapa E · Um fato, um lançamento.
-- O valor do lançamento é o que de fato entrou ou saiu da conta (líquido). Valor original,
-- juros, multa, desconto e taxa ficam guardados no próprio lançamento, como composição
-- informativa, em centavos exatos:
--   valor = original + juros + multa - desconto - taxa (entrada)
--   valor = original + juros + multa - desconto + taxa (saída)
-- A taxa é o custo para a igreja: negativa quando o provedor devolve a taxa numa devolução.

alter table private.finance_entries
 add column base_cents bigint,
 add column interest_cents bigint not null default 0,
 add column fine_cents bigint not null default 0,
 add column discount_cents bigint not null default 0,
 add column fee_cents bigint not null default 0;
alter table private.finance_entries add constraint finance_entries_composition check (
 (base_cents is null and interest_cents=0 and fine_cents=0 and discount_cents=0 and fee_cents=0)
 or (kind in('income','expense') and base_cents between 1 and 999999999999
  and interest_cents between 0 and 999999999999 and fine_cents between 0 and 999999999999
  and discount_cents between 0 and base_cents and fee_cents between -999999999999 and 999999999999
  and amount_cents=base_cents+interest_cents+fine_cents-discount_cents+case when kind='income' then -fee_cents else fee_cents end)
);

-- Lançamentos do provedor continuam imutáveis. A única alteração aceita é preencher a
-- composição uma vez, sem mudar nenhum outro campo (a restrição acima confere os valores).
create or replace function private.digital_entry_guard() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='UPDATE' and old.base_cents is null and new.base_cents is not null
  and (to_jsonb(old)-'base_cents'-'interest_cents'-'fine_cents'-'discount_cents'-'fee_cents')=(to_jsonb(new)-'base_cents'-'interest_cents'-'fine_cents'-'discount_cents'-'fee_cents') then return new;end if;
 if exists(select 1 from private.finance_digital_links where entry_id=old.id) then raise exception 'digital_adjustment_required' using errcode='42501';end if;return case when tg_op='DELETE' then old else new end;
end $$;
revoke all on function private.digital_entry_guard() from public,anon,authenticated,service_role;

-- Recebimento ou devolução do provedor em um único lançamento líquido, com a taxa informada.
create function private.digital_post_net(p_order private.finance_digital_orders,p_receipt uuid,p_kind text,p_base bigint,p_fee bigint,p_date date) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_net bigint;
begin
 if p_kind not in('gross','refund') or p_base is null or p_fee is null then raise exception 'invalid_digital_amount' using errcode='22023';end if;
 v_net:=p_base+case when p_kind='gross' then -p_fee else p_fee end;
 v_id:=private.digital_post(p_order,p_receipt,p_kind,v_net,p_date);
 update private.finance_entries set base_cents=p_base,fee_cents=p_fee where id=v_id;
 return v_id;
end $$;
revoke all on function private.digital_post_net(private.finance_digital_orders,uuid,text,bigint,bigint,date) from public,anon,authenticated,service_role;

-- Aplicação do recebimento: 1 lançamento líquido no recebimento e 1 na devolução.
-- Só ajustes de taxa informados depois, sem devolução, geram um lançamento próprio.
do $digital$
declare d text;old_block text;new_block text;
begin
 d:=pg_get_functiondef('private.digital_apply(uuid)'::regprocedure);
 old_block:=$old$  if r.posted_gross=0 then perform private.digital_post(o,r.id,'gross',gross,day);end if;
  if fee>r.posted_fee then perform private.digital_post(o,r.id,'fee',fee-r.posted_fee,case when r.posted_gross=0 then day else (r.occurred_at at time zone 'America/Sao_Paulo')::date end);
  elsif fee<r.posted_fee then perform private.digital_post(o,r.id,'fee_credit',r.posted_fee-fee,(r.occurred_at at time zone 'America/Sao_Paulo')::date);end if;
  if refund>r.posted_refund then perform private.digital_post(o,r.id,'refund',refund-r.posted_refund,(r.occurred_at at time zone 'America/Sao_Paulo')::date);end if;$old$;
 new_block:=$new$  if r.posted_gross=0 then perform private.digital_post_net(o,r.id,'gross',gross,fee,day);
  else
   if refund>r.posted_refund and fee<r.posted_fee and r.posted_fee-fee<refund-r.posted_refund then returned:=r.posted_fee-fee;end if;
   if refund>r.posted_refund then perform private.digital_post_net(o,r.id,'refund',refund-r.posted_refund,-returned,(r.occurred_at at time zone 'America/Sao_Paulo')::date);end if;
   if fee>r.posted_fee then perform private.digital_post(o,r.id,'fee',fee-r.posted_fee,(r.occurred_at at time zone 'America/Sao_Paulo')::date);
   elsif r.posted_fee-fee>returned then perform private.digital_post(o,r.id,'fee_credit',r.posted_fee-fee-returned,(r.occurred_at at time zone 'America/Sao_Paulo')::date);end if;
  end if;$new$;
 if (length(d)-length(replace(d,old_block,'')))/length(old_block)<>1 then raise exception 'digital_apply_changed';end if;
 d:=replace(d,old_block,new_block);
 if position('declare r private.finance_digital_receipts;' in d)=0 then raise exception 'digital_apply_declare_changed';end if;
 d:=replace(d,'declare r private.finance_digital_receipts;','declare returned bigint:=0;r private.finance_digital_receipts;');
 execute d;
end $digital$;

-- Baixa de contas a receber/pagar: 1 lançamento com o valor que movimentou a conta.
do $settle$
declare d text;needle text;
begin
 d:=pg_get_functiondef('private.finance_f2_base(uuid,uuid,text,jsonb)'::regprocedure);
 needle:=$old$payload:=jsonb_build_object('id',cash,'kind',ent.kind,'amountCents',gross::text,$old$;
 if (length(d)-length(replace(d,needle,'')))/length(needle)<>1 then raise exception 'finance_settle_payload_changed';end if;
 d:=replace(d,needle,$new$payload:=jsonb_build_object('id',cash,'kind',ent.kind,'amountCents',(gross+case when ent.kind='income' then -fee else fee end)::text,$new$);
 needle:=$old$    if fee>0 then
     fee_entry:=extensions.gen_random_uuid();
     perform private.finance_f1_base(p_org,array[p_unit],'entry',payload||jsonb_build_object('id',fee_entry,'kind','expense','amountCents',fee::text,'description',left(ent.description,270)||' · taxa','category',p_data->>'feeCategory'));
    end if;
$old$;
 if (length(d)-length(replace(d,needle,'')))/length(needle)<>1 then raise exception 'finance_settle_fee_changed';end if;
 d:=replace(d,needle,$new$    update private.finance_entries set base_cents=principal,interest_cents=interest,fine_cents=fine,discount_cents=discount,fee_cents=fee where id=cash;
$new$);
 needle:=$old$'gross',e.amount_cents::text,$old$;
 if (length(d)-length(replace(d,needle,'')))/length(needle)<>1 then raise exception 'finance_settle_history_changed';end if;
 d:=replace(d,needle,$new$'gross',(s.principal_cents+s.interest_cents+s.fine_cents-s.discount_cents)::text,'net',e.amount_cents::text,$new$);
 execute d;
end $settle$;

-- Composição disponível na lista, no detalhe e nos relatórios de qualquer lançamento.
alter function private.finance_entry_display(uuid,uuid) rename to finance_entry_display_before_composition;
create function private.finance_entry_display(p_org uuid,p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;e private.finance_entries;
begin
 result:=private.finance_entry_display_before_composition(p_org,p_entry);
 select * into e from private.finance_entries where id=p_entry and organization_id=p_org;
 if not found or e.base_cents is null then return result;end if;
 return result||jsonb_build_object('composition',jsonb_build_object('base',e.base_cents::text,'interest',e.interest_cents::text,'fine',e.fine_cents::text,'discount',e.discount_cents::text,'fee',e.fee_cents::text,'net',e.amount_cents::text));
end $$;
revoke all on function private.finance_entry_display_before_composition(uuid,uuid),private.finance_entry_display(uuid,uuid) from public,anon,authenticated,service_role;

-- Junta cada recebimento online já lançado com a taxa do mesmo dia num único lançamento
-- líquido. O saldo da conta não muda (bruto - taxa = líquido). A alteração do valor fica no
-- histórico do lançamento; o lançamento da taxa e o seu lote contábil deixam de existir.
-- Lançamentos estornados ou já conciliados não são tocados.
do $merge$
declare g record;f record;net bigint;
begin
 alter table private.finance_entries disable trigger digital_entry_guard;
 alter table private.finance_entry_history disable trigger finance_history_immutable;
 for g in select e.*,l.receipt_id from private.finance_digital_links l join private.finance_entries e on e.id=l.entry_id
  where l.kind='gross' and e.base_cents is null and e.reversal_id is null and e.status='posted' order by e.created_at,e.id loop
  select e.* into f from private.finance_digital_links l join private.finance_entries e on e.id=l.entry_id
   where l.receipt_id=g.receipt_id and l.kind='fee' and e.reversal_id is null and e.status='posted' and e.unit_id=g.unit_id
    and e.account_id=g.account_id and e.paid_date=g.paid_date and e.amount_cents<g.amount_cents
    and not exists(select 1 from private.finance_reconciliation_book_items b where b.journal_id in(e.journal_id,g.journal_id) and b.active)
    and not exists(select 1 from private.finance_ofx_entries o where o.entry_id=e.id)
   order by e.created_at,e.id limit 1;
  if not found then continue;end if;
  net:=g.amount_cents-f.amount_cents;
  update private.finance_entries set amount_cents=net,base_cents=g.amount_cents,fee_cents=f.amount_cents where id=g.id;
  update public.church_ledger_lines set delta_cents=case when delta_cents>0 then net else -net end where journal_id=g.journal_id;
  delete from private.finance_digital_links where entry_id=f.id;
  delete from private.finance_record_numbers where entry_id=f.id;
  delete from private.finance_entry_history where entry_id=f.id;
  delete from private.finance_entry_annotations where entry_id=f.id;
  delete from private.finance_entries where id=f.id;
  delete from public.church_ledger_lines where journal_id=f.journal_id;
  delete from public.church_ledger_journals where id=f.journal_id;
  update public.church_ledger_periods set generation=generation+1 where organization_id=g.organization_id and unit_id=g.unit_id;
 end loop;
 alter table private.finance_entry_history enable trigger finance_history_immutable;
 alter table private.finance_entries enable trigger digital_entry_guard;
end $merge$;

-- Visão mensal: o total de taxas dos pagamentos online soma a taxa informada no lançamento
-- (valor já líquido) e os ajustes de taxa lançados à parte.
do $flow$
declare d text;needle text;
begin
 d:=pg_get_functiondef('private.finance_f1_base(uuid,uuid[],text,jsonb)'::regprocedure);
 needle:=$old$(select kind from private.finance_digital_links where entry_id=filtered.id) digital_kind from filtered where status='posted'$old$;
 if (length(d)-length(replace(d,needle,'')))/length(needle)<>1 then raise exception 'finance_flow_posted_changed';end if;
 d:=replace(d,needle,$new$(select kind from private.finance_digital_links where entry_id=filtered.id) digital_kind,(select fee_cents from private.finance_entries where id=filtered.id)::numeric entry_fee from filtered where status='posted'$new$);
 needle:=$old$(select kind from private.finance_digital_links where entry_id=filtered.id) from filtered where reversal_id$old$;
 if (length(d)-length(replace(d,needle,'')))/length(needle)<>1 then raise exception 'finance_flow_reversed_changed';end if;
 d:=replace(d,needle,$new$(select kind from private.finance_digital_links where entry_id=filtered.id),-(select fee_cents from private.finance_entries where id=filtered.id)::numeric from filtered where reversal_id$new$);
 needle:=$old$case when digital_kind='fee' then cents when digital_kind='fee_credit' then -cents else 0 end digital_fee$old$;
 if (length(d)-length(replace(d,needle,'')))/length(needle)<>1 then raise exception 'finance_flow_fee_changed';end if;
 d:=replace(d,needle,$new$case when digital_kind='fee' then cents when digital_kind='fee_credit' then -cents when digital_kind is not null then entry_fee else 0 end digital_fee$new$);
 execute d;
end $flow$;
