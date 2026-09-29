CREATE TABLE IF NOT EXISTS platform_users (
  id TEXT PRIMARY KEY,
  external_user_id TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL,
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('owner','admin','support','read_only')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','revoked')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  last_login_at INTEGER
);

CREATE INDEX IF NOT EXISTS platform_users_email_idx ON platform_users(email, status);

CREATE TABLE IF NOT EXISTS platform_audit_logs (
  id TEXT PRIMARY KEY,
  actor_platform_user_id TEXT NOT NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  metadata TEXT,
  ip_address TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (actor_platform_user_id) REFERENCES platform_users(id)
);

CREATE INDEX IF NOT EXISTS platform_audit_actor_idx ON platform_audit_logs(actor_platform_user_id, created_at);
CREATE INDEX IF NOT EXISTS platform_audit_entity_idx ON platform_audit_logs(entity_type, entity_id, created_at);
