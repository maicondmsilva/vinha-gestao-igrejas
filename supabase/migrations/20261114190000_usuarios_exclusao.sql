-- Usuários: ao excluir um usuário no painel, a conta de acesso também é encerrada quando ele não tem
-- mais nenhum acesso ativo (em nenhuma igreja) e não é da equipe da plataforma. O cadastro de membro
-- (people) continua, com seus lançamentos e histórico; só perde o vínculo com a conta antiga.
-- Assim, se a pessoa se cadastrar de novo no app, uma conta nova é criada.

alter table private.account_closures drop constraint if exists account_closures_requested_via_check;
alter table private.account_closures add constraint account_closures_requested_via_check check (requested_via in ('app','web','panel'));

create or replace function private.account_erasable(p_user uuid) returns boolean
language sql stable security definer set search_path to '' as $$
 select p_user is not null
  and exists(select 1 from auth.users where id=p_user and deleted_at is null)
  and not exists(select 1 from public.platform_operators where user_id=p_user and active)
  and not exists(select 1 from public.organization_memberships where user_id=p_user and status='active')
$$;
revoke all on function private.account_erasable(uuid) from public,anon,authenticated;

do $$
declare d text; n int; a text; b text;
begin
 d:=pg_get_functiondef('private.staff_user'::regproc);
 if position('staff_user_erase' in d)=0 then
  a:=$a$  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,auth.uid(),'staff.user.removed','organization_membership',m.id::text,jsonb_build_object('role',m.role));
  return jsonb_build_object('ok',true);$a$;
  b:=$b$  insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
   values(p_org,auth.uid(),'staff.user.removed','organization_membership',m.id::text,jsonb_build_object('role',m.role));
  -- staff_user_erase: sem nenhum outro acesso ativo, a conta de login é encerrada (o cadastro de membro fica).
  if private.account_erasable(m.user_id) then
   update public.people set auth_user_id=null,updated_at=clock_timestamp() where auth_user_id=m.user_id;
   update private.member_push_devices set enabled=false,updated_at=clock_timestamp() where user_id=m.user_id and enabled;
   insert into private.account_closures(user_id,organizations,requested_via)
    values(m.user_id,(select coalesce(array_agg(distinct organization_id),'{}') from public.organization_memberships where user_id=m.user_id),'panel')
    on conflict(user_id) do nothing;
   insert into public.audit_logs(organization_id,actor_user_id,action,entity_type,entity_id,metadata)
    values(p_org,auth.uid(),'staff.user.account_closed','organization_membership',m.id::text,'{}'::jsonb);
   return jsonb_build_object('ok',true,'user',m.user_id,'erase',true);
  end if;
  return jsonb_build_object('ok',true,'user',m.user_id,'erase',false);$b$;
  n:=(length(d)-length(replace(d,a,'')))/length(a);
  if n<>1 then raise exception 'staff_user: trecho da remoção não encontrado (%)',n;end if;
  execute replace(d,a,b);
 end if;
end $$;
