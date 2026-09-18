-- Run on STAGING (d8n-staging-db). Read-only against staging.
-- Rebuilds the EXACT same id mapping used by the original batch-of-30 and
-- founder exports (same source queries/order/offsets), so profile_preferences
-- rows land against the correct already-imported profile/user ids.
-- production.profile_preferences max was 949 as of this run.

-- Batch of 30 (matches scratch_hookus_export.sql exactly)
CREATE TEMP TABLE map_users_batch AS
SELECT u.id AS old_id, 952 + row_number() OVER (ORDER BY u.id) AS new_id
FROM users u
JOIN brand_memberships bm ON bm.user_id = u.id
JOIN brands b ON b.id = bm.brand_id AND b.slug = 'hookus'
WHERE u.created_at >= '2026-09-14';

CREATE TEMP TABLE map_profiles_batch AS
SELECT p.id AS old_id, 947 + row_number() OVER (ORDER BY p.id) AS new_id
FROM profiles p
JOIN map_users_batch mu ON mu.old_id = p.user_id;

-- Founder (matches scratch_hookus_founder_export.sql exactly)
CREATE TEMP TABLE map_users_founder AS
SELECT 3120::bigint AS old_id, 983::bigint AS new_id;

CREATE TEMP TABLE map_profiles_founder AS
SELECT p.id AS old_id, 973 + row_number() OVER (ORDER BY p.id) AS new_id
FROM profiles p
JOIN map_users_founder mu ON mu.old_id = p.user_id;

-- Combined
CREATE TEMP TABLE map_users AS
SELECT * FROM map_users_batch UNION ALL SELECT * FROM map_users_founder;

CREATE TEMP TABLE map_profiles AS
SELECT * FROM map_profiles_batch UNION ALL SELECT * FROM map_profiles_founder;

CREATE TEMP TABLE map_preferences AS
SELECT pp.id AS old_id, 949 + row_number() OVER (ORDER BY pp.id) AS new_id
FROM profile_preferences pp
JOIN map_profiles mp ON mp.old_id = pp.profile_id;

\echo '--- verify: reconstructed profile mapping must match what is already in production ---'
SELECT old_id, new_id FROM map_profiles ORDER BY new_id;

\echo '--- count (sanity check) ---'
SELECT count(*) FROM map_preferences;

\echo '--- BEGIN GENERATED SQL ---'
SELECT 'BEGIN;';

SELECT format(
  'INSERT INTO profile_preferences (id, profile_id, user_id, brand_id, min_age, max_age, interested_in, max_distance_km, country, relationship_intent, metadata, deleted_at, created_at, updated_at, preferred_country_codes, preferred_attributes) VALUES (%s, %s, %s, 3, %s, %s, %L, %s, %s, %s, %L, %s, %s, %s, %L, %L);',
  mpp.new_id, mp.new_id, mu.new_id, pp.min_age, pp.max_age, pp.interested_in::text, pp.max_distance_km,
  quote_nullable(pp.country), quote_nullable(pp.relationship_intent), pp.metadata::text,
  quote_nullable(pp.deleted_at), quote_literal(pp.created_at), quote_literal(pp.updated_at),
  '[]', '{}'
)
FROM profile_preferences pp
JOIN map_preferences mpp ON mpp.old_id = pp.id
JOIN map_profiles mp ON mp.old_id = pp.profile_id
JOIN map_users mu ON mu.old_id = pp.user_id
ORDER BY mpp.new_id;

SELECT format('SELECT setval(''profile_preferences_id_seq'', %s, true);', max(mpp.new_id))
FROM map_preferences mpp;

SELECT 'COMMIT;';
\echo '--- END GENERATED SQL ---'
