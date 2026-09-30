CREATE TABLE IF NOT EXISTS church_user_invites (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  role TEXT NOT NULL,
  unit_id TEXT,
  invite_token TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','revoked','expired')),
  expires_at INTEGER NOT NULL,
  invited_by_user_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  sent_at INTEGER,
  accepted_at INTEGER,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE,
  FOREIGN KEY (unit_id) REFERENCES church_units(id),
  FOREIGN KEY (invited_by_user_id) REFERENCES church_users(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_church_user_invites_token ON church_user_invites(invite_token);
CREATE INDEX IF NOT EXISTS idx_church_user_invites_queue ON church_user_invites(church_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_church_user_invites_email ON church_user_invites(church_id, email, status);

CREATE TABLE IF NOT EXISTS member_import_jobs (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  file_name TEXT NOT NULL,
  total_rows INTEGER NOT NULL DEFAULT 0,
  imported_rows INTEGER NOT NULL DEFAULT 0,
  skipped_rows INTEGER NOT NULL DEFAULT 0,
  error_rows INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'processing' CHECK (status IN ('processing','completed','failed')),
  summary TEXT,
  created_by_user_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  completed_at INTEGER,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by_user_id) REFERENCES church_users(id)
);

CREATE INDEX IF NOT EXISTS idx_member_import_jobs_church ON member_import_jobs(church_id, created_at);
PRAGMA optimize;

