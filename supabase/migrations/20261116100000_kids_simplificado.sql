-- Kids simplificado
-- 1. App da igreja: o responsável adiciona outro responsável fixo (days=0) além do temporário (1 a 30 dias).
-- 2. Sessão = repetição com salas e responsáveis por sala (rooms[].staff = ids da equipe do Kids).
--    Ao salvar, as próximas sessões ainda sem lançamentos são recriadas com as salas e a equipe novas.
-- 3. Recepção: a criança cadastrada pelo app aparece com o selo "a conferir" (não bloqueia a entrada).

do $$ declare d text; begin
 d:=pg_get_functiondef('private.member_kids_temporary(uuid,text,jsonb)'::regprocedure);
 if position('kids_fixed_guardian' in d)=0 then
  if position('if days not between 1 and 30 then' in d)=0
   or position('true,false,false,''approved'',uid,clock_timestamp(),current_date+days-1,uid,true,me.id)' in d)=0
   or position('''Responsável temporário'',''Autorizado por ''||me.full_name||'' pelo app''' in d)=0
   or position('can_edit=false,relationship=''Responsável temporário'',' in d)=0
   or position('valid_until=excluded.valid_until,temporary=true,' in d)=0
   or position('where id=nullif(p_data->>''id'','''')::uuid and profile_id=k.id and temporary;' in d)=0
   or position('return jsonb_build_object(''ok'',true,''name'',split_part(target.full_name,'' '',1),''until'',current_date+days-1);' in d)=0
  then raise exception 'member_kids_temporary: trechos não encontrados';end if;
  d:=replace(d,'if days not between 1 and 30 then','if days not between 0 and 30 /* kids_fixed_guardian: 0 = responsável fixo */ then');
  d:=replace(d,'''Responsável temporário'',''Autorizado por ''||me.full_name||'' pelo app''',
   'case when days=0 then ''Responsável (a conferir)'' else ''Responsável temporário'' end,''Autorizado por ''||me.full_name||'' pelo app''');
  d:=replace(d,'true,false,false,''approved'',uid,clock_timestamp(),current_date+days-1,uid,true,me.id)',
   'true,false,false,''approved'',uid,clock_timestamp(),case when days=0 then null else current_date+days-1 end,uid,days>0,me.id)');
  d:=replace(d,'can_edit=false,relationship=''Responsável temporário'',','can_edit=false,relationship=excluded.relationship,');
  d:=replace(d,'valid_until=excluded.valid_until,temporary=true,','valid_until=excluded.valid_until,temporary=excluded.temporary,');
  -- Quem adicionou pelo app também pode retirar (nunca a si mesmo nem o vínculo conferido pela secretaria).
  d:=replace(d,'where id=nullif(p_data->>''id'','''')::uuid and profile_id=k.id and temporary;',
   'where id=nullif(p_data->>''id'','''')::uuid and profile_id=k.id and person_id<>me.id and (temporary or granted_by is not null);');
  d:=replace(d,'return jsonb_build_object(''ok'',true,''name'',split_part(target.full_name,'' '',1),''until'',current_date+days-1);',
   'return jsonb_build_object(''ok'',true,''name'',split_part(target.full_name,'' '',1),''until'',case when days=0 then null else current_date+days-1 end,''fixed'',days=0);');
  execute d;
 end if;
end $$;

-- A lista mostra quem pode ser retirado pelo responsável.
do $$ declare d text; begin
 d:=pg_get_functiondef('private.member_kids_temporary(uuid,text,jsonb)'::regprocedure);
 if position('''removable''' in d)=0 then
  if position('''canPickup'',x.can_pickup,''me'',p.id=me.id)' in d)=0 then raise exception 'member_kids_temporary: lista não encontrada';end if;
  d:=replace(d,'''canPickup'',x.can_pickup,''me'',p.id=me.id)','''canPickup'',x.can_pickup,''me'',p.id=me.id,''removable'',p.id<>me.id and (x.temporary or x.granted_by is not null))');
  execute d;
 end if;
end $$;

-- Escala por sala na geração das sessões.
do $$ declare d text; begin
 d:=pg_get_functiondef('private.kids_series_run(uuid)'::regprocedure);
 if position('kids_room_staff' in d)=0 then
  if position('     on conflict do nothing;
   end loop;' in d)=0 then raise exception 'kids_series_run: trecho não encontrado';end if;
  d:=replace(d,'     on conflict do nothing;
   end loop;','     on conflict do nothing;
    -- kids_room_staff: responsáveis escolhidos para esta sala na sessão.
    if jsonb_typeof(rm->''staff'')=''array'' then
     for t in select k.* from private.kids_team k where k.unit_id=s.unit_id and k.active and k.id::text in(select jsonb_array_elements_text(rm->''staff'')) loop
      continue when exists(select 1 from private.kids_team_unavailable u where u.team_id=t.id and u.day=d);
      insert into private.kids_assignments(id,organization_id,unit_id,session_id,group_id,person_id,member_id,role,can_care,active)
       values(md5(''kids-series-staff:''||sid::text||'':''||t.member_id::text)::uuid,s.organization_id,s.unit_id,sid,case when t.role in(''supervisor'',''reception'') then null else gid end,t.person_id,t.member_id,t.role,t.can_care,true)
       on conflict do nothing;
     end loop;
    end if;
   end loop;');
  execute d;
 end if;
end $$;

-- Salvar a sessão recria as próximas datas ainda sem lançamentos (salas e equipe novas).
do $$ declare d text; begin
 d:=pg_get_functiondef('private.kids_setup(uuid,uuid,text,jsonb)'::regprocedure);
 if position('kids_series_refresh' in d)=0 then
  if position('  perform private.kids_series_run((p_data->>''id'')::uuid);' in d)=0 then raise exception 'kids_setup: trecho não encontrado';end if;
  d:=replace(d,'  perform private.kids_series_run((p_data->>''id'')::uuid);','  -- kids_series_refresh
  delete from private.kids_assignments where session_id in(select id from private.kids_sessions where series_id=(p_data->>''id'')::uuid and status=''draft'' and starts_at>now() and not private.kids_session_has_records(id));
  delete from private.kids_session_rooms where session_id in(select id from private.kids_sessions where series_id=(p_data->>''id'')::uuid and status=''draft'' and starts_at>now() and not private.kids_session_has_records(id));
  delete from private.kids_sessions where series_id=(p_data->>''id'')::uuid and status=''draft'' and starts_at>now() and not private.kids_session_has_records(id);
  perform private.kids_series_run((p_data->>''id'')::uuid);');
  execute d;
 end if;
end $$;

-- Recepção: selo "a conferir".
do $$ declare d text; begin
 d:=pg_get_functiondef('private.kids_operations_page(uuid,uuid,uuid,uuid,text,text)'::regprocedure);
 if position('''review''' in d)=0 then
  if (length(d)-length(replace(d,'''profileId'',a.profile_id,''name'',p.full_name,','')))/length('''profileId'',a.profile_id,''name'',p.full_name,')<>1 then raise exception 'kids_operations_page: trecho não encontrado';end if;
  d:=replace(d,'''profileId'',a.profile_id,''name'',p.full_name,','''profileId'',a.profile_id,''name'',p.full_name,''review'',exists(select 1 from private.member_family_requests fr where fr.profile_id=a.profile_id and fr.kind=''kids.create'' and fr.status=''pending''),');
  execute d;
 end if;
end $$;
