CREATE TABLE `payment_provider_settings` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`provider` text NOT NULL,
	`display_name` text NOT NULL,
	`account_reference` text,
	`environment` text DEFAULT 'sandbox' NOT NULL,
	`methods` text DEFAULT '[]' NOT NULL,
	`status` text DEFAULT 'not_configured' NOT NULL,
	`is_primary` integer DEFAULT false NOT NULL,
	`updated_by_user_id` text NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_payment_provider_church` ON `payment_provider_settings` (`church_id`,`provider`);--> statement-breakpoint
CREATE INDEX `idx_payment_provider_primary` ON `payment_provider_settings` (`church_id`,`is_primary`);
