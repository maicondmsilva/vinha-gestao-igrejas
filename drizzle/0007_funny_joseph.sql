PRAGMA foreign_keys=OFF;--> statement-breakpoint
CREATE TABLE `__new_kids_checkins` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`session_id` text NOT NULL,
	`child_id` text NOT NULL,
	`checkin_guardian_id` text NOT NULL,
	`checkout_guardian_id` text,
	`checkin_by_user_id` text NOT NULL,
	`checkout_by_user_id` text,
	`security_code` text NOT NULL,
	`label_token` text DEFAULT '' NOT NULL,
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
INSERT INTO `__new_kids_checkins`("id", "church_id", "session_id", "child_id", "checkin_guardian_id", "checkout_guardian_id", "checkin_by_user_id", "checkout_by_user_id", "security_code", "label_token", "checked_in_at", "checked_out_at", "status", "notes", "created_at") SELECT "id", "church_id", "session_id", "child_id", "checkin_guardian_id", "checkout_guardian_id", "checkin_by_user_id", "checkout_by_user_id", "security_code", "label_token", "checked_in_at", "checked_out_at", "status", "notes", "created_at" FROM `kids_checkins`;--> statement-breakpoint
DROP TABLE `kids_checkins`;--> statement-breakpoint
ALTER TABLE `__new_kids_checkins` RENAME TO `kids_checkins`;--> statement-breakpoint
PRAGMA foreign_keys=ON;--> statement-breakpoint
CREATE UNIQUE INDEX `idx_kids_checkin_session_child` ON `kids_checkins` (`church_id`,`session_id`,`child_id`);