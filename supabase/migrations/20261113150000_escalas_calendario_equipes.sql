-- Escalas · calendário com cores por equipe: a lista do planejamento passa a trazer as equipes de cada culto.
do $mig$
declare def text; n int; needle text:='private.scale_service_allowed(p_org,p_unit,s.id,''manage'') "canManage"';
begin
 def:=pg_get_functiondef('private.scale_planning_before_permissions(uuid,uuid,text,jsonb)'::regprocedure);
 if position('as_teams_by_service' in def)>0 then return; end if;
 n:=(length(def)-length(replace(def,needle,'')))/length(needle);
 if n<>1 then raise exception 'scale_planning: trecho esperado % vez(es)',n; end if;
 def:=replace(def,needle,needle||',(select coalesce(jsonb_agg(jsonb_build_object(''id'',t.id,''name'',t.name) order by t.name),''[]'') /* as_teams_by_service */ from private.scale_teams t where exists(select 1 from private.scale_positions q where q.service_id=s.id and q.team_id=t.id)) teams');
 execute def;
end $mig$;
