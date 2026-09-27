CREATE TABLE `saas_plans` (
 `id` text PRIMARY KEY NOT NULL,
 `code` text NOT NULL,
 `name` text NOT NULL,
 `description` text,
 `base_price_cents` integer DEFAULT 0 NOT NULL,
 `billing_cycle` text DEFAULT 'monthly' NOT NULL,
 `active` integer DEFAULT 1 NOT NULL,
 `created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_saas_plans_code` ON `saas_plans` (`code`);
--> statement-breakpoint
CREATE TABLE `saas_subscriptions` (
 `id` text PRIMARY KEY NOT NULL,
 `church_id` text NOT NULL,
 `plan_id` text NOT NULL,
 `status` text DEFAULT 'trialing' NOT NULL,
 `app_addon` integer DEFAULT 0 NOT NULL,
 `trial_ends_at` integer,
 `current_period_end` integer,
 `created_at` integer NOT NULL,
 `updated_at` integer NOT NULL,
 FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
 FOREIGN KEY (`plan_id`) REFERENCES `saas_plans`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_saas_subscription_church` ON `saas_subscriptions` (`church_id`);
--> statement-breakpoint
CREATE TABLE `saas_subscription_modules` (
 `id` text PRIMARY KEY NOT NULL,
 `subscription_id` text NOT NULL,
 `module_code` text NOT NULL,
 `enabled` integer DEFAULT 1 NOT NULL,
 `limit_value` integer,
 `created_at` integer NOT NULL,
 FOREIGN KEY (`subscription_id`) REFERENCES `saas_subscriptions`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_saas_subscription_module` ON `saas_subscription_modules` (`subscription_id`,`module_code`);
--> statement-breakpoint
INSERT INTO `saas_plans` (`id`,`code`,`name`,`description`,`base_price_cents`,`billing_cycle`,`active`,`created_at`) VALUES
 ('plan-essential','essential','Essencial','Membresia, unidades e comunicação básica',14900,'monthly',1,unixepoch()*1000),
 ('plan-management','management','Gestão','Operação integrada da igreja e seus ministérios',29900,'monthly',1,unixepoch()*1000),
 ('plan-complete','complete','Completo','Todos os módulos e recursos avançados',49900,'monthly',1,unixepoch()*1000);
