CREATE TABLE `church_users` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`external_user_id` text NOT NULL,
	`email` text NOT NULL,
	`name` text NOT NULL,
	`role` text DEFAULT 'member' NOT NULL,
	`status` text DEFAULT 'active' NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_church_users_tenant_external` ON `church_users` (`church_id`,`external_user_id`);--> statement-breakpoint
CREATE TABLE `churches` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`app_name` text NOT NULL,
	`slug` text NOT NULL,
	`primary_color` text DEFAULT '#285c45' NOT NULL,
	`accent_color` text DEFAULT '#d8b769' NOT NULL,
	`logo_key` text,
	`opening_video_key` text,
	`created_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_churches_slug` ON `churches` (`slug`);--> statement-breakpoint
CREATE TABLE `families` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`name` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `people` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`family_id` text,
	`full_name` text NOT NULL,
	`email` text,
	`phone` text,
	`journey_status` text DEFAULT 'visitor' NOT NULL,
	`group_name` text,
	`joined_at` integer,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`family_id`) REFERENCES `families`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_people_tenant_email` ON `people` (`church_id`,`email`);