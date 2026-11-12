-- Cadastro pelo app: o vínculo de usuário do aplicativo nasce ativo (acesso na hora, sem aprovação).
-- A solicitação de membro continua indo para Pessoas › Perfis pendentes.
-- Reprovação (total ou parcial): aviso na caixa do app e e-mail numa fila com novas tentativas.

do $mig$
declare def text; n int; old_txt text; new_txt text;
begin
 def:=pg_get_functiondef('private.member_self_service(uuid,text,uuid,jsonb)'::regprocedure);
 old_txt:='values(p_org,auth.uid(),p_unit,''member'',''pending'') returning * into m;';
 new_txt:='values(p_org,auth.uid(),p_unit,''member'',''active'') returning * into m;';
 if position(new_txt in def)=0 then
  n:=(length(def)-length(replace(def,old_txt,'')))/length(old_txt);
  if n<>1 then raise exception 'member_self_service: vínculo pendente encontrado % vez(es)',n; end if;
  def:=replace(def,old_txt,new_txt);
 end if;
 -- Com o vínculo ativo, o tipo da solicitação passa a depender do cadastro de membro ainda pendente.
 old_txt:='kind:=case when person.id is null or m.status=''pending'' then ''registration'' else ''update'' end;';
 new_txt:='kind:=case when person.id is null or person.status=''pending'' or m.status=''pending'' then ''registration'' else ''update'' end;';
 if position(new_txt in def)=0 then
  n:=(length(def)-length(replace(def,old_txt,'')))/length(old_txt);
  if n<>1 then raise exception 'member_self_service: tipo da solicitação encontrado % vez(es)',n; end if;
  def:=replace(def,old_txt,new_txt);
 end if;
 execute def;
end $mig$;

-- Quem já se cadastrou pelo app e aguarda análise passa a ter acesso, como os novos.
update public.organization_memberships m set status='active'
where m.status='pending' and m.role='member'
 and exists(select 1 from private.member_profile_requests r where r.organization_id=m.organization_id and r.user_id=m.user_id);

-- Nomes dos campos do cadastro, como aparecem para a pessoa.
create or replace function private.member_profile_field_label(p_field text) returns text
language sql immutable set search_path to '' as $$
 select case p_field when 'full_name' then 'Nome' when 'phone' then 'Celular' when 'birth_date' then 'Data de nascimento'
  when 'gender' then 'Sexo' when 'marital_status' then 'Estado civil' when 'cpf' then 'CPF' when 'postal_code' then 'CEP'
  when 'street' then 'Rua' when 'number' then 'Número' when 'complement' then 'Complemento' when 'district' then 'Bairro'
  when 'city' then 'Cidade' when 'state' then 'UF' else p_field end
$$;

-- Campos não aprovados de uma solicitação analisada.
create or replace function private.member_profile_rejected_fields(p_payload jsonb, p_accepted text[]) returns jsonb
language sql immutable set search_path to '' as $$
 select coalesce(jsonb_agg(private.member_profile_field_label(k) order by o),'[]'::jsonb)
 from (select k, array_position(array['full_name','phone','birth_date','gender','marital_status','cpf','postal_code','street','number','complement','district','city','state'],k) o
  from jsonb_object_keys(coalesce(p_payload,'{}'::jsonb)) k where not k=any(coalesce(p_accepted,'{}'))) x
$$;

create table if not exists private.member_review_emails(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 request_id uuid not null unique,
 user_id uuid not null references auth.users(id) on delete cascade,
 recipient text not null,
 subject text not null,
 items jsonb not null default '[]'::jsonb,
 reason text not null,
 status text not null default 'pending' check (status in ('pending','sent','failed')),
 attempts int not null default 0,
 next_at timestamptz not null default now(),
 last_error text,
 created_at timestamptz not null default now(),
 sent_at timestamptz
);
create index if not exists member_review_emails_due on private.member_review_emails(next_at) where status='pending';
alter table private.member_review_emails enable row level security;
revoke all on private.member_review_emails from public,anon,authenticated,service_role;

-- Ao analisar: se algum campo ficou de fora, entra o e-mail na fila (o aviso no app é lido da própria solicitação).
create or replace function private.member_review_enqueue_email() returns trigger
language plpgsql security definer set search_path to '' as $$
declare v_email text; v_church text; v_items jsonb;
begin
 if new.status not in ('rejected','partial') or old.status is not distinct from new.status then return new; end if;
 v_items:=private.member_profile_rejected_fields(new.payload,new.accepted_fields);
 if jsonb_array_length(v_items)=0 then return new; end if;
 select email into v_email from auth.users where id=new.user_id and deleted_at is null;
 if v_email is null then return new; end if;
 select name into v_church from public.organizations where id=new.organization_id;
 insert into private.member_review_emails(organization_id,request_id,user_id,recipient,subject,items,reason)
 values(new.organization_id,new.id,new.user_id,lower(v_email),'Seu cadastro na '||coalesce(v_church,'igreja')||' precisa de ajuste',v_items,coalesce(new.reason,''))
 on conflict (request_id) do nothing;
 return new;
