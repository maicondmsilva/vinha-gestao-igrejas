ALTER TABLE notification_jobs ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE notification_jobs ADD COLUMN next_attempt_at INTEGER;
ALTER TABLE notification_jobs ADD COLUMN updated_at INTEGER;

CREATE TABLE IF NOT EXISTS app_device_tokens (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  person_id TEXT NOT NULL,
  platform TEXT NOT NULL,
  device_name TEXT,
  token TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  last_seen_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id),
  FOREIGN KEY (person_id) REFERENCES people(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_device_token ON app_device_tokens(church_id,token);
CREATE INDEX IF NOT EXISTS idx_app_device_person ON app_device_tokens(church_id,person_id,status);
CREATE INDEX IF NOT EXISTS idx_notification_retry ON notification_jobs(status,next_attempt_at,attempts);
PRAGMA optimize;
