ALTER TABLE notification_channel_settings ADD COLUMN credential_ciphertext TEXT;
ALTER TABLE notification_channel_settings ADD COLUMN credential_iv TEXT;
ALTER TABLE notification_channel_settings ADD COLUMN credential_hint TEXT;
ALTER TABLE notification_channel_settings ADD COLUMN provider_config TEXT;
ALTER TABLE notification_channel_settings ADD COLUMN last_tested_at INTEGER;
ALTER TABLE notification_channel_settings ADD COLUMN last_test_status TEXT;
PRAGMA optimize;
