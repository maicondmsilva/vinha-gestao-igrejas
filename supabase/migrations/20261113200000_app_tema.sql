-- App do membro · tema claro ou escuro definido pela igreja no painel (Configurações). O membro não escolhe.
alter table public.organizations add column if not exists app_theme text not null default 'dark';
do $$ begin
 if not exists(select 1 from pg_constraint where conname='organizations_app_theme_check') then
  alter table public.organizations add constraint organizations_app_theme_check check (app_theme in ('light','dark'));
 end if;
end $$;

do $$
declare d text; n int;
begin
 d:=pg_get_functiondef('private.organization_settings_save'::regproc);
 if position('app_theme_setting' in d)=0 then
  n:=(length(d)-length(replace(d,'''primaryColor'',''accentColor'',''logo'']','')))/length('''primaryColor'',''accentColor'',''logo'']');
  if n<>1 then raise exception 'organization_settings_save: lista de campos não encontrada (%)',n; end if;
  d:=replace(d,'''primaryColor'',''accentColor'',''logo'']','''primaryColor'',''accentColor'',''logo'',''appTheme'']');
  n:=(length(d)-length(replace(d,' if p_data ? ''logo'' then','')))/length(' if p_data ? ''logo'' then');
  if n<>1 then raise exception 'organization_settings_save: trecho do logo não encontrado (%)',n; end if;
  d:=replace(d,' if p_data ? ''logo'' then',' if p_unit is null and p_data ? ''appTheme'' then -- app_theme_setting
  if p_data->>''appTheme'' not in (''light'',''dark'') then raise exception ''invalid_settings'' using errcode=''22023''; end if;
  update public.organizations set app_theme=p_data->>''appTheme'' where id=p_org;
 end if;
 if p_data ? ''logo'' then');
  execute d;
 end if;
 d:=pg_get_functiondef('member_app_api.config(text)'::regprocedure);
 if position('''theme''' in d)=0 then
  n:=(length(d)-length(replace(d,'''accent'',o.accent_color,','')))/length('''accent'',o.accent_color,');
  if n<>1 then raise exception 'member_app_api.config: trecho não encontrado (%)',n; end if;
  execute replace(d,'''accent'',o.accent_color,','''accent'',o.accent_color,''theme'',o.app_theme,');
 end if;
end $$;
