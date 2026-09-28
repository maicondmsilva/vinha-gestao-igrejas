CREATE TABLE IF NOT EXISTS saas_organization_links (
  id TEXT PRIMARY KEY,
  parent_church_id TEXT NOT NULL,
  child_church_id TEXT NOT NULL,
  relationship_type TEXT NOT NULL DEFAULT 'daughter',
  status TEXT NOT NULL DEFAULT 'active',
  linked_at INTEGER NOT NULL,
  unlinked_at INTEGER,
  created_by TEXT,
  FOREIGN KEY (parent_church_id) REFERENCES churches(id) ON DELETE CASCADE,
  FOREIGN KEY (child_church_id) REFERENCES churches(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS saas_active_child_link_idx ON saas_organization_links(child_church_id) WHERE status='active';
CREATE INDEX IF NOT EXISTS saas_parent_links_idx ON saas_organization_links(parent_church_id,status);

CREATE TABLE IF NOT EXISTS saas_billing_responsibilities (
  church_id TEXT PRIMARY KEY,
  payer_church_id TEXT NOT NULL,
  billing_mode TEXT NOT NULL DEFAULT 'individual',
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE,
  FOREIGN KEY (payer_church_id) REFERENCES churches(id) ON DELETE CASCADE
);

ALTER TABLE saas_invoices ADD COLUMN payer_church_id TEXT REFERENCES churches(id);
CREATE INDEX IF NOT EXISTS saas_invoices_payer_idx ON saas_invoices(payer_church_id,status,due_at);
