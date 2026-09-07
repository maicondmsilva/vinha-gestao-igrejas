CREATE TABLE `event_payment_orders` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`event_id` text NOT NULL,
	`registration_id` text NOT NULL,
	`provider` text NOT NULL,
	`payment_method` text DEFAULT 'all' NOT NULL,
	`amount_cents` integer NOT NULL,
	`currency` text DEFAULT 'BRL' NOT NULL,
	`provider_payment_id` text,
	`checkout_url` text,
	`status` text DEFAULT 'created' NOT NULL,
	`expires_at` integer,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`event_id`) REFERENCES `events`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`registration_id`) REFERENCES `event_registrations`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_event_payment_registration` ON `event_payment_orders` (`registration_id`);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_event_payment_provider_id` ON `event_payment_orders` (`provider`,`provider_payment_id`);
--> statement-breakpoint
CREATE INDEX `idx_event_payment_church_status` ON `event_payment_orders` (`church_id`,`status`);
--> statement-breakpoint
CREATE TABLE `payment_webhook_events` (
	`id` text PRIMARY KEY NOT NULL,
	`provider` text NOT NULL,
	`external_event_id` text NOT NULL,
	`event_type` text,
	`status` text DEFAULT 'received' NOT NULL,
	`payload` text,
	`received_at` integer NOT NULL,
	`processed_at` integer
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_payment_webhook_provider_event` ON `payment_webhook_events` (`provider`,`external_event_id`);
--> statement-breakpoint
PRAGMA optimize;
