CREATE TABLE `church_units` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`parent_unit_id` text,
	`name` text NOT NULL,
	`type` text DEFAULT 'campus' NOT NULL,
	`slug` text NOT NULL,
	`legal_name` text,
	`tax_id` text,
	`pastor_name` text,
	`email` text,
	`phone` text,
	`postal_code` text,
	`street` text,
	`number` text,
	`complement` text,
	`district` text,
	`city` text,
	`state` text,
	`financial_autonomy` integer DEFAULT false NOT NULL,
	`communication_autonomy` integer DEFAULT true NOT NULL,
	`branding_autonomy` integer DEFAULT false NOT NULL,
	`status` text DEFAULT 'active' NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_church_units_slug` ON `church_units` (`church_id`,`slug`);
--> statement-breakpoint
CREATE INDEX `idx_church_units_parent` ON `church_units` (`church_id`,`parent_unit_id`);
--> statement-breakpoint
CREATE TABLE `user_unit_access` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`user_id` text NOT NULL,
	`unit_id` text NOT NULL,
	`role` text DEFAULT 'viewer' NOT NULL,
	`include_children` integer DEFAULT false NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`user_id`) REFERENCES `church_users`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`unit_id`) REFERENCES `church_units`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_user_unit_access_unique` ON `user_unit_access` (`church_id`,`user_id`,`unit_id`);
--> statement-breakpoint
CREATE INDEX `idx_user_unit_access_user` ON `user_unit_access` (`church_id`,`user_id`);
--> statement-breakpoint
PRAGMA optimize;
