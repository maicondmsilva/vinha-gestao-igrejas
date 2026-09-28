ALTER TABLE saas_organization_invites ADD COLUMN invite_token TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS saas_organization_invites_token_idx
  ON saas_organization_invites(invite_token);

