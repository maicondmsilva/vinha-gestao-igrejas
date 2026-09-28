CREATE TABLE IF NOT EXISTS app_notification_reads (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  notification_job_id TEXT NOT NULL,
  person_id TEXT NOT NULL,
  read_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id),
  FOREIGN KEY (notification_job_id) REFERENCES notification_jobs(id),
  FOREIGN KEY (person_id) REFERENCES people(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_notification_read ON app_notification_reads(church_id,notification_job_id,person_id);
CREATE INDEX IF NOT EXISTS idx_app_notification_person ON app_notification_reads(church_id,person_id,read_at);
PRAGMA optimize;
