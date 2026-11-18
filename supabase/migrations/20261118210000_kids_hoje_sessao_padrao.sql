-- Kids › Hoje: a sessão mostrada por padrão passa a ser a que importa agora.
-- Antes: a aberta ou, se nenhuma, a de início mais recente — uma sessão vazia criada depois (sem salas)
-- escondia a sessão preparada em Configurar, e a página mostrava 0 salas, 0 presentes e 0 vagas.
-- Agora: 1) aberta; 2) em preparação ainda não terminada e com salas, a mais próxima de começar;
-- 3) as demais não encerradas e ainda não terminadas; 4) a mais recente.
begin;
set local lock_timeout='5s';

create function pg_temp.swap(p regprocedure, a text, b text) returns void language plpgsql as $f$
declare d text:=pg_get_functiondef(p);
begin
 if position(a in d)=0 then raise exception 'trecho não encontrado em %: %', p, left(a,90); end if;
 execute replace(d,a,b);
end $f$;

select pg_temp.swap('private.kids_operations_page(uuid,uuid,uuid,uuid,text,text)',
 $$order by (status='open') desc,starts_at desc limit 1;$$,
 $$order by (status='open') desc,
  (status='draft' and ends_at>now() and exists(select 1 from private.kids_session_rooms g where g.session_id=s.id)) desc,
  (status not in('closed','cancelled') and ends_at>now()) desc,
  case when ends_at>now() then starts_at end asc nulls last,
  starts_at desc limit 1;$$);

-- A página Hoje informa se a sessão abre sozinha (série com abertura automática, 30 min antes do início).
select pg_temp.swap('private.kids_operations_page(uuid,uuid,uuid,uuid,text,text)',
 $$jsonb_build_object('id',id,'name',name,'startsAt',starts_at,'endsAt',ends_at,'status',status,'version',version)$$,
 $$jsonb_build_object('id',id,'name',name,'startsAt',starts_at,'endsAt',ends_at,'status',status,'version',version,
  'autoOpen',coalesce((select ss.auto_open from private.kids_session_series ss where ss.id=series_id),false))$$);
commit;
