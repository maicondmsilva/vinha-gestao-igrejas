CREATE TABLE IF NOT EXISTS schedule_reminders (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  position_id TEXT NOT NULL,
  recipient_person_id TEXT NOT NULL,
  channel TEXT NOT NULL DEFAULT 'push',
  status TEXT NOT NULL DEFAULT 'queued',
  sent_by_user_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id),
  FOREIGN KEY (position_id) REFERENCES schedule_positions(id) ON DELETE CASCADE,
  FOREIGN KEY (recipient_person_id) REFERENCES people(id),
  FOREIGN KEY (sent_by_user_id) REFERENCES church_users(id)
);
CREATE INDEX IF NOT EXISTS idx_schedule_reminders_position ON schedule_reminders(position_id,created_at);
PRAGMA optimize;
