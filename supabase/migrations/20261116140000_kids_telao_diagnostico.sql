-- Telão Kids (Holyrics): passa a usar /request (aguarda a resposta do Holyrics) e guarda o resultado,
-- para a tela "Testar telão" dizer se chegou, se a chave/token não têm permissão ou se o Holyrics está fechado.

alter table private.kids_projector_log add column if not exists status_code integer;
alter table private.kids_projector_log add column if not exists response text;

do $$ declare d text; begin
 d:=pg_get_functiondef('private.kids_projector_send(uuid,uuid,uuid,text,jsonb)'::regprocedure);
 if position('/request/SetAlert' in d)=0 then
  if position('''https://api.holyrics.com.br/send/SetAlert'',p_body,' in d)=0 then raise exception 'kids_projector_send: trecho não encontrado';end if;
  d:=replace(d,'''https://api.holyrics.com.br/send/SetAlert'',p_body,','''https://api.holyrics.com.br/request/SetAlert'',case when (p_body->>''show'')::boolean then jsonb_build_object(''display_ahead'',true)||p_body else p_body end,');
  execute d;
 end if;
end $$;

-- Resultado do último envio (lê a resposta do pg_net enquanto ela existe e guarda no registro).
create or replace function private.kids_projector_last(p_org uuid,p_unit uuid) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare l private.kids_projector_log; code int; body text; err text;
begin
 select * into l from private.kids_projector_log where organization_id=p_org and unit_id=p_unit order by id desc limit 1;
 if l.id is null then return jsonb_build_object('state','none');end if;
 if l.status_code is null and l.request_id is not null and to_regclass('net._http_response') is not null then
  execute 'select status_code,left(content,500),error_msg from net._http_response where id=$1' into code,body,err using l.request_id;
  if code is not null or err is not null then
   update private.kids_projector_log set status_code=coalesce(code,0),response=left(coalesce(body,err),500) where id=l.id;
   l.status_code:=coalesce(code,0);l.response:=left(coalesce(body,err),500);
  end if;
 end if;
 return jsonb_build_object('state',case
   when l.request_id is null then 'not_sent'
   when l.status_code is null then 'waiting'
   when l.status_code=200 and coalesce(l.response,'') ~* '"status"\s*:\s*"ok"' then 'ok'
   when l.status_code in(401,403) or coalesce(l.response,'') ~* 'permiss|unauthor|invalid.*(token|key)|api_key' then 'denied'
   when l.status_code=0 then 'network'
   else 'error' end,
  'code',l.status_code,'response',l.response,'at',l.created_at,'action',l.action);
end $$;
revoke all on function private.kids_projector_last(uuid,uuid) from public,anon,authenticated;

do $$ declare d text; begin
 d:=pg_get_functiondef('private.kids_projector(uuid,uuid,text,jsonb)'::regprocedure);
 if position('kids_projector_last' in d)=0 then
  if position(' elsif p_action=''test'' then' in d)=0 then raise exception 'kids_projector: trecho não encontrado';end if;
  d:=replace(d,' elsif p_action=''test'' then',' elsif p_action=''last'' then
  return private.kids_projector_last(p_org,p_unit);
 elsif p_action=''test'' then');
  execute d;
 end if;
end $$;
