CREATE TABLE `child_guardians` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`child_id` text NOT NULL,
	`guardian_person_id` text NOT NULL,
	`relationship` text NOT NULL,
	`is_primary` integer DEFAULT false NOT NULL,
	`can_manage` integer DEFAULT true NOT NULL,
	`can_pickup` integer DEFAULT true NOT NULL,
	`linked_by_person_id` text,
	`verified_at` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`child_id`) REFERENCES `children`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`guardian_person_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_child_guardian_unique` ON `child_guardians` (`church_id`,`child_id`,`guardian_person_id`);--> statement-breakpoint
CREATE TABLE `children` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`person_id` text,
	`full_name` text NOT NULL,
	`birth_date` text NOT NULL,
	`gender` text,
	`photo_key` text,
	`allergies` text,
	`medical_notes` text,
	`special_needs` text,
	`created_by_person_id` text,
	`created_via` text DEFAULT 'admin' NOT NULL,
	`status` text DEFAULT 'active' NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`person_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
DROP INDEX `idx_person_consent_type`;--> statement-breakpoint
ALTER TABLE `person_consents` ADD `term_id` text;--> statement-breakpoint
ALTER TABLE `person_consents` ADD `accepted_by_person_id` text;--> statement-breakpoint
ALTER TABLE `person_consents` ADD `subject_person_id` text;--> statement-breakpoint
ALTER TABLE `person_consents` ADD `acceptance_snapshot` text;--> statement-breakpoint
ALTER TABLE `person_consents` ADD `ip_address` text;--> statement-breakpoint
ALTER TABLE `person_consents` ADD `user_agent` text;--> statement-breakpoint
CREATE INDEX `idx_person_consent_type` ON `person_consents` (`church_id`,`person_id`,`consent_type`);--> statement-breakpoint
ALTER TABLE `churches` ADD `senior_pastor_name` text DEFAULT 'Pastor titular' NOT NULL;--> statement-breakpoint
ALTER TABLE `churches` ADD `senior_pastor_cpf` text;