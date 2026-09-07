ALTER TABLE `payment_provider_settings` ADD `credential_ciphertext` text;
--> statement-breakpoint
ALTER TABLE `payment_provider_settings` ADD `credential_iv` text;
--> statement-breakpoint
ALTER TABLE `payment_provider_settings` ADD `credential_hint` text;
--> statement-breakpoint
ALTER TABLE `payment_provider_settings` ADD `webhook_token_ciphertext` text;
--> statement-breakpoint
ALTER TABLE `payment_provider_settings` ADD `webhook_token_iv` text;
--> statement-breakpoint
ALTER TABLE `payment_provider_settings` ADD `last_tested_at` integer;
--> statement-breakpoint
ALTER TABLE `payment_provider_settings` ADD `last_test_status` text;
