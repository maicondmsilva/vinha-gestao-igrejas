CREATE TABLE IF NOT EXISTS saas_billing_provider_settings (
  id TEXT PRIMARY KEY,
  provider TEXT NOT NULL UNIQUE,
  environment TEXT NOT NULL DEFAULT 'sandbox',
  status TEXT NOT NULL DEFAULT 'inactive',
  is_primary INTEGER NOT NULL DEFAULT 0,
  credential_ciphertext TEXT,
  credential_iv TEXT,
  credential_hint TEXT,
  webhook_token_ciphertext TEXT,
  webhook_token_iv TEXT,
  webhook_token_hint TEXT,
  last_tested_at INTEGER,
  last_test_status TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS saas_billing_profiles (
  church_id TEXT PRIMARY KEY,
  legal_name TEXT NOT NULL,
  tax_id TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  postal_code TEXT,
  address TEXT,
  address_number TEXT,
  district TEXT,
  city TEXT,
  state TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS saas_billing_events (
  id TEXT PRIMARY KEY,
  provider TEXT NOT NULL,
  external_event_id TEXT NOT NULL,
  invoice_id TEXT,
  event_type TEXT NOT NULL,
  payload TEXT,
  processed_at INTEGER NOT NULL,
  UNIQUE(provider, external_event_id),
  FOREIGN KEY (invoice_id) REFERENCES saas_invoices(id) ON DELETE SET NULL
);

ALTER TABLE saas_invoices ADD COLUMN checkout_expires_at INTEGER;
CREATE INDEX IF NOT EXISTS saas_billing_events_invoice_idx ON saas_billing_events(invoice_id, processed_at);