end $$;
revoke all on function private.member_review_enqueue_email() from public,anon,authenticated,service_role;
drop trigger if exists member_review_enqueue_email on private.member_profile_requests;
create trigger member_review_enqueue_email after update of status on private.member_profile_requests
 for each row execute function private.member_review_enqueue_email();

-- Reserva itens pendentes para envio (o servidor chama, envia e marca o resultado).
create or replace function private.member_review_email_batch(p_limit int) returns setof jsonb
language sql security definer set search_path to '' as $$
 with picked as (
  update private.member_review_emails e set attempts=e.attempts+1, next_at=now()+interval '15 minutes'
  where e.id in (select id from private.member_review_emails where status='pending' and next_at<=now()
   order by next_at limit greatest(1,least(coalesce(p_limit,20),100)) for update skip locked)
  returning e.*)
 select to_jsonb(p)||jsonb_build_object('church',o.name,'slug',o.slug) from picked p join public.organizations o on o.id=p.organization_id
$$;

create or replace function private.member_review_email_mark(p_id uuid, p_ok boolean, p_error text) returns void
language sql security definer set search_path to '' as $$
 update private.member_review_emails set
  status=case when p_ok then 'sent' when attempts>=5 then 'failed' else 'pending' end,
  sent_at=case when p_ok then now() else sent_at end,
  next_at=case when p_ok then next_at else now()+(attempts*interval '10 minutes') end,
  last_error=case when p_ok then null else left(coalesce(p_error,'erro'),300) end
 where id=p_id
$$;

create or replace function public.member_review_email_batch(p_limit int) returns setof jsonb
language sql security invoker set search_path to '' as $$ select * from private.member_review_email_batch(p_limit) $$;
create or replace function public.member_review_email_mark(p_id uuid, p_ok boolean, p_error text) returns void
language sql security invoker set search_path to '' as $$ select private.member_review_email_mark(p_id,p_ok,p_error) $$;

revoke all on function private.member_review_email_batch(int) from public,anon,authenticated;
revoke all on function private.member_review_email_mark(uuid,boolean,text) from public,anon,authenticated;
revoke all on function public.member_review_email_batch(int) from public,anon,authenticated;
revoke all on function public.member_review_email_mark(uuid,boolean,text) from public,anon,authenticated;
grant usage on schema private to service_role;
grant execute on function private.member_review_email_batch(int) to service_role;
grant execute on function private.member_review_email_mark(uuid,boolean,text) to service_role;
grant execute on function public.member_review_email_batch(int) to service_role;
grant execute on function public.member_review_email_mark(uuid,boolean,text) to service_role;
revoke all on function private.member_profile_field_label(text) from public,anon;
revoke all on function private.member_profile_rejected_fields(jsonb,text[]) from public,anon;

-- Caixa de avisos do app: a última análise com campos não aprovados aparece até a pessoa reenviar.
do $mig$
declare def text;
begin
 if to_regprocedure('private.member_inbox_before_profile_review(uuid,uuid)') is null then
  def:=pg_get_functiondef('private.member_inbox_rows(uuid,uuid)'::regprocedure);
  def:=replace(def,'FUNCTION private.member_inbox_rows(','FUNCTION private.member_inbox_before_profile_review(');
  execute def;
  revoke all on function private.member_inbox_before_profile_review(uuid,uuid) from public,anon,authenticated,service_role;
 end if;
end $mig$;

create or replace function private.member_inbox_rows(p_org uuid, p_unit uuid)
returns table(message_key text, title text, body text, occurred_at timestamptz, target text, target_id uuid)
language sql stable security definer set search_path to '' as $$
 select * from (
  select * from private.member_inbox_before_profile_review(p_org,p_unit)
  union all
  select 'profile-review:'||r.id::text,
   'Seu cadastro precisa de ajuste'::text,
   'O que precisa ajustar: '||(select string_agg(x,', ') from jsonb_array_elements_text(private.member_profile_rejected_fields(r.payload,r.accepted_fields)) x)
    ||'. Motivo: '||coalesce(r.reason,'')||'. Toque para corrigir seu cadastro.',
   r.reviewed_at,'profile'::text,r.id
  from private.member_profile_requests r
  where r.organization_id=p_org and r.user_id=auth.uid() and r.status in ('rejected','partial')
   and r.reviewed_at>now()-interval '90 days'
   and jsonb_array_length(private.member_profile_rejected_fields(r.payload,r.accepted_fields))>0
   and not exists(select 1 from private.member_profile_requests n where n.organization_id=r.organization_id and n.user_id=r.user_id and n.created_at>r.created_at)
 ) x order by occurred_at desc nulls last, message_key limit 100
$$;
