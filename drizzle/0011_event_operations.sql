CREATE TABLE `event_coupons` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`event_id` text NOT NULL,
	`code` text NOT NULL,
	`discount_type` text DEFAULT 'percent' NOT NULL,
	`discount_value` integer NOT NULL,
	`max_uses` integer,
	`used_count` integer DEFAULT 0 NOT NULL,
	`starts_at` integer,
	`ends_at` integer,
	`status` text DEFAULT 'active' NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`event_id`) REFERENCES `events`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_event_coupon_code` ON `event_coupons` (`church_id`,`event_id`,`code`);--> statement-breakpoint
CREATE INDEX `idx_event_coupons_event` ON `event_coupons` (`church_id`,`event_id`);
