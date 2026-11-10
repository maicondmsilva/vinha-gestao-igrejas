-- Cover the complete service/member foreign keys, including inactive invitation history.
create index scale_invites_service_scope on private.scale_invites(service_id,organization_id,unit_id);
create index scale_qualifications_member_scope on private.scale_qualifications(member_id,team_id,organization_id,unit_id);
