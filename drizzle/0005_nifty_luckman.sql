CREATE TABLE `guardian_calls` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`checkin_id` text NOT NULL,
	`guardian_person_id` text NOT NULL,
	`reason` text NOT NULL,
	`status` text DEFAULT 'sent' NOT NULL,
	`channel` text DEFAULT 'app' NOT NULL,
	`sent_at` integer NOT NULL,
	`acknowledged_at` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`checkin_id`) REFERENCES `kids_checkins`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`guardian_person_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `kids_incidents` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`session_id` text NOT NULL,
	`child_id` text NOT NULL,
	`category` text NOT NULL,
	`description` text NOT NULL,
	`severity` text DEFAULT 'low' NOT NULL,
	`guardian_notified` integer DEFAULT false NOT NULL,
	`recorded_by_user_id` text NOT NULL,
	`occurred_at` integer NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`session_id`) REFERENCES `kids_sessions`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`child_id`) REFERENCES `children`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `kids_room_volunteers` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`session_id` text NOT NULL,
	`person_id` text NOT NULL,
	`role` text DEFAULT 'Voluntário' NOT NULL,
	`checked_in_at` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`session_id`) REFERENCES `kids_sessions`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`person_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_kids_volunteer_session` ON `kids_room_volunteers` (`church_id`,`session_id`,`person_id`);