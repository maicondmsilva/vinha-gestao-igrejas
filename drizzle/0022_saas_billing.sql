CREATE TABLE IF NOT EXISTS saas_invoices (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  subscription_id TEXT NOT NULL,
  reference_month TEXT NOT NULL,
  due_at INTEGER NOT NULL,
  amount_cents INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  provider TEXT,
  provider_invoice_id TEXT,
  payment_url TEXT,
  paid_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE,
  FOREIGN KEY (subscription_id) REFERENCES saas_subscriptions(id) ON DELETE CASCADE,
  UNIQUE(subscription_id, reference_month)
);
CREATE INDEX IF NOT EXISTS saas_invoices_due_idx ON saas_invoices(status, due_at);
CREATE INDEX IF NOT EXISTS saas_invoices_church_idx ON saas_invoices(church_id, created_at);

