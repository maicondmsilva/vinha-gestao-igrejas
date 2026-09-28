CREATE TABLE IF NOT EXISTS notification_automation_runs (
  id TEXT PRIMARY KEY, church_id TEXT, trigger_type TEXT NOT NULL,
  generated_count INTEGER NOT NULL DEFAULT 0, processed_count INTEGER NOT NULL DEFAULT 0,
  delivered_count INTEGER NOT NULL DEFAULT 0, retry_count INTEGER NOT NULL DEFAULT 0,
  failed_count INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, error_message TEXT,
  started_at INTEGER NOT NULL, finished_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_notification_automation_runs ON notification_automation_runs(church_id,started_at);
PRAGMA optimize;
