-- Additive validation; existing order question snapshots are unchanged.
create or replace function private.event_ticket_questions_valid(d jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare q jsonb;
begin
 if jsonb_typeof(d) is distinct from 'array' or jsonb_array_length(d)>30 then return false;end if;
 for q in select value from jsonb_array_elements(d) loop
  if jsonb_typeof(q) is distinct from 'object' or q-array['id','label','kind','required','options']<>'{}' or not(q ?& array['id','label','kind','required','options']) or jsonb_typeof(q->'label') is distinct from 'string' or length(btrim(q->>'label')) not between 2 and 160 or jsonb_typeof(q->'required') is distinct from 'boolean' or coalesce(q->>'kind','') not in('text','email','date','cpf','phone','number','select','select_other','boolean') or jsonb_typeof(q->'options') is distinct from 'array' or jsonb_array_length(q->'options')>30 then return false;end if;
  if nullif(q->>'id','')::uuid is null then return false;end if;
  if q->>'kind' in('select','select_other') and jsonb_array_length(q->'options')=0 then return false;end if;
  if exists(select 1 from jsonb_array_elements(q->'options')v where jsonb_typeof(v) is distinct from 'string' or length(v#>>'{}') not between 1 and 100) then return false;end if;
  if q->>'kind'='select_other' and exists(select 1 from jsonb_array_elements_text(q->'options')v where v in('Outro','__other__') or v like 'Outro: %') then return false;end if;
 end loop;
 return (select count(distinct v->>'id')=jsonb_array_length(d) from jsonb_array_elements(d)v);
exception when others then return false;end $$;
create or replace function private.event_ticket_answers_valid(d jsonb,questions jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare q jsonb;v text;
begin
 if jsonb_typeof(d) is distinct from 'object' or octet_length(d::text)>24000 or exists(select 1 from jsonb_each(d) a where not exists(select 1 from jsonb_array_elements(questions)question_row where question_row->>'id'=a.key) or jsonb_typeof(a.value) is distinct from 'string') then return false;end if;
 for q in select value from jsonb_array_elements(questions) loop
  v:=btrim(coalesce(d->>(q->>'id'),''));if length(v)>1000 or (q->>'required')::boolean and v='' then return false;end if;
  if v<>'' then
   if q->>'kind'='email' and v!~'^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or q->>'kind'='number' and v!~'^[0-9]{1,12}$' or q->>'kind'='boolean' and v not in('Sim','Não') or q->>'kind'='select' and not(q->'options' ? v) or q->>'kind'='cpf' and not private.event_cpf_valid(v) or q->>'kind'='phone' and length(regexp_replace(v,'[^0-9]','','g')) not between 10 and 13 then return false;end if;
   if q->>'kind'='select_other' and not(q->'options' ? v or left(v,7)='Outro: ' and length(btrim(substr(v,8)))>0) then return false;end if;
   if q->>'kind'='date' then if v!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or v::date is null then return false;end if;end if;
  end if;
 end loop;return true;
exception when others then return false;end $$;
notify pgrst,'reload schema';
