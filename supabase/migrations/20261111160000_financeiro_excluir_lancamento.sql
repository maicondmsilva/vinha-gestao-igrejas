-- Excluir lançamento, sem pedir motivo, para quem já pode estornar (church_ledger_allowed).
-- Só quando o lançamento não veio do provedor, não tem baixa, não foi estornado, não está
-- conciliado, não veio do extrato e não está em mês fechado. O lançamento sai da lista, dos
-- relatórios e do saldo (o lote contábil é removido). Uma cópia completa fica na auditoria.

-- O histórico continua imutável; a única remoção aceita é a do lançamento sendo excluído agora,
-- dentro da função abaixo (o marcador vale só para a transação).
create or replace function private.finance_history_immutable() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' and tg_table_name='finance_entry_history'
  and nullif(current_setting('vinha.finance_entry_delete',true),'') is not null
  and to_jsonb(old)->>'entry_id'=current_setting('vinha.finance_entry_delete',true) then return old;end if;
 raise exception 'finance_history_immutable' using errcode='42501';
end $$;
revoke all on function private.finance_history_immutable() from public,anon,authenticated,service_role;

create function private.finance_delete_entry(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare ent private.finance_entries;v_id uuid;
begin
 perform private.require_confirmed_self_service_email();
 if (p_data-array['id','version'])<>'{}'::jsonb then raise exception 'invalid_action' using errcode='22023';end if;
 v_id:=(p_data->>'id')::uuid;
 if v_id is null or not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 perform 1 from public.organization_units where id=p_unit and organization_id=p_org for update;
 select * into ent from private.finance_entries where id=v_id and organization_id=p_org and unit_id=p_unit for update;
 if not found then raise exception 'entry_not_found' using errcode='42501';end if;
 if ent.version is distinct from (p_data->>'version')::integer then raise exception 'entry_changed' using errcode='40001';end if;
 if exists(select 1 from private.finance_digital_links where entry_id=v_id) then raise exception 'digital_adjustment_required' using errcode='22023';end if;
 if exists(select 1 from private.finance_settlements where title_id=v_id or cash_entry=v_id or fee_entry=v_id) then raise exception 'use_settlement_reversal_first' using errcode='22023';end if;
 if ent.reversal_id is not null then raise exception 'entry_already_reversed' using errcode='22023';end if;
 if exists(select 1 from private.finance_ofx_entries where entry_id=v_id) then raise exception 'entry_from_statement' using errcode='22023';end if;
 if ent.journal_id is not null and exists(select 1 from private.finance_reconciliation_book_items b where b.journal_id=ent.journal_id and b.active) then raise exception 'undo_reconciliation_first' using errcode='22023';end if;
 if ent.status='posted' and exists(select 1 from public.church_ledger_periods where organization_id=p_org and unit_id=p_unit and closed_through>=ent.paid_date) then raise exception 'period_closed' using errcode='22023';end if;

 insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
 values(p_org,auth.uid(),'finance.entry_deleted','finance_entry',v_id::text,jsonb_build_object('unit_id',p_unit,'entry',to_jsonb(ent),
  'history',(select coalesce(jsonb_agg(to_jsonb(h) order by h.id),'[]') from private.finance_entry_history h where h.entry_id=v_id),
  'lines',(select coalesce(jsonb_agg(to_jsonb(l)),'[]') from public.church_ledger_lines l where l.journal_id=ent.journal_id)));

 perform set_config('vinha.finance_entry_delete',v_id::text,true);
 delete from private.finance_entry_history where entry_id=v_id;
 perform set_config('vinha.finance_entry_delete','',true);
 delete from private.finance_entry_annotations where entry_id=v_id;
 delete from private.finance_record_numbers where entry_id=v_id;
 delete from private.finance_series_items where entry_id=v_id;
 delete from private.finance_entries where id=v_id;
 if ent.journal_id is not null then
  insert into public.church_ledger_periods(organization_id,unit_id) values(p_org,p_unit) on conflict do nothing;
  update public.church_ledger_periods set generation=generation+1 where organization_id=p_org and unit_id=p_unit;
  delete from public.church_ledger_lines where journal_id=ent.journal_id;
  delete from public.church_ledger_journals where id=ent.journal_id;
 end if;
 return jsonb_build_object('id',v_id,'ok',true,'deleted',true);
end $$;
revoke all on function private.finance_delete_entry(uuid,uuid,jsonb) from public,anon,authenticated,service_role;

-- Entrada pela mesma RPC do F1 (uma igreja por vez, como o estorno).
create or replace function private.finance_f1(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r jsonb;items jsonb;begin
 if p_action='delete' then
  if cardinality(p_units) is distinct from 1 then raise exception 'select_one_unit' using errcode='22023';end if;
  return private.finance_delete_entry(p_org,p_units[1],p_data);
 end if;
 r:=private.finance_f1_before_readable_origin(p_org,p_units,p_action,p_data);
 if p_action='snapshot' then
  select coalesce(jsonb_agg(x.value||private.finance_entry_display(p_org,(x.value->>'id')::uuid) order by x.ordinality),'[]') into items from jsonb_array_elements(r->'entries') with ordinality x;
  r:=jsonb_set(r,'{entries}',items);
 end if;return r;
end$$;
