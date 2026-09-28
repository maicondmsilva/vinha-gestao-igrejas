CREATE TABLE IF NOT EXISTS notification_channel_settings (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  channel TEXT NOT NULL,
  provider TEXT,
  enabled INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'not_configured',
  sender_name TEXT,
  sender_address TEXT,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_channel ON notification_channel_settings(church_id,channel);

CREATE TABLE IF NOT EXISTS notification_templates (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  event_code TEXT NOT NULL,
  channel TEXT NOT NULL,
  name TEXT NOT NULL,
  subject TEXT,
  body TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_template ON notification_templates(church_id,event_code,channel);

CREATE TABLE IF NOT EXISTS notification_rules (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  event_code TEXT NOT NULL,
  channel TEXT NOT NULL,
  offset_minutes INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id)
);

CREATE TABLE IF NOT EXISTS notification_jobs (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  event_code TEXT NOT NULL,
  channel TEXT NOT NULL,
  recipient_person_id TEXT,
  recipient_address TEXT,
  subject TEXT,
  body TEXT NOT NULL,
  entity_type TEXT,
  entity_id TEXT,
  scheduled_at INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  provider_message_id TEXT,
  last_error TEXT,
  created_at INTEGER NOT NULL,
  sent_at INTEGER,
  FOREIGN KEY (church_id) REFERENCES churches(id),
  FOREIGN KEY (recipient_person_id) REFERENCES people(id)
);
CREATE INDEX IF NOT EXISTS idx_notification_jobs_queue ON notification_jobs(church_id,status,scheduled_at);
PRAGMA optimize;
