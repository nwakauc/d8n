-- Cleanup for a real bug: the photo-transfer rake task ran without
-- D8N_R2_ENABLED=true, so Media::StorageResolver fell back to the local
-- test-disk storage service instead of real R2. The resulting
-- ProfilePhoto/active_storage_blob/attachment rows reference a "test"
-- service that doesn't exist in production and would fail to load. The
-- underlying photo bytes are safe (already transferred to real R2 under
-- the legacy key by scripts/date9ja/transfer_media_bytes.rb) -- only this
-- broken re-upload step needs to be redone with the correct config.
BEGIN;

DELETE FROM active_storage_attachments
WHERE blob_id IN (SELECT id FROM active_storage_blobs WHERE service_name = 'test');

DELETE FROM active_storage_blobs WHERE service_name = 'test';

DELETE FROM legacy_references
WHERE destination_type IN ('ProfilePhoto', 'ProfileVideo')
  AND source_entity IN ('photo', 'profile_video');

DELETE FROM profile_photos WHERE brand_id = 2;
DELETE FROM profile_videos WHERE brand_id = 2;

\echo Remaining broken rows (should all be 0):
SELECT 'active_storage_blobs (test service)' t, count(*) FROM active_storage_blobs WHERE service_name = 'test'
UNION ALL SELECT 'profile_photos', count(*) FROM profile_photos WHERE brand_id = 2
UNION ALL SELECT 'profile_videos', count(*) FROM profile_videos WHERE brand_id = 2
UNION ALL SELECT 'dangling legacy_references', count(*) FROM legacy_references WHERE destination_type IN ('ProfilePhoto', 'ProfileVideo');

\echo DateZA sanity check (must be unchanged):
SELECT count(*) FROM profiles WHERE brand_id = 1;

COMMIT;
