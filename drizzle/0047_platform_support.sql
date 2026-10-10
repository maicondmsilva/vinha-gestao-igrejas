CREATE TABLE IF NOT EXISTS saas_support_tickets (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  church_id TEXT NOT NULL,
  category TEXT NOT NULL,
  priority TEXT NOT NULL CHECK(priority IN ('low','medium','high','critical')),
  status TEXT NOT NULL DEFAULT 'new' CHECK(status IN ('new','open','waiting_customer','resolved','closed')),
  subject TEXT NOT NULL,
  description TEXT NOT NULL,
  requester_name TEXT,
  requester_email TEXT,
  assigned_platform_user_id TEXT,
  sla_due_at INTEGER NOT NULL,
  first_response_at INTEGER,
  resolved_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(church_id) REFERENCES churches(id) ON DELETE CASCADE,
  FOREIGN KEY(assigned_platform_user_id) REFERENCES platform_users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS saas_support_messages (
  id TEXT PRIMARY KEY,
  ticket_id TEXT NOT NULL,
  author_platform_user_id TEXT,
  author_name TEXT NOT NULL,
  body TEXT NOT NULL,
  internal INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(ticket_id) REFERENCES saas_support_tickets(id) ON DELETE CASCADE,
  FOREIGN KEY(author_platform_user_id) REFERENCES platform_users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS saas_support_tickets_queue_idx ON saas_support_tickets(status,priority,sla_due_at);
CREATE INDEX IF NOT EXISTS saas_support_tickets_church_idx ON saas_support_tickets(church_id,created_at);
CREATE INDEX IF NOT EXISTS saas_support_messages_ticket_idx ON saas_support_messages(ticket_id,created_at);
