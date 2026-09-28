CREATE TABLE IF NOT EXISTS saas_hierarchy_requests (
  id TEXT PRIMARY KEY,
  parent_church_id TEXT NOT NULL,
  child_church_id TEXT NOT NULL,
  billing_mode TEXT NOT NULL DEFAULT 'individual',
  status TEXT NOT NULL DEFAULT 'pending',
  parent_approved_at INTEGER,
  child_approved_at INTEGER,
  parent_approved_by TEXT,
  child_approved_by TEXT,
  requested_by TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  resolved_at INTEGER,
  FOREIGN KEY (parent_church_id) REFERENCES churches(id) ON DELETE CASCADE,
  FOREIGN KEY (child_church_id) REFERENCES churches(id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX IF NOT EXISTS saas_pending_hierarchy_request_idx ON saas_hierarchy_requests(parent_church_id,child_church_id) WHERE status='pending';
CREATE INDEX IF NOT EXISTS saas_hierarchy_request_org_idx ON saas_hierarchy_requests(status,parent_church_id,child_church_id);

CREATE TABLE IF NOT EXISTS saas_consolidated_invoices (
  id TEXT PRIMARY KEY,
  payer_church_id TEXT NOT NULL,
  reference_month TEXT NOT NULL,
  due_at INTEGER NOT NULL,
  amount_cents INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  provider TEXT,
  provider_invoice_id TEXT,
  payment_url TEXT,
  checkout_expires_at INTEGER,
  paid_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (payer_church_id) REFERENCES churches(id) ON DELETE CASCADE,
  UNIQUE(payer_church_id,reference_month)
);
CREATE TABLE IF NOT EXISTS saas_consolidated_invoice_items (
  id TEXT PRIMARY KEY,
  consolidated_invoice_id TEXT NOT NULL,
  invoice_id TEXT NOT NULL UNIQUE,
  amount_cents INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (consolidated_invoice_id) REFERENCES saas_consolidated_invoices(id) ON DELETE CASCADE,
  FOREIGN KEY (invoice_id) REFERENCES saas_invoices(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS saas_consolidated_invoice_status_idx ON saas_consolidated_invoices(status,due_at);
