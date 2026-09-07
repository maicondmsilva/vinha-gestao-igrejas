CREATE TABLE `event_schedule_items` (`id` text PRIMARY KEY NOT NULL,`church_id` text NOT NULL,`event_id` text NOT NULL,`title` text NOT NULL,`description` text,`location` text,`starts_at` integer NOT NULL,`ends_at` integer,`sort_order` integer DEFAULT 0 NOT NULL,`created_at` integer NOT NULL,FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`),FOREIGN KEY (`event_id`) REFERENCES `events`(`id`));
--> statement-breakpoint
CREATE INDEX `idx_event_schedule_event` ON `event_schedule_items` (`church_id`,`event_id`,`starts_at`);
--> statement-breakpoint
CREATE TABLE `event_guests` (`id` text PRIMARY KEY NOT NULL,`church_id` text NOT NULL,`event_id` text NOT NULL,`name` text NOT NULL,`role` text,`biography` text,`profile_url` text,`sort_order` integer DEFAULT 0 NOT NULL,`created_at` integer NOT NULL,FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`),FOREIGN KEY (`event_id`) REFERENCES `events`(`id`));
--> statement-breakpoint
CREATE INDEX `idx_event_guests_event` ON `event_guests` (`church_id`,`event_id`,`sort_order`);
--> statement-breakpoint
CREATE TABLE `event_organizers` (`id` text PRIMARY KEY NOT NULL,`church_id` text NOT NULL,`event_id` text NOT NULL,`name` text NOT NULL,`role` text,`email` text,`phone` text,`created_at` integer NOT NULL,FOREIGN KEY (`church_id`) REFERENCES `churches`(`id`),FOREIGN KEY (`event_id`) REFERENCES `events`(`id`));
--> statement-breakpoint
CREATE INDEX `idx_event_organizers_event` ON `event_organizers` (`church_id`,`event_id`);
--> statement-breakpoint
PRAGMA optimize;
