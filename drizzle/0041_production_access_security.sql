CREATE TABLE IF NOT EXISTS auth_security_policies (
  church_id TEXT PRIMARY KEY,
  require_mfa_admins INTEGER NOT NULL DEFAULT 1,
  require_mfa_finance INTEGER NOT NULL DEFAULT 1,
  require_verified_email INTEGER NOT NULL DEFAULT 1,
  require_verified_phone_members INTEGER NOT NULL DEFAULT 0,
  session_timeout_minutes INTEGER NOT NULL DEFAULT 480,
  max_failed_attempts INTEGER NOT NULL DEFAULT 5,
  updated_by_user_id TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE,
  FOREIGN KEY (updated_by_user_id) REFERENCES church_users(id)
);

CREATE TABLE IF NOT EXISTS user_security_profiles (
  user_id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  default_unit_id TEXT,
  identity_provider TEXT NOT NULL DEFAULT 'openai_sites',
  email_verified_at INTEGER,
  phone_verified_at INTEGER,
  mfa_status TEXT NOT NULL DEFAULT 'not_enrolled' CHECK (mfa_status IN ('not_enrolled','pending','enabled','recovery_required')),
  last_seen_at INTEGER,
  last_ip_address TEXT,
  failed_attempts INTEGER NOT NULL DEFAULT 0,
  locked_until INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (user_id) REFERENCES church_users(id) ON DELETE CASCADE,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE,
  FOREIGN KEY (default_unit_id) REFERENCES church_units(id)
);

CREATE INDEX IF NOT EXISTS idx_user_security_church ON user_security_profiles(church_id, mfa_status, updated_at);

CREATE TABLE IF NOT EXISTS user_login_events (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('login','logout','denied','mfa_challenge','recovery_requested','unit_changed')),
  identity_provider TEXT NOT NULL,
  ip_address TEXT,
  user_agent TEXT,
  metadata TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES church_users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_user_login_events_church ON user_login_events(church_id, created_at);
CREATE INDEX IF NOT EXISTS idx_user_login_events_user ON user_login_events(user_id, created_at);

INSERT OR IGNORE INTO user_security_profiles (user_id,church_id,identity_provider,email_verified_at,mfa_status,created_at,updated_at)
SELECT id,church_id,'openai_sites',created_at,CASE WHEN role IN ('admin','pastor') THEN 'pending' ELSE 'not_enrolled' END,created_at,created_at
FROM church_users;

PRAGMA optimize;
