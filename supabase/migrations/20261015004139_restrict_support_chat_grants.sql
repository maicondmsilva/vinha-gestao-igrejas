revoke all on public.saas_trial_registrations,public.saas_chat_conversations,public.saas_chat_messages from public,anon,authenticated;
grant select,insert on public.saas_trial_registrations to authenticated;
grant select,update on public.saas_chat_conversations to authenticated;
grant select,insert on public.saas_chat_messages to authenticated;
