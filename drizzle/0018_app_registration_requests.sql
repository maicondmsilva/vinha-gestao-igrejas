CREATE TABLE `app_registration_requests` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`unit_id` text NOT NULL,
	`external_user_id` text NOT NULL,
	`matched_person_id` text,
	`full_name` text NOT NULL,
	`cpf` text,
	`email` text NOT NULL,
	`phone` text NOT NULL,
	`birth_date` text,
	`theme_preference` text DEFAULT 'system' NOT NULL,
	`status` text DEFAULT 'new_pending' NOT NULL,
	`match_score` integer DEFAULT 0 NOT NULL,
	`match_reason` text,
	`requested_at` integer NOT NULL,
	`reviewed_by_user_id` text,
	`reviewed_at` integer,
	`decision_note` text,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`unit_id`) REFERENCES `church_units`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`matched_person_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_app_registration_external` ON `app_registration_requests` (`church_id`,`external_user_id`);--> statement-breakpoint
CREATE INDEX `idx_app_registration_queue` ON `app_registration_requests` (`church_id`,`unit_id`,`status`,`requested_at`);
