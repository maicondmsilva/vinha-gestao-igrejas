CREATE TABLE IF NOT EXISTS chat_conversations (
  id TEXT PRIMARY KEY, church_id TEXT NOT NULL, unit_id TEXT, name TEXT,
  conversation_type TEXT NOT NULL DEFAULT 'channel', scope_type TEXT NOT NULL DEFAULT 'organization',
  scope_id TEXT, visibility TEXT NOT NULL DEFAULT 'members', description TEXT,
  minors_allowed INTEGER NOT NULL DEFAULT 0, retention_days INTEGER NOT NULL DEFAULT 730,
  created_by_user_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'active', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id), FOREIGN KEY (unit_id) REFERENCES church_units(id), FOREIGN KEY (created_by_user_id) REFERENCES church_users(id)
);
CREATE INDEX IF NOT EXISTS idx_chat_conversations_scope ON chat_conversations(church_id,scope_type,scope_id,status);
CREATE TABLE IF NOT EXISTS chat_participants (
  id TEXT PRIMARY KEY, church_id TEXT NOT NULL, conversation_id TEXT NOT NULL, person_id TEXT NOT NULL,
  member_role TEXT NOT NULL DEFAULT 'member', notification_level TEXT NOT NULL DEFAULT 'all',
  last_read_at INTEGER, joined_at INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'active',
  FOREIGN KEY (conversation_id) REFERENCES chat_conversations(id) ON DELETE CASCADE, FOREIGN KEY (person_id) REFERENCES people(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_participant ON chat_participants(conversation_id,person_id);
CREATE TABLE IF NOT EXISTS chat_messages (
  id TEXT PRIMARY KEY, church_id TEXT NOT NULL, conversation_id TEXT NOT NULL, sender_person_id TEXT NOT NULL,
  reply_to_message_id TEXT, body TEXT NOT NULL, message_type TEXT NOT NULL DEFAULT 'text',
  edited_at INTEGER, deleted_at INTEGER, created_at INTEGER NOT NULL,
  FOREIGN KEY (conversation_id) REFERENCES chat_conversations(id) ON DELETE CASCADE,
  FOREIGN KEY (sender_person_id) REFERENCES people(id), FOREIGN KEY (reply_to_message_id) REFERENCES chat_messages(id)
);
CREATE INDEX IF NOT EXISTS idx_chat_messages_feed ON chat_messages(conversation_id,created_at);
CREATE TABLE IF NOT EXISTS chat_moderation_events (
  id TEXT PRIMARY KEY, church_id TEXT NOT NULL, conversation_id TEXT NOT NULL, message_id TEXT,
  actor_user_id TEXT NOT NULL, action TEXT NOT NULL, reason TEXT, created_at INTEGER NOT NULL
);
PRAGMA optimize;
