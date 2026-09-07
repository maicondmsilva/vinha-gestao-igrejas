ALTER TABLE `event_payment_orders` ADD `fee_cents` integer DEFAULT 0 NOT NULL;
--> statement-breakpoint
ALTER TABLE `event_payment_orders` ADD `net_amount_cents` integer;
--> statement-breakpoint
ALTER TABLE `event_payment_orders` ADD `settled_at` integer;
--> statement-breakpoint
ALTER TABLE `event_payment_orders` ADD `reconciliation_status` text DEFAULT 'pending' NOT NULL;
--> statement-breakpoint
CREATE INDEX `idx_event_payment_reconciliation` ON `event_payment_orders` (`church_id`,`reconciliation_status`,`created_at`);
--> statement-breakpoint
PRAGMA optimize;
