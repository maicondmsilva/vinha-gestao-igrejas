set local lock_timeout='5s';
create index church_app_events_unit on private.church_app_events(unit_id,organization_id);
create index church_app_registrations_event_scope on private.church_app_registrations(event_id,organization_id,unit_id);
create index church_app_registrations_auth_user on private.church_app_registrations(user_id);
