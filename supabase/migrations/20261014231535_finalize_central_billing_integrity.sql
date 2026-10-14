-- Subscription suspension also revokes entry through access_context().
create function private.sync_subscription_organization_status() returns trigger language plpgsql security definer set search_path='' as $$ begin
 update public.organizations set status=(case new.status when 'suspended' then 'suspended' when 'cancelled' then 'cancelled' when 'trialing' then 'trial' else 'active' end)::public.organization_status where id=new.organization_id;
 return new; end $$;
revoke all on function private.sync_subscription_organization_status() from public,anon,authenticated;
create trigger sync_subscription_organization_status after update of status on public.saas_subscriptions for each row execute function private.sync_subscription_organization_status();

-- Invoked only by the backend AFTER authenticating a provider callback. The
-- browser and church/operator JWTs have no EXECUTE privilege on this function.
create function public.apply_saas_billing_event(p_reference uuid,p_provider text,p_event_id text,p_event_type text,p_paid boolean,p_amount_cents bigint,p_payload jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare inv public.saas_invoices; batch public.saas_consolidated_invoices; eid uuid; stamp bigint:=(extract(epoch from now())*1000)::bigint; begin
 select * into inv from public.saas_invoices where id=p_reference for update;
 if inv.id is null then select * into batch from public.saas_consolidated_invoices where id=p_reference for update; end if;
 if inv.id is null and batch.id is null then return jsonb_build_object('ok',true,'ignored',true); end if;
 if coalesce(inv.provider,batch.provider) is distinct from p_provider then raise exception 'provider_mismatch'; end if;
 if p_paid and (p_amount_cents is null or p_amount_cents<>coalesce(inv.amount_cents,batch.amount_cents)) then raise exception 'amount_mismatch'; end if;
 insert into public.saas_billing_events(provider,external_event_id,invoice_id,event_type,payload,processed_at) values(p_provider,p_event_id,inv.id,p_event_type,p_payload,stamp) on conflict(provider,external_event_id) do nothing returning id into eid;
 if eid is null then return jsonb_build_object('ok',true,'duplicate',true); end if;
 if p_paid then
  if inv.id is not null and inv.status='open' then
   update public.saas_invoices set status='paid',paid_at=stamp,updated_at=stamp where id=inv.id;
   update public.saas_subscriptions set status='active',current_period_end=greatest(coalesce(current_period_end,now()),now())+interval '1 month',updated_at=now() where id=inv.subscription_id;
  elsif batch.id is not null and batch.status='open' then
   update public.saas_consolidated_invoices set status='paid',paid_at=stamp,updated_at=stamp where id=batch.id;
   update public.saas_subscriptions set status='active',current_period_end=greatest(coalesce(current_period_end,now()),now())+interval '1 month',updated_at=now() where id in (select i.subscription_id from public.saas_invoices i join public.saas_consolidated_invoice_items x on x.invoice_id=i.id where x.consolidated_invoice_id=batch.id and i.status='open');
   update public.saas_invoices set status='paid',paid_at=stamp,updated_at=stamp where id in(select invoice_id from public.saas_consolidated_invoice_items where consolidated_invoice_id=batch.id) and status='open';
  end if;
 end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.apply_saas_billing_event(uuid,text,text,text,boolean,bigint,jsonb) from public,anon,authenticated;
grant execute on function public.apply_saas_billing_event(uuid,text,text,text,boolean,bigint,jsonb) to service_role;

create policy organizations_select_operator on public.organizations for select to authenticated
using(private.has_aal2() and private.is_platform_operator(array['owner','admin','support','read_only']::public.platform_operator_role[]));
