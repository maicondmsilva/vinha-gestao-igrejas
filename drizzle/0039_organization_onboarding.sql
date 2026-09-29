CREATE TABLE IF NOT EXISTS saas_onboarding_progress (
  church_id TEXT PRIMARY KEY,
  status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress','completed')),
  current_step TEXT NOT NULL DEFAULT 'identity',
  completed_steps TEXT NOT NULL DEFAULT '[]',
  started_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  completed_at INTEGER,
  updated_by_user_id TEXT,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE,
  FOREIGN KEY (updated_by_user_id) REFERENCES church_users(id)
);

CREATE INDEX IF NOT EXISTS idx_saas_onboarding_status
  ON saas_onboarding_progress(status, updated_at);

