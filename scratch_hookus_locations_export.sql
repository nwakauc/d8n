-- Run on STAGING (d8n-staging-db). Read-only against staging. Reuses the
-- EXACT same id-mapping logic/offsets as scratch_hookus_export.sql so the
-- new profile_locations rows line up with the profiles/users already
-- promoted to production. Prints ready-to-run INSERT statements only.

CREATE TEMP TABLE map_users AS
SELECT u.id AS old_id, 952 + row_number() OVER (ORDER BY u.id) AS new_id
FROM users u
JOIN brand_memberships bm ON bm.user_id = u.id
JOIN brands b ON b.id = bm.brand_id AND b.slug = 'hookus'
WHERE u.created_at >= '2026-09-14';

CREATE TEMP TABLE map_profiles AS
SELECT p.id AS old_id, 947 + row_number() OVER (ORDER BY p.id) AS new_id
FROM profiles p
JOIN map_users mu ON mu.old_id = p.user_id;

CREATE TEMP TABLE map_profile_locations AS
SELECT pl.id AS old_id, 61 + row_number() OVER (ORDER BY pl.id) AS new_id
FROM profile_locations pl
JOIN map_profiles mp ON mp.old_id = pl.profile_id
WHERE pl.deleted_at IS NULL;

\echo '--- count (sanity check) ---'
SELECT count(*) FROM map_profile_locations;

\echo '--- BEGIN GENERATED SQL ---'
SELECT 'BEGIN;';

SELECT format(
  'INSERT INTO profile_locations (id, profile_id, user_id, brand_id, latitude, longitude, accuracy_meters, source, captured_at, deleted_at, created_at, updated_at, place_id) VALUES (%s, %s, %s, 3, %s, %s, %s, %L, %s, %s, %s, %s, NULL);',
  mpl.new_id, mp.new_id, mu.new_id, pl.latitude, pl.longitude, pl.accuracy_meters, pl.source,
  quote_literal(pl.captured_at), quote_nullable(pl.deleted_at), quote_literal(pl.created_at), quote_literal(pl.updated_at)
)
FROM profile_locations pl
JOIN map_profile_locations mpl ON mpl.old_id = pl.id
JOIN map_profiles mp ON mp.old_id = pl.profile_id
JOIN map_users mu ON mu.old_id = pl.user_id
ORDER BY mpl.new_id;

SELECT format(
  'SELECT setval(pg_get_serial_sequence(''profile_locations'',''id''), %s, true);',
  max(mpl.new_id)
) FROM map_profile_locations mpl;

SELECT 'COMMIT;';
\echo '--- END GENERATED SQL ---'
