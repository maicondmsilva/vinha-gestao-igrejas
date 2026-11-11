-- Configurações › Usuários e permissões: celular do cadastro de membro vinculado na lista.
-- Mesmo critério do nome (pessoa da organização ligada ao login, não recusada).
do $staff$
declare d text;needle text;
begin
 d:=pg_get_functiondef('public.staff_directory(uuid)'::regprocedure);
 needle:='''email'',a.email,';
 if (length(d)-length(replace(d,needle,'')))/length(needle)<>1 then raise exception 'staff_directory_changed';end if;
 d:=replace(d,needle,'''email'',a.email,''phone'',(select person.phone from public.people person where person.organization_id=m.organization_id and person.auth_user_id=m.user_id and person.status<>''rejected'' order by person.created_at limit 1),');
 execute d;
end $staff$;
