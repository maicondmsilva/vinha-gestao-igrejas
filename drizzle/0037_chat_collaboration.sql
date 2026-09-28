CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_scope_unique ON chat_conversations(church_id,scope_type,scope_id) WHERE scope_id IS NOT NULL;
CREATE TABLE IF NOT EXISTS chat_attachments (
  id TEXT PRIMARY KEY, church_id TEXT NOT NULL, conversation_id TEXT NOT NULL, message_id TEXT,
  object_key TEXT NOT NULL, file_name TEXT NOT NULL, content_type TEXT NOT NULL, size_bytes INTEGER NOT NULL,
  uploaded_by_person_id TEXT NOT NULL, created_at INTEGER NOT NULL,
  FOREIGN KEY (conversation_id) REFERENCES chat_conversations(id) ON DELETE CASCADE,
  FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_chat_attachment_message ON chat_attachments(message_id);
CREATE TABLE IF NOT EXISTS chat_reactions (
  id TEXT PRIMARY KEY, church_id TEXT NOT NULL, message_id TEXT NOT NULL, person_id TEXT NOT NULL,
  emoji TEXT NOT NULL, created_at INTEGER NOT NULL,
  FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE,
  FOREIGN KEY (person_id) REFERENCES people(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_reaction_unique ON chat_reactions(message_id,person_id,emoji);
CREATE TABLE IF NOT EXISTS chat_mentions (
  id TEXT PRIMARY KEY, church_id TEXT NOT NULL, message_id TEXT NOT NULL, mentioned_person_id TEXT NOT NULL,
  notified_at INTEGER, read_at INTEGER, created_at INTEGER NOT NULL,
  FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE,
  FOREIGN KEY (mentioned_person_id) REFERENCES people(id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_mention_unique ON chat_mentions(message_id,mentioned_person_id);
PRAGMA optimize;
