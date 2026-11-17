-- Kids · lembrete de aniversário à equipe da sala: quando a criança aniversariante entra, a equipe escalada
-- naquela sala (e a coordenação da sessão) recebe um aviso no app da igreja. Reescreve o aviso à família
-- para que os dois avisos saiam do mesmo ponto (a presença).
begin;
set local lock_timeout='5s';

-- Envia uma mensagem de texto próprio para aparelhos escolhidos, dentro da campanha fixa "Avisos do Kids" da igreja.
create or replace function private.kids_push(p_org uuid, p_unit uuid, p_users uuid[], p_title text, p_body text) returns integer
language plpgsql security definer set search_path to '' as $$
declare camp uuid; run uuid; n integer;
begin
 if coalesce(cardinality(p_users),0)=0 or not exists(select 1 from private.member_push_devices d
   where d.user_id=any(p_users) and d.organization_id=p_org and d.enabled and d.token is not null) then return 0; end if;
 insert into private.push_campaigns(organization_id,owner_unit,title,body,link,targets,source,source_key,status)
  values(p_org,p_unit,'Avisos do Kids','Entrada e saída das crianças','{"screen":"kids"}',array[p_unit],'kids','kids:'||p_unit,'sent')
  on conflict(organization_id,source,source_key) do update set updated_at=clock_timestamp() returning id into camp;
 insert into private.push_runs(campaign_id,scheduled_for) values(camp,clock_timestamp()) on conflict do nothing returning id into run;
 if run is null then return 0; end if;
 insert into private.push_messages(run_id,device_id,user_id,title,body)
  select distinct on (d.id) run,d.id,d.user_id,left(p_title,65),left(p_body,240) from private.member_push_devices d
  where d.user_id=any(p_users) and d.organization_id=p_org and d.enabled and d.token is not null
  on conflict do nothing;
 get diagnostics n=row_count;
 update private.push_runs set recipients=n where id=run;
 return n;
end $$;
revoke all on function private.kids_push(uuid,uuid,uuid[],text,text) from public,anon,authenticated;

create or replace function private.kids_family_notice() returns trigger
language plpgsql security definer set search_path to '' as $$
declare child text; born date; room text; adult text; zone text; today date; family uuid[]; team uuid[]; age int;
begin
 if tg_op='INSERT' and new.status<>'present' then return new; end if;
 if tg_op='UPDATE' and not (old.status='present' and new.status='out') then return new; end if;
 select split_part(btrim(p.full_name),' ',1),p.birth_date into child,born from private.kids_profiles k join public.people p on p.id=k.person_id where k.id=new.profile_id;
 select r.name into room from private.kids_session_rooms g join private.kids_rooms r on r.id=g.room_id where g.id=new.group_id;
 zone:=coalesce(private.unit_timezone(new.unit_id),'America/Sao_Paulo');
 today:=(clock_timestamp() at time zone zone)::date;
 -- Família: responsáveis aprovados e permanentes (nunca dados de saúde).
 select coalesce(array_agg(distinct p.auth_user_id),'{}') into family from private.kids_guardians g join public.people p on p.id=g.person_id
  where g.profile_id=new.profile_id and g.status='approved' and not g.temporary and p.auth_user_id is not null;
 if tg_op='INSERT' then
  perform private.kids_push(new.organization_id,new.unit_id,family,coalesce(child,'Criança')||' chegou ao Kids',
   'Entrada às '||to_char(new.checked_in_at at time zone zone,'HH24:MI')||coalesce(' na '||room,'')||'. Guarde o comprovante para a retirada.');
  -- Aniversário hoje: lembrete à equipe escalada na sala e à coordenação da sessão.
  if born is not null and to_char(born,'MMDD')=to_char(today,'MMDD') then
   age:=extract(year from age(today,born))::int;
   select coalesce(array_agg(distinct p.auth_user_id),'{}') into team from private.kids_assignments a join public.people p on p.id=a.person_id
    where a.session_id=new.session_id and a.active and a.declined_at is null and p.auth_user_id is not null
      and (a.group_id=new.group_id or a.role='supervisor');
   perform private.kids_push(new.organization_id,new.unit_id,team,'🎂 Aniversário'||coalesce(' na '||room,' no Kids'),
    coalesce(child,'Uma criança')||' faz '||age||case when age=1 then ' ano' else ' anos' end||' hoje e acabou de chegar. Que tal celebrar com a turma?');
  end if;
 else
  select split_part(btrim(p.full_name),' ',1) into adult from public.people p where p.id=new.pickup_guardian;
  perform private.kids_push(new.organization_id,new.unit_id,family,coalesce(child,'Criança')||' saiu do Kids',
   'Retirada às '||to_char(coalesce(new.checked_out_at,clock_timestamp()) at time zone zone,'HH24:MI')||coalesce(' com '||adult,'')||'. Se não reconhece esta retirada, fale com a equipe agora.');
 end if;
 return new;
exception when others then
 -- Os avisos nunca impedem a entrada ou a retirada.
 return new;
end $$;
revoke all on function private.kids_family_notice() from public,anon,authenticated;
commit;
