CREATE TABLE `saas_module_catalog` (`code` text PRIMARY KEY NOT NULL,`name` text NOT NULL,`description` text,`monthly_price_cents` integer DEFAULT 0 NOT NULL,`active` integer DEFAULT 1 NOT NULL,`created_at` integer NOT NULL,`updated_at` integer NOT NULL);
--> statement-breakpoint
CREATE TABLE `saas_plan_modules` (`plan_id` text NOT NULL,`module_code` text NOT NULL,`included` integer DEFAULT 1 NOT NULL,`created_at` integer NOT NULL,PRIMARY KEY(`plan_id`,`module_code`),FOREIGN KEY (`plan_id`) REFERENCES `saas_plans`(`id`),FOREIGN KEY (`module_code`) REFERENCES `saas_module_catalog`(`code`));
--> statement-breakpoint
CREATE INDEX `idx_saas_plan_modules_code` ON `saas_plan_modules` (`module_code`);
--> statement-breakpoint
CREATE TABLE `saas_promotions` (`id` text PRIMARY KEY NOT NULL,`code` text NOT NULL,`name` text NOT NULL,`discount_type` text NOT NULL,`discount_value` integer NOT NULL,`starts_at` integer,`ends_at` integer,`max_redemptions` integer,`active` integer DEFAULT 1 NOT NULL,`created_at` integer NOT NULL,`updated_at` integer NOT NULL);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_saas_promotions_code` ON `saas_promotions` (`code`);
--> statement-breakpoint
CREATE INDEX `idx_saas_promotions_active_period` ON `saas_promotions` (`active`,`starts_at`,`ends_at`);
--> statement-breakpoint
CREATE TABLE `saas_subscription_discounts` (`subscription_id` text PRIMARY KEY NOT NULL,`promotion_id` text,`custom_percent` integer DEFAULT 0 NOT NULL,`custom_amount_cents` integer DEFAULT 0 NOT NULL,`valid_until` integer,`created_at` integer NOT NULL,`updated_at` integer NOT NULL,FOREIGN KEY (`subscription_id`) REFERENCES `saas_subscriptions`(`id`),FOREIGN KEY (`promotion_id`) REFERENCES `saas_promotions`(`id`));
--> statement-breakpoint
CREATE INDEX `idx_saas_subscription_discounts_promotion` ON `saas_subscription_discounts` (`promotion_id`);
--> statement-breakpoint
INSERT INTO `saas_module_catalog` (`code`,`name`,`description`,`monthly_price_cents`,`active`,`created_at`,`updated_at`) VALUES
('people','Membresia','Cadastro, famílias e jornada do membro',4900,1,unixepoch()*1000,unixepoch()*1000),('finance','Financeiro','Tesouraria, conciliação e contabilidade',6900,1,unixepoch()*1000,unixepoch()*1000),('cells','Células','Células, grupos e acompanhamento',3900,1,unixepoch()*1000,unixepoch()*1000),('kids','Kids','Check-in, responsáveis e segurança',4900,1,unixepoch()*1000,unixepoch()*1000),('events','Eventos','Eventos, inscrições e tickets',5900,1,unixepoch()*1000,unixepoch()*1000),('scales','Escalas','Escalas integradas de ministérios',3900,1,unixepoch()*1000,unixepoch()*1000),('worship','Louvor','Repertório, cifras e planejamento',4900,1,unixepoch()*1000,unixepoch()*1000),('communication','Comunicação','Canais, chat e notificações',3900,1,unixepoch()*1000,unixepoch()*1000),('broadcasts','Transmissões','Lives, audiência e moderação',5900,1,unixepoch()*1000,unixepoch()*1000),('reports','Relatórios','Indicadores e exportações',2900,1,unixepoch()*1000,unixepoch()*1000),('terms','Termos e consentimentos','Documentos, aceite e auditoria',2900,1,unixepoch()*1000,unixepoch()*1000),('custom_app','Aplicativo personalizado','Aplicativo próprio publicado nas lojas',9900,1,unixepoch()*1000,unixepoch()*1000);
