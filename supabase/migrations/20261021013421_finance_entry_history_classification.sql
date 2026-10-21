set local lock_timeout='5s';
create table private.finance_entry_history (
 id bigint generated always as identity primary key,
 entry_id uuid not null,organization_id uuid not null,unit_id uuid not null,
 actor_id uuid,actor_name text not null,event text not null,changes jsonb not null,
 happened_at timestamptz not null default clock_timestamp(),recorded_at timestamptz not null default clock_timestamp(),
 foreign key(entry_id,organization_id,unit_id) references private.finance_entries(id,organization_id,unit_id)
);
create index finance_entry_history_entry on private.finance_entry_history(entry_id,organization_id,unit_id,id desc);
alter table private.finance_entry_history enable row level security;
create policy finance_entry_history_deny on private.finance_entry_history as restrictive for all using(false) with check(false);
revoke all on private.finance_entry_history from public,anon,authenticated,service_role;
revoke all on sequence private.finance_entry_history_id_seq from public,anon,authenticated,service_role;
create function private.finance_history_immutable() returns trigger language plpgsql set search_path='' as $$begin raise exception 'finance_history_immutable' using errcode='42501';end $$;
revoke all on function private.finance_history_immutable() from public,anon,authenticated,service_role;
create trigger finance_history_immutable before update or delete on private.finance_entry_history for each row execute function private.finance_history_immutable();
create function private.finance_capture_history() returns trigger language plpgsql security definer set search_path='' as $$
declare before_row jsonb;after_row jsonb;delta jsonb;actor text;
begin
 before_row:=case when tg_op='INSERT' then '{}'::jsonb else to_jsonb(old) end;
 after_row:=to_jsonb(new);
 select coalesce(jsonb_object_agg(k,jsonb_build_object('before',before_row->k,'after',after_row->k)),'{}') into delta
 from unnest(array['kind','amount_cents','description','account_id','destination_id','category_id','center_id','supplier_id','person_id','party_name','method','notes','competence_date','due_date','paid_date','status','journal_id','reversal_id','reversed_date','version']) k
 where before_row->k is distinct from after_row->k;
 if delta='{}' then return new;end if;
 select left(coalesce(nullif(btrim(full_name),''),'Operador identificado'),160) into actor from public.profiles where id=auth.uid();
 insert into private.finance_entry_history(entry_id,organization_id,unit_id,actor_id,actor_name,event,changes)
 values(new.id,new.organization_id,new.unit_id,auth.uid(),coalesce(actor,'Operação interna identificada'),case when tg_op='INSERT' then 'created' else 'changed' end,delta);
 return new;
end $$;
revoke all on function private.finance_capture_history() from public,anon,authenticated,service_role;
create trigger finance_capture_history after insert or update on private.finance_entries for each row execute function private.finance_capture_history();
create function private.finance_capture_settlement_history() returns trigger language plpgsql security definer set search_path='' as $$
declare delta jsonb;actor text;before_row jsonb;after_row jsonb;
begin
 before_row:=case when tg_op='INSERT' then '{}'::jsonb else to_jsonb(old) end;after_row:=to_jsonb(new);
 select coalesce(jsonb_object_agg(k,jsonb_build_object('before',before_row->k,'after',after_row->k)),'{}') into delta
 from unnest(array['principal_cents','interest_cents','fine_cents','discount_cents','fee_cents','cash_entry','fee_entry','reversed_at','reason']) k where before_row->k is distinct from after_row->k;
 select left(coalesce(nullif(btrim(full_name),''),'Operador identificado'),160) into actor from public.profiles where id=auth.uid();
 insert into private.finance_entry_history(entry_id,organization_id,unit_id,actor_id,actor_name,event,changes)
 values(new.title_id,new.organization_id,new.unit_id,auth.uid(),coalesce(actor,'Operação interna identificada'),case when tg_op='INSERT' then 'settlement' else 'settlement_reversed' end,delta);
 return new;
