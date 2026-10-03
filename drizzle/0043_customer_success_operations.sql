CREATE TABLE IF NOT EXISTS saas_customer_operations (
  church_id TEXT PRIMARY KEY NOT NULL,
  customer_success_owner TEXT,
  health_status TEXT NOT NULL DEFAULT 'attention' CHECK (health_status IN ('healthy','attention','risk')),
  internal_notes TEXT,
  next_action_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_saas_customer_operations_health
  ON saas_customer_operations(health_status, next_action_at);
