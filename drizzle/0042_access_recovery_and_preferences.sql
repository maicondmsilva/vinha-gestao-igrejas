CREATE TABLE IF NOT EXISTS user_access_preferences (
  external_user_id TEXT PRIMARY KEY,
  selected_church_id TEXT,
  selected_unit_id TEXT,
  theme_preference TEXT NOT NULL DEFAULT 'system' CHECK (theme_preference IN ('light','dark','system')),
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (selected_church_id) REFERENCES churches(id),
  FOREIGN KEY (selected_unit_id) REFERENCES church_units(id)
);

CREATE TABLE IF NOT EXISTS access_recovery_requests (
  id TEXT PRIMARY KEY,
  church_id TEXT,
  email TEXT NOT NULL,
  church_slug TEXT,
  request_type TEXT NOT NULL DEFAULT 'access' CHECK (request_type IN ('access','email_changed','mfa','locked')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','in_review','resolved','cancelled')),
  public_protocol TEXT NOT NULL UNIQUE,
  ip_hash TEXT NOT NULL,
  user_agent TEXT,
  reviewed_by_user_id TEXT,
  review_note TEXT,
  requested_at INTEGER NOT NULL,
  reviewed_at INTEGER,
  FOREIGN KEY (church_id) REFERENCES churches(id),
  FOREIGN KEY (reviewed_by_user_id) REFERENCES church_users(id)
);

CREATE INDEX IF NOT EXISTS idx_access_recovery_church ON access_recovery_requests(church_id,status,requested_at);
CREATE INDEX IF NOT EXISTS idx_access_recovery_email ON access_recovery_requests(email,requested_at);
PRAGMA optimize;
