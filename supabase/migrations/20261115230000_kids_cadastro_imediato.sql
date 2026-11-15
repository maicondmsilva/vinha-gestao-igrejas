-- Kids · cadastro feito pelo responsável no app já fica ativo na hora (criança, vínculo e cuidados),
-- e continua na fila da secretaria para conferir o cadastro e o vínculo:
--  · aprovar  → o vínculo passa a "Responsável conferido" (com a anotação de quem conferiu);
--  · vincular a um cadastro existente → liga o responsável à criança que já existia e arquiva a duplicada;
--  · recusar  → arquiva a ficha e retira o vínculo.

create or replace function private.kids_app_create(p_request uuid) returns uuid
language plpgsql security definer set search_path to '' as $function$
declare r private.member_family_requests; child uuid; profile uuid;
begin
 select * into r from private.member_family_requests where id=p_request for update;
 if r.id is null or r.kind<>'kids.create' or r.status<>'pending' or r.profile_id is not null then return r.profile_id;end if;
 child:=extensions.gen_random_uuid();profile:=extensions.gen_random_uuid();
 insert into public.people(id,organization_id,unit_id,full_name,birth_date,status) values(child,r.organization_id,r.unit_id,btrim(r.data->>'name'),(r.data->>'birth')::date,'active');
 insert into private.kids_profiles(id,organization_id,unit_id,person_id,review_status,created_by) values(profile,r.organization_id,r.unit_id,child,'approved',r.user_id);
 insert into private.kids_guardians(organization_id,unit_id,profile_id,person_id,relationship,verification_note,can_pickup,can_edit,status,approved_by,approved_at,created_by)
  values(r.organization_id,r.unit_id,profile,r.person_id,'Responsável (a conferir)','Cadastrado pelo responsável no app; aguarda a conferência da secretaria.',true,true,'approved',r.user_id,clock_timestamp(),r.user_id)
  on conflict(profile_id,person_id) do nothing;
 if length(btrim(coalesce(r.data->>'care','')))>0 then
  insert into private.kids_care(profile_id,organization_id,unit_id,instructions,source) values(profile,r.organization_id,r.unit_id,r.data->>'care','Informado pelo responsável no app')
   on conflict(profile_id) do update set instructions=excluded.instructions,source=excluded.source;
 end if;
 insert into private.kids_history(organization_id,unit_id,profile_id,person_id,actor_id,action,changed_fields) values(r.organization_id,r.unit_id,profile,child,r.user_id,'kids.app.created',array['profile','guardian','care']);
 update private.member_family_requests set profile_id=profile,updated_at=clock_timestamp() where id=r.id;
 return profile;
end $function$;
revoke all on function private.kids_app_create(uuid) from public,anon,authenticated;

create or replace function private.kids_app_create_trigger() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
 if new.kind='kids.create' and new.status='pending' and new.profile_id is null then perform private.kids_app_create(new.id);end if;
 return null;
end $$;
revoke all on function private.kids_app_create_trigger() from public,anon,authenticated;
drop trigger if exists kids_app_create on private.member_family_requests;
create trigger kids_app_create after insert on private.member_family_requests for each row execute function private.kids_app_create_trigger();

-- Pedidos que já estavam na fila passam a valer agora.
do $$ declare x uuid; begin
 for x in select id from private.member_family_requests where kind='kids.create' and status='pending' and profile_id is null loop perform private.kids_app_create(x);end loop;
end $$;

-- Conferência da secretaria.
do $$ declare d text; begin
 d:=pg_get_functiondef('private.member_family_admin(uuid,uuid,text,uuid,integer,jsonb,integer)'::regprocedure);
 if position('kids_app_conferido' in d)=0 then
  if position('    elsif nullif(p_data->>''existingProfile'','''') is not null then' in d)=0
   or position('  update private.member_family_requests set status=answer,reason=p_data->>''reason''' in d)=0
   or position('''Responsável conferido''' in d)=0 then raise exception 'member_family_admin: trechos não encontrados';end if;
  -- Aprovar o cadastro já criado pelo app.
  d:=replace(d,'    elsif nullif(p_data->>''existingProfile'','''') is not null then',
   '    elsif req.kind=''kids.create'' and req.profile_id is not null and nullif(p_data->>''existingProfile'','''') is null then -- kids_app_conferido
     select k.id,k.person_id into profile,child from private.kids_profiles k where k.id=req.profile_id for update;
     update private.kids_profiles set status=''active'',version=version+1,updated_at=clock_timestamp() where id=profile;
    elsif nullif(p_data->>''existingProfile'','''') is not null then');
  -- Duplicada ou recusada: arquiva a ficha criada pelo app e retira o vínculo dela.
  d:=replace(d,'  update private.member_family_requests set status=answer,reason=p_data->>''reason''',
   '  if req.kind=''kids.create'' and req.profile_id is not null and (answer<>''approved'' or (profile is not null and profile<>req.profile_id)) then
   update private.kids_profiles set status=''archived'',version=version+1,updated_at=clock_timestamp() where id=req.profile_id;
   update private.kids_guardians set status=''revoked'',approved_by=null,approved_at=null,can_pickup=false,version=version+1,updated_at=clock_timestamp() where profile_id=req.profile_id;
  end if;
  update private.member_family_requests set status=answer,reason=p_data->>''reason''');
  -- O vínculo criado pelo app passa a "Responsável conferido".
  if position('on conflict(profile_id,person_id) do update set status=''approved'',' in d)=0 then raise exception 'member_family_admin: vínculo não encontrado';end if;
  d:=replace(d,'on conflict(profile_id,person_id) do update set status=''approved'',','on conflict(profile_id,person_id) do update set relationship=excluded.relationship,status=''approved'',');
  execute d;
 end if;
end $$;
