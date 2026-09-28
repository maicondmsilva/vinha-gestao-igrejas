CREATE TABLE IF NOT EXISTS saas_organization_invites (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  owner_name TEXT NOT NULL,
  owner_email TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at INTEGER NOT NULL,
  accepted_at INTEGER,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS saas_organization_invites_church_idx
  ON saas_organization_invites(church_id, status);

