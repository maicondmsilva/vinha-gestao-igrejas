CREATE TABLE IF NOT EXISTS saas_lifecycle_rules (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  threshold_days INTEGER NOT NULL DEFAULT 1,
  priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high','critical')),
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS saas_customer_tasks (
  id TEXT PRIMARY KEY,
  church_id TEXT NOT NULL,
  rule_code TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('low','medium','high','critical')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','done','dismissed')),
  due_at INTEGER,
  assigned_to TEXT,
  source_key TEXT UNIQUE,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  completed_at INTEGER,
  FOREIGN KEY (church_id) REFERENCES churches(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS saas_customer_tasks_status_idx ON saas_customer_tasks(status, due_at);
CREATE INDEX IF NOT EXISTS saas_customer_tasks_church_idx ON saas_customer_tasks(church_id, status);

INSERT OR IGNORE INTO saas_lifecycle_rules (code,name,description,enabled,threshold_days,priority,updated_at) VALUES
 ('trial_ending','Teste próximo do fim','Cria uma tarefa antes do encerramento do período de avaliação.',1,7,'high',unixepoch()*1000),
 ('onboarding_stalled','Onboarding parado','Sinaliza clientes sem avanço no onboarding.',1,5,'medium',unixepoch()*1000),
 ('payment_overdue','Pagamento vencido','Prioriza a recuperação de cobranças vencidas.',1,1,'critical',unixepoch()*1000);