end $$;
revoke all on function private.finance_capture_settlement_history() from public,anon,authenticated,service_role;
create trigger finance_capture_settlement_history after insert or update on private.finance_settlements for each row execute function private.finance_capture_settlement_history();
-- Existing records retain the known creator; unknown past edits are not fabricated.
insert into private.finance_entry_history(entry_id,organization_id,unit_id,actor_id,actor_name,event,changes,happened_at)
select e.id,e.organization_id,e.unit_id,e.created_by,left(coalesce(nullif(btrim(p.full_name),''),'Criador identificado'),160),'baseline',jsonb_build_object('description',jsonb_build_object('before',null,'after',e.description)),e.created_at
from private.finance_entries e left join public.profiles p on p.id=e.created_by;
create function private.finance_activity(p_org uuid,p_unit uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare ent private.finance_entries;cursor_id bigint;items jsonb;has_more boolean;next_cursor text;
begin
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 perform 1 from public.organizations where id=p_org for share;
 perform private.require_confirmed_self_service_email();
 if not private.church_ledger_allowed(p_org,p_unit) then raise exception 'finance_access_denied' using errcode='42501';end if;
 cursor_id:=nullif(p_data->>'before','')::bigint;
 if cursor_id is not null and cursor_id<=0 then raise exception 'invalid_cursor' using errcode='22023';end if;
 select * into ent from private.finance_entries where organization_id=p_org and unit_id=p_unit and id=(p_data->>'title')::uuid;
 if not found then raise exception 'entry_not_found' using errcode='42501';end if;
 with page as(select * from private.finance_entry_history where entry_id=ent.id and (cursor_id is null or id<cursor_id) order by id desc limit 101),shown as(select * from page order by id desc limit 100)
 select coalesce((select jsonb_agg(jsonb_build_object('id',id::text,'actorId',actor_id,'actor',actor_name,'event',event,'changes',changes,'at',happened_at,'recordedAt',recorded_at) order by id desc)from shown),'[]'),(select count(*)>100 from page),(select min(id)::text from shown) into items,has_more,next_cursor;
 return jsonb_build_object('items',items,'hasMore',has_more,'next',next_cursor);
end $$;
revoke all on function private.finance_activity(uuid,uuid,jsonb) from public,anon,authenticated,service_role;
alter function private.finance_f2(uuid,uuid,text,jsonb) rename to finance_f2_base;
revoke all on function private.finance_f2_base(uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;
create function private.finance_f2(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_action='activity' then return private.finance_activity(p_org,p_unit,p_data);end if;
 return private.finance_f2_base(p_org,p_unit,p_action,p_data);
end $$;
revoke all on function private.finance_f2(uuid,uuid,text,jsonb) from public,anon,service_role;
grant execute on function private.finance_f2(uuid,uuid,text,jsonb) to authenticated;
create or replace function public.finance_f2(p_org uuid,p_unit uuid,p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.finance_f2(p_org,p_unit,p_action,p_data)$$;
-- The stored leaf category remains the canonical accounting identity. A principal
-- category filter now includes its children, while subcategory is an exact filter.
do $$declare src text;begin
 src:=pg_get_functiondef('private.finance_f1_base(uuid,uuid[],text,jsonb)'::regprocedure);
 if strpos(src,'e.category_id=(p_data->>''category'')::uuid')=0 then raise exception 'unexpected_category_filter';end if;
 src:=replace(src,'e.category_id=(p_data->>''category'')::uuid)','(e.category_id=(p_data->>''category'')::uuid or c.parent_id=(p_data->>''category'')::uuid))');
 src:=replace(src,'and (nullif(p_data->>''center'','''') is null','and (nullif(p_data->>''subcategory'','''') is null or e.category_id=(p_data->>''subcategory'')::uuid) and (nullif(p_data->>''center'','''') is null');
 execute src;
end $$;
