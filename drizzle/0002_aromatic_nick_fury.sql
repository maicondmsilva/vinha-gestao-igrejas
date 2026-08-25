CREATE TABLE `consent_terms` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`consent_type` text NOT NULL,
	`title` text NOT NULL,
	`version` text NOT NULL,
	`content` text NOT NULL,
	`effective_at` integer NOT NULL,
	`active` integer DEFAULT true NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_consent_term_version` ON `consent_terms` (`church_id`,`consent_type`,`version`);--> statement-breakpoint
CREATE TABLE `family_members` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`family_id` text NOT NULL,
	`person_id` text NOT NULL,
	`relationship` text NOT NULL,
	`is_guardian` integer DEFAULT false NOT NULL,
	`can_pickup_minor` integer DEFAULT false NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`family_id`) REFERENCES `families`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_family_member_unique` ON `family_members` (`church_id`,`family_id`,`person_id`);