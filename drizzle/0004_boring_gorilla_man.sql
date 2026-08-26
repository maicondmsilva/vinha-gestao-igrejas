CREATE TABLE `kids_checkins` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`session_id` text NOT NULL,
	`child_id` text NOT NULL,
	`checkin_guardian_id` text NOT NULL,
	`checkout_guardian_id` text,
	`checkin_by_user_id` text NOT NULL,
	`checkout_by_user_id` text,
	`security_code` text NOT NULL,
	`checked_in_at` integer NOT NULL,
	`checked_out_at` integer,
	`status` text DEFAULT 'checked_in' NOT NULL,
	`notes` text,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`session_id`) REFERENCES `kids_sessions`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`child_id`) REFERENCES `children`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`checkin_guardian_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`checkout_guardian_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_kids_checkin_session_child` ON `kids_checkins` (`church_id`,`session_id`,`child_id`);--> statement-breakpoint
CREATE TABLE `kids_rooms` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`name` text NOT NULL,
	`min_age_months` integer DEFAULT 0 NOT NULL,
	`max_age_months` integer DEFAULT 144 NOT NULL,
	`capacity` integer DEFAULT 20 NOT NULL,
	`location` text,
	`color` text DEFAULT '#4d8066' NOT NULL,
	`status` text DEFAULT 'active' NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `kids_sessions` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`room_id` text NOT NULL,
	`event_name` text NOT NULL,
	`starts_at` integer NOT NULL,
	`ends_at` integer,
	`status` text DEFAULT 'open' NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`room_id`) REFERENCES `kids_rooms`(`id`) ON UPDATE no action ON DELETE no action
);
