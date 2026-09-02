CREATE TABLE `event_media` (
	`id` text PRIMARY KEY NOT NULL,
	`church_id` text NOT NULL,
	`event_id` text NOT NULL,
	`object_key` text NOT NULL,
	`media_type` text DEFAULT 'gallery' NOT NULL,
	`alt_text` text,
	`sort_order` integer DEFAULT 0 NOT NULL,
	`content_type` text NOT NULL,
	`size_bytes` integer NOT NULL,
	`created_by_user_id` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`event_id`) REFERENCES `events`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `idx_event_media_object_key` ON `event_media` (`object_key`);
--> statement-breakpoint
CREATE INDEX `idx_event_media_event` ON `event_media` (`church_id`,`event_id`,`media_type`,`sort_order`);
--> statement-breakpoint
PRAGMA optimize;
