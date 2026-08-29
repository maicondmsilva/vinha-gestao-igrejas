CREATE TABLE `audit_logs` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`actor_user_id` text NOT NULL,
	`action` text NOT NULL,
	`entity_type` text NOT NULL,
	`entity_id` text,
	`metadata` text,
	`ip_address` text,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
ALTER TABLE `church_users` ADD `person_id` text;