CREATE TABLE `custom_field_definitions` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`label` text NOT NULL,
	`field_type` text DEFAULT 'text' NOT NULL,
	`required` integer DEFAULT false NOT NULL,
	`options` text,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `emergency_contacts` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`person_id` text NOT NULL,
	`name` text NOT NULL,
	`relationship` text,
	`phone` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`person_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `pastoral_notes` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`person_id` text NOT NULL,
	`author_user_id` text NOT NULL,
	`content` text NOT NULL,
	`visibility` text DEFAULT 'pastoral' NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`person_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `person_addresses` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`person_id` text NOT NULL,
	`postal_code` text,
	`street` text,
	`number` text,
	`complement` text,
	`district` text,
	`city` text,
	`state` text,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`person_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_person_addresses_person` ON `person_addresses` (`church_id`,`person_id`);--> statement-breakpoint
CREATE TABLE `person_consents` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`person_id` text NOT NULL,
	`consent_type` text NOT NULL,
	`granted` integer NOT NULL,
	`source` text DEFAULT 'admin' NOT NULL,
	`granted_at` integer,
	`revoked_at` integer,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`person_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_person_consent_type` ON `person_consents` (`church_id`,`person_id`,`consent_type`);--> statement-breakpoint
CREATE TABLE `person_custom_field_values` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`person_id` text NOT NULL,
	`field_id` text NOT NULL,
	`value` text,
	`updated_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`person_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`field_id`) REFERENCES `custom_field_definitions`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_person_custom_field` ON `person_custom_field_values` (`church_id`,`person_id`,`field_id`);--> statement-breakpoint
CREATE TABLE `person_ministries` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`person_id` text NOT NULL,
	`ministry_name` text NOT NULL,
	`function_name` text,
	`status` text DEFAULT 'active' NOT NULL,
	`started_at` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`person_id`) REFERENCES `people`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_person_ministry_unique` ON `person_ministries` (`church_id`,`person_id`,`ministry_name`);--> statement-breakpoint
ALTER TABLE `people` ADD `photo_key` text;--> statement-breakpoint
ALTER TABLE `people` ADD `birth_date` text;--> statement-breakpoint
ALTER TABLE `people` ADD `gender` text;--> statement-breakpoint
ALTER TABLE `people` ADD `marital_status` text;--> statement-breakpoint
ALTER TABLE `people` ADD `cpf` text;--> statement-breakpoint
ALTER TABLE `people` ADD `family_relationship` text;--> statement-breakpoint
ALTER TABLE `people` ADD `campus` text;--> statement-breakpoint
ALTER TABLE `people` ADD `first_visit_at` integer;--> statement-breakpoint
ALTER TABLE `people` ADD `baptized` integer DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE `people` ADD `baptism_date` text;--> statement-breakpoint
ALTER TABLE `people` ADD `tags` text DEFAULT '[]' NOT NULL;--> statement-breakpoint
ALTER TABLE `people` ADD `app_role` text DEFAULT 'member' NOT NULL;--> statement-breakpoint
ALTER TABLE `people` ADD `status` text DEFAULT 'active' NOT NULL;