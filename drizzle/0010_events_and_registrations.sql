CREATE TABLE `events` (
	`id` text PRIMARY KEY NOT NULL, `church_id` text NOT NULL, `unit_id` text, `created_by_user_id` text NOT NULL,
	`title` text NOT NULL, `public_slug` text NOT NULL, `description` text NOT NULL, `category` text DEFAULT 'Geral' NOT NULL,
	`format` text DEFAULT 'presential' NOT NULL, `location_name` text, `address` text, `online_url` text,
	`starts_at` integer NOT NULL, `ends_at` integer NOT NULL, `scope` text DEFAULT 'unit' NOT NULL,
	`registration_mode` text DEFAULT 'public' NOT NULL, `capacity` integer, `status` text DEFAULT 'draft' NOT NULL,
	`published_at` integer, `created_at` integer NOT NULL, `updated_at` integer,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`), FOREIGN KEY (`unit_id`) REFERENCES `church_units`(`id`), FOREIGN KEY (`created_by_user_id`) REFERENCES `church_users`(`id`)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_events_public_slug` ON `events` (`public_slug`);
--> statement-breakpoint
CREATE INDEX `idx_events_church_unit_start` ON `events` (`church_id`,`unit_id`,`starts_at`);
--> statement-breakpoint
CREATE TABLE `event_tickets` (
	`id` text PRIMARY KEY NOT NULL, `church_id` text NOT NULL, `event_id` text NOT NULL, `name` text NOT NULL,
	`price_cents` integer DEFAULT 0 NOT NULL, `quantity` integer, `sales_start_at` integer, `sales_end_at` integer,
	`status` text DEFAULT 'active' NOT NULL, `created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`), FOREIGN KEY (`event_id`) REFERENCES `events`(`id`)
);
--> statement-breakpoint
CREATE INDEX `idx_event_tickets_event` ON `event_tickets` (`church_id`,`event_id`);
--> statement-breakpoint
CREATE TABLE `event_registrations` (
	`id` text PRIMARY KEY NOT NULL, `church_id` text NOT NULL, `event_id` text NOT NULL, `ticket_id` text NOT NULL,
	`person_id` text, `full_name` text NOT NULL, `email` text NOT NULL, `phone` text, `document` text,
	`quantity` integer DEFAULT 1 NOT NULL, `amount_cents` integer DEFAULT 0 NOT NULL,
	`payment_status` text DEFAULT 'not_required' NOT NULL, `registration_status` text DEFAULT 'confirmed' NOT NULL,
	`checkin_token` text NOT NULL, `checked_in_at` integer, `consent_snapshot` text, `created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`), FOREIGN KEY (`event_id`) REFERENCES `events`(`id`),
	FOREIGN KEY (`ticket_id`) REFERENCES `event_tickets`(`id`), FOREIGN KEY (`person_id`) REFERENCES `people`(`id`)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_event_registration_token` ON `event_registrations` (`checkin_token`);
--> statement-breakpoint
CREATE INDEX `idx_event_registration_event` ON `event_registrations` (`church_id`,`event_id`);
--> statement-breakpoint
PRAGMA optimize;
