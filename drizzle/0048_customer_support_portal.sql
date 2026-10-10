ALTER TABLE saas_support_tickets ADD COLUMN customer_rating INTEGER CHECK(customer_rating BETWEEN 1 AND 5);
ALTER TABLE saas_support_tickets ADD COLUMN customer_feedback TEXT;
ALTER TABLE saas_support_tickets ADD COLUMN rated_at INTEGER;

CREATE TABLE IF NOT EXISTS saas_support_articles (
  id TEXT PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  body TEXT NOT NULL,
  keywords TEXT,
  featured INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS saas_support_articles_active_idx ON saas_support_articles(active,featured,category);

INSERT OR IGNORE INTO saas_support_articles (id,slug,category,title,summary,body,keywords,featured,active,created_at,updated_at) VALUES
('support-article-access','primeiro-acesso-e-login','Acesso','Primeiro acesso e problemas de login','Como entrar, selecionar sua igreja e recuperar o acesso.','Use o e-mail que recebeu o convite da igreja. Após entrar, selecione o ministério e a unidade de trabalho. Se o convite expirou ou sua conta não aparece, peça ao administrador local para reenviar o convite ou abra um chamado informando seu e-mail e a igreja.','login,acesso,convite,senha,conta',1,1,1791622800000,1791622800000),
('support-article-billing','pagamentos-e-assinatura','Financeiro','Pagamentos, assinatura e notas','Entenda cobrança por igreja, pagamento centralizado e situação da assinatura.','Cada igreja pode pagar sua própria assinatura ou o ministério pode centralizar a cobrança em um único CNPJ. No painel financeiro, confirme o responsável pagador, a forma de pagamento e as unidades incluídas. Em caso de divergência, abra um chamado com o período e a unidade afetada.','pagamento,assinatura,boleto,pix,cartao,cnpj',1,1,1791622800000,1791622800000),
('support-article-app','cadastro-no-aplicativo','Aplicativo','Cadastro no aplicativo e vínculo de membro','Saiba como o usuário escolhe a unidade e é conciliado com o cadastro da igreja.','No primeiro acesso ao aplicativo personalizado, o usuário escolhe sua congregação, campus ou filial. A Vinha procura um cadastro compatível na membresia. Quando encontra, cria o vínculo; quando não encontra, gera um novo cadastro pendente para aprovação do responsável da igreja.','aplicativo,membro,cadastro,conciliacao,campus',1,1,1791622800000,1791622800000),
('support-article-events','eventos-e-inscricoes','Eventos','Eventos, inscrições e pagamentos','Crie eventos gratuitos ou pagos e compartilhe o link público.','Cadastre os dados do evento, defina público e unidades, configure ingressos e publique. O link gerado aceita inscrições mesmo de pessoas sem conta. Eventos pagos usam o provedor financeiro conectado pela igreja e os recebimentos aparecem na conciliação do evento.','evento,inscricao,ticket,ingresso,pagamento,link',0,1,1791622800000,1791622800000),
('support-article-onboarding','configuracao-inicial','Configuração','Checklist de configuração inicial','Os passos essenciais para preparar a Vinha para sua equipe.','Comece pela identidade visual, dados da sede e unidades. Depois convide a equipe, defina papéis e permissões, importe os membros e conecte os provedores necessários. Por fim, revise o aplicativo, os termos e os modelos de comunicação antes de publicar.','configuracao,onboarding,importacao,equipe,permissoes',0,1,1791622800000,1791622800000);
