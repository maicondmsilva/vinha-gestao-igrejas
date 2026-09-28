CREATE TABLE IF NOT EXISTS saas_hierarchy_module_access (
  id TEXT PRIMARY KEY,
  link_id TEXT NOT NULL,
  module_code TEXT NOT NULL,
  access_level TEXT NOT NULL DEFAULT 'none',
  include_personal_data INTEGER NOT NULL DEFAULT 0,
  approved_by_user_id TEXT,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (link_id) REFERENCES saas_organization_links(id) ON DELETE CASCADE,
  UNIQUE(link_id,module_code)
);
CREATE INDEX IF NOT EXISTS idx_hierarchy_access_link_level ON saas_hierarchy_module_access(link_id,access_level);
PRAGMA optimize;
