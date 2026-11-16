-- Portal da Vinha: vídeo de cada módulo, cadastrado pela Central Vinha (link do YouTube ou Vimeo).
create table public.vinha_portal_videos (
 module text primary key check (module ~ '^[a-z]{2,30}$'),
 url text not null check (char_length(url) <= 300 and url ~ '^https://(www\.)?(youtube\.com|youtu\.be|m\.youtube\.com|vimeo\.com|player\.vimeo\.com)/'),
 updated_by uuid references auth.users(id) on delete set null,
 updated_at timestamptz not null default now()
);
create index vinha_portal_videos_author_idx on public.vinha_portal_videos(updated_by);
alter table public.vinha_portal_videos enable row level security;
revoke all on public.vinha_portal_videos from anon, authenticated;
grant select on public.vinha_portal_videos to authenticated;
grant all on public.vinha_portal_videos to service_role;
-- Qualquer usuário conectado assiste aos vídeos do Portal; só a Central altera.
create policy vinha_portal_videos_read on public.vinha_portal_videos for select to authenticated using (true);

create function private.save_portal_video(p_module text, p_url text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_url text := nullif(btrim(coalesce(p_url, '')), '');
begin
 perform private.require_platform_manager();
 if p_module is null or p_module !~ '^[a-z]{2,30}$' then raise exception 'Módulo inválido.'; end if;
 if v_url is null then
  delete from public.vinha_portal_videos where module = p_module;
 else
  if char_length(v_url) > 300 or v_url !~ '^https://(www\.)?(youtube\.com|youtu\.be|m\.youtube\.com|vimeo\.com|player\.vimeo\.com)/' then
   raise exception 'Use um link do YouTube ou do Vimeo.';
  end if;
  insert into public.vinha_portal_videos(module, url, updated_by) values (p_module, v_url, auth.uid())
  on conflict (module) do update set url = excluded.url, updated_by = auth.uid(), updated_at = now();
 end if;
 insert into public.platform_audit_events(actor_user_id, action, entity_type, metadata)
 values (auth.uid(), 'portal.video_saved', 'vinha', jsonb_build_object('module', p_module, 'url', v_url));
end $$;
revoke all on function private.save_portal_video(text, text) from public, anon;
grant execute on function private.save_portal_video(text, text) to authenticated;
create function public.save_portal_video(p_module text, p_url text) returns void
language sql security invoker set search_path = '' as $$ select private.save_portal_video(p_module, p_url) $$;
revoke all on function public.save_portal_video(text, text) from public, anon;
grant execute on function public.save_portal_video(text, text) to authenticated;
