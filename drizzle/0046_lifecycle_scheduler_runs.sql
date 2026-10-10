CREATE TABLE IF NOT EXISTS saas_lifecycle_runs (
  id TEXT PRIMARY KEY,
  trigger_type TEXT NOT NULL,
  status TEXT NOT NULL,
  tasks_created INTEGER NOT NULL DEFAULT 0,
  alerts_created INTEGER NOT NULL DEFAULT 0,
  alerts_delivered INTEGER NOT NULL DEFAULT 0,
  alerts_pending INTEGER NOT NULL DEFAULT 0,
  alerts_failed INTEGER NOT NULL DEFAULT 0,
  error_message TEXT,
  started_at INTEGER NOT NULL,
  finished_at INTEGER
);

CREATE INDEX IF NOT EXISTS saas_lifecycle_runs_started_idx ON saas_lifecycle_runs(started_at);
