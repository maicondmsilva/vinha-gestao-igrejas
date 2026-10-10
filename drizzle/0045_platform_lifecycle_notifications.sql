CREATE TABLE IF NOT EXISTS saas_notification_channels (
  channel TEXT PRIMARY KEY CHECK (channel IN ('email','push','whatsapp')),
  provider TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'not_configured',
  default_recipient TEXT,
  sender_name TEXT,
  sender_address TEXT,
  credential_ciphertext TEXT,
  credential_iv TEXT,
  credential_hint TEXT,
  provider_config TEXT,
  last_tested_at INTEGER,
  last_test_status TEXT,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS saas_lifecycle_templates (
  id TEXT PRIMARY KEY,
  rule_code TEXT NOT NULL,
  channel TEXT NOT NULL CHECK (channel IN ('email','push','whatsapp')),
  subject TEXT,
  body TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL,
  UNIQUE(rule_code,channel)
);

CREATE TABLE IF NOT EXISTS saas_lifecycle_deliveries (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  channel TEXT NOT NULL,
  recipient_address TEXT,
  subject TEXT,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  attempts INTEGER NOT NULL DEFAULT 0,
  provider_message_id TEXT,
  last_error TEXT,
  next_attempt_at INTEGER,
  sent_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (task_id) REFERENCES saas_customer_tasks(id) ON DELETE CASCADE,
  UNIQUE(task_id,channel)
);

CREATE INDEX IF NOT EXISTS saas_lifecycle_deliveries_status_idx ON saas_lifecycle_deliveries(status,next_attempt_at);

INSERT OR IGNORE INTO saas_notification_channels (channel,provider,enabled,status,sender_name,updated_at) VALUES
 ('email','resend',0,'not_configured','Vinha',unixepoch()*1000),
 ('push','firebase',0,'not_configured','Vinha',unixepoch()*1000),
 ('whatsapp','meta_whatsapp',0,'not_configured','Vinha',unixepoch()*1000);

INSERT OR IGNORE INTO saas_lifecycle_templates (id,rule_code,channel,subject,body,enabled,updated_at) VALUES
 ('tpl-trial-email','trial_ending','email','Cliente próximo do fim do teste','A organização {{igreja}} encerra o período de teste em {{data}}. Acesse a Central Vinha para acompanhar a conversão.',1,unixepoch()*1000),
 ('tpl-trial-push','trial_ending','push','Teste terminando','{{igreja}} está próximo do fim do período de avaliação.',1,unixepoch()*1000),
 ('tpl-trial-whatsapp','trial_ending','whatsapp',NULL,'Vinha: o teste de {{igreja}} está próximo do fim. Prazo: {{data}}.',1,unixepoch()*1000),
 ('tpl-onboarding-email','onboarding_stalled','email','Onboarding sem avanço','O onboarding de {{igreja}} está parado. Próxima ação: {{tarefa}}.',1,unixepoch()*1000),
 ('tpl-onboarding-push','onboarding_stalled','push','Onboarding parado','{{igreja}} precisa de acompanhamento no onboarding.',1,unixepoch()*1000),
 ('tpl-onboarding-whatsapp','onboarding_stalled','whatsapp',NULL,'Vinha: o onboarding de {{igreja}} está sem avanço. Verifique a fila operacional.',1,unixepoch()*1000),
 ('tpl-payment-email','payment_overdue','email','Pagamento vencido','Existe uma cobrança vencida de {{igreja}}. Consulte a tarefa {{tarefa}} na Central Vinha.',1,unixepoch()*1000),
 ('tpl-payment-push','payment_overdue','push','Pagamento vencido','{{igreja}} possui uma cobrança vencida.',1,unixepoch()*1000),
 ('tpl-payment-whatsapp','payment_overdue','whatsapp',NULL,'Vinha: existe pagamento vencido de {{igreja}}. Consulte a Central Vinha.',1,unixepoch()*1000);
