CREATE TABLE IF NOT EXISTS cells (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  unit_id TEXT,
  name TEXT NOT NULL,
  leader_person_id TEXT,
  co_leader_person_id TEXT,
  meeting_day TEXT NOT NULL,
  meeting_time TEXT NOT NULL,
  meeting_type TEXT NOT NULL DEFAULT 'presential',
  address TEXT,
  capacity INTEGER,
  status TEXT NOT NULL DEFAULT 'active',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id),
  FOREIGN KEY (unit_id) REFERENCES church_units(id),
  FOREIGN KEY (leader_person_id) REFERENCES people(id),
  FOREIGN KEY (co_leader_person_id) REFERENCES people(id)
);
CREATE INDEX IF NOT EXISTS idx_cells_church_status ON cells(church_id,status);

CREATE TABLE IF NOT EXISTS cell_members (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  cell_id TEXT NOT NULL,
  person_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'participant',
  status TEXT NOT NULL DEFAULT 'active',
  joined_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id),
  FOREIGN KEY (cell_id) REFERENCES cells(id) ON DELETE CASCADE,
  FOREIGN KEY (person_id) REFERENCES people(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cell_member_unique ON cell_members(cell_id,person_id);

CREATE TABLE IF NOT EXISTS cell_meetings (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  cell_id TEXT NOT NULL,
  occurred_at INTEGER NOT NULL,
  theme TEXT,
  visitors INTEGER NOT NULL DEFAULT 0,
  offerings_cents INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  created_by_user_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id),
  FOREIGN KEY (cell_id) REFERENCES cells(id) ON DELETE CASCADE,
  FOREIGN KEY (created_by_user_id) REFERENCES church_users(id)
);
CREATE INDEX IF NOT EXISTS idx_cell_meetings_cell_date ON cell_meetings(cell_id,occurred_at);

CREATE TABLE IF NOT EXISTS cell_attendance (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  meeting_id TEXT NOT NULL,
  person_id TEXT NOT NULL,
  present INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (church_id) REFERENCES churches(id),
  FOREIGN KEY (meeting_id) REFERENCES cell_meetings(id) ON DELETE CASCADE,
  FOREIGN KEY (person_id) REFERENCES people(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cell_attendance_unique ON cell_attendance(meeting_id,person_id);
PRAGMA optimize;
