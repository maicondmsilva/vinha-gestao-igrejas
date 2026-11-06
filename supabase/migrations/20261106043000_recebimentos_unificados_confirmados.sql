-- A payment is one operational launch. Immutable, dated journal components
-- remain available to cash balances, reconciliation and accounting exports.
do $migration$
declare d text; needle text; replacement text; projection text;
begin
 d:=pg_get_functiondef('private.finance_f1_base(uuid,uuid[],text,jsonb)'::regprocedure);
 projection:=split_part(split_part(d,'with filtered as (',2),'where e.organization_id=p_org',1);
 if position('from private.finance_reporting_entries e' in projection)=0 then raise exception 'finance_projection_changed';end if;
 needle:=$old$), visible as (
   select * from filtered where (case when p_data->>'dateBy'='competence' then competence_date when p_data->>'dateBy'='paid' then paid_date else due_date end) between v_from and v_to
  ), flow as ($old$;
 replacement:=$new$), visible_matches as (
   select * from filtered where (case when p_data->>'dateBy'='competence' then competence_date when p_data->>'dateBy'='paid' then paid_date else due_date end) between v_from and v_to
  ), visible_ids as (
   select distinct coalesce(root.entry_id,f.id) id from visible_matches f
   left join private.finance_digital_links component on component.entry_id=f.id
   left join lateral (select l.entry_id from private.finance_digital_links l join private.finance_entries e on e.id=l.entry_id where l.receipt_id=component.receipt_id and l.kind='gross' and e.organization_id=p_org and e.unit_id=any(p_units) order by e.created_at,e.id limit 1) root on true
  ), visible as ($new$||projection||$new$where e.organization_id=p_org and e.unit_id=any(p_units) and e.id in(select id from visible_ids)
  ), flow as ($new$;
 if position(needle in d)=0 then raise exception 'finance_visible_changed';end if;
 execute replace(d,needle,replacement);
 d:=pg_get_functiondef('private.finance_digital_before_readable_origin(uuid,uuid,text,jsonb)'::regprocedure);
 needle:='where ord.organization_id=p_org and ord.unit_id=p_unit and (nullif(p_data->>''from'','''')';
 replacement:='where ord.organization_id=p_org and ord.unit_id=p_unit and ord.environment=''production'' and (rec.posted_gross>0 or rec.snapshot->>''state'' in (''approved'',''partially_refunded'',''refunded'')) and (nullif(p_data->>''from'','''')';
 if position(needle in d)=0 then raise exception 'digital_list_changed';end if;
 execute replace(d,needle,replacement);
end $migration$;

-- Break down real cash movements without changing totals or their dates.
do $cashflow$
declare d text;
begin
 d:=pg_get_functiondef('private.finance_f1_base(uuid,uuid[],text,jsonb)'::regprocedure);
 if position('center_name from filtered where status=' in d)=0 then raise exception 'finance_flow_changed';end if;
 d:=replace(d,'center_name from filtered where status=','center_name,(select kind from private.finance_digital_links where entry_id=filtered.id) digital_kind from filtered where status=');
 d:=replace(d,'center_name from filtered where reversal_id','center_name,(select kind from private.finance_digital_links where entry_id=filtered.id) from filtered where reversal_id');
 d:=replace(d,'0::numeric receivable,0::numeric payable from flow','0::numeric receivable,0::numeric payable,case when digital_kind=''fee'' then cents when digital_kind=''fee_credit'' then -cents else 0 end digital_fee,case when digital_kind=''refund'' then cents else 0 end digital_refund from flow');
 d:=replace(d,'then amount_cents else 0 end from filtered where status=''pending''','then amount_cents else 0 end,0,0 from filtered where status=''pending''');
 d:=replace(d,'sum(payable)::text payable from monthly_flow','sum(payable)::text payable,sum(digital_fee)::text digital_fee,sum(digital_refund)::text digital_refund from monthly_flow');
 execute d;
end $cashflow$;

alter function private.finance_entry_display(uuid,uuid) rename to finance_entry_display_before_components;
create function private.finance_entry_display(p_org uuid,p_entry uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;r private.finance_digital_receipts;o private.finance_digital_orders;principal bigint;discount bigint;history jsonb;
begin
 result:=private.finance_entry_display_before_components(p_org,p_entry);
 select rec.* into r from private.finance_digital_links l join private.finance_digital_receipts rec on rec.id=l.receipt_id join private.finance_digital_orders ord on ord.id=rec.order_id where l.entry_id=p_entry and ord.organization_id=p_org;
 if not found then return result;end if;
 select * into o from private.finance_digital_orders where id=r.order_id;
 select t.subtotal,t.discount into principal,discount from private.event_ticket_orders t where t.finance_order=o.id and t.organization_id=p_org and t.receiving_unit=o.unit_id;
 select coalesce(jsonb_agg(jsonb_build_object('kind',l.kind,'amount',e.amount_cents::text,'date',e.paid_date) order by e.paid_date,e.created_at,e.id),'[]') into history from private.finance_digital_links l join private.finance_entries e on e.id=l.entry_id where l.receipt_id=r.id and e.organization_id=p_org;
 return result||jsonb_build_object('digital_payment',jsonb_build_object('receipt',r.id,'state',r.snapshot->>'state','principal',coalesce(principal,o.gross)::text,'interest','0','fine','0','discount',coalesce(discount,0)::text,'gross',r.posted_gross::text,'fee',r.posted_fee::text,'refund',r.posted_refund::text,'net',(r.posted_gross-r.posted_fee-r.posted_refund)::text,'history',history));
end $$;
revoke all on function private.finance_entry_display_before_components(uuid,uuid),private.finance_entry_display(uuid,uuid) from public,anon,authenticated,service_role;

alter function private.finance_f6(uuid,uuid[],text,jsonb) rename to finance_f6_before_components;
create function private.finance_f6(p_org uuid,p_units uuid[],p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r jsonb;items jsonb;
begin
 r:=private.finance_f6_before_components(p_org,p_units,p_action,p_data);
 if jsonb_typeof(r->'rows')='array' then
  select coalesce(jsonb_agg(x.value||case when nullif(x.value->>'id','') is not null then private.finance_entry_display(p_org,(x.value->>'id')::uuid) else '{}'::jsonb end order by x.ordinality),'[]') into items from jsonb_array_elements(r->'rows') with ordinality x;
  r:=jsonb_set(r,'{rows}',items);
 end if;
 return r;
end $$;
revoke all on function private.finance_f6(uuid,uuid[],text,jsonb),private.finance_f6_before_components(uuid,uuid[],text,jsonb) from public,anon,authenticated,service_role;
-- The public invoker RPC continues to call the guarded private function.
grant execute on function private.finance_f6(uuid,uuid[],text,jsonb) to authenticated;
