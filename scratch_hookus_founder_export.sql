-- Run on STAGING (d8n-staging-db). Read-only against staging. One-off
-- addition for a single known-real user (id 3120, verified by the founder
-- as their own account). Same mapping/generation pattern as the batch-of-30
-- export, offsets set past production's current max as of this run.

CREATE TEMP TABLE map_users AS
SELECT 3120::bigint AS old_id, 983::bigint AS new_id;

CREATE TEMP TABLE map_identity_identifiers AS
SELECT ii.id AS old_id, 1606 + row_number() OVER (ORDER BY ii.id) AS new_id
FROM identity_identifiers ii
JOIN map_users mu ON mu.old_id = ii.user_id;

CREATE TEMP TABLE map_credentials AS
SELECT c.id AS old_id, 926 + row_number() OVER (ORDER BY c.id) AS new_id
FROM credentials c
JOIN map_identity_identifiers mii ON mii.old_id = c.identity_identifier_id;

CREATE TEMP TABLE map_brand_memberships AS
SELECT bm.id AS old_id, 981 + row_number() OVER (ORDER BY bm.id) AS new_id
FROM brand_memberships bm
JOIN map_users mu ON mu.old_id = bm.user_id;

CREATE TEMP TABLE map_profiles AS
SELECT p.id AS old_id, 973 + row_number() OVER (ORDER BY p.id) AS new_id
FROM profiles p
JOIN map_users mu ON mu.old_id = p.user_id;

CREATE TEMP TABLE map_profile_photos AS
SELECT pp.id AS old_id, 1628 + row_number() OVER (ORDER BY pp.id) AS new_id
FROM profile_photos pp
JOIN map_profiles mp ON mp.old_id = pp.profile_id;

CREATE TEMP TABLE map_blobs AS
SELECT DISTINCT asb.id AS old_id, 3618 + row_number() OVER (ORDER BY asb.id) AS new_id
FROM active_storage_blobs asb
JOIN active_storage_attachments asa ON asa.blob_id = asb.id
JOIN map_profile_photos mpp ON mpp.old_id = asa.record_id AND asa.record_type = 'ProfilePhoto';

CREATE TEMP TABLE map_attachments AS
SELECT asa.id AS old_id, 3581 + row_number() OVER (ORDER BY asa.id) AS new_id
FROM active_storage_attachments asa
JOIN map_profile_photos mpp ON mpp.old_id = asa.record_id AND asa.record_type = 'ProfilePhoto';

CREATE TEMP TABLE map_profile_locations AS
SELECT pl.id AS old_id, 77 + row_number() OVER (ORDER BY pl.id) AS new_id
FROM profile_locations pl
JOIN map_profiles mp ON mp.old_id = pl.profile_id
WHERE pl.deleted_at IS NULL;

\echo '--- counts (sanity check) ---'
SELECT 'users' t, count(*) FROM map_users
UNION ALL SELECT 'identity_identifiers', count(*) FROM map_identity_identifiers
UNION ALL SELECT 'credentials', count(*) FROM map_credentials
UNION ALL SELECT 'brand_memberships', count(*) FROM map_brand_memberships
UNION ALL SELECT 'profiles', count(*) FROM map_profiles
UNION ALL SELECT 'profile_photos', count(*) FROM map_profile_photos
UNION ALL SELECT 'active_storage_blobs', count(*) FROM map_blobs
UNION ALL SELECT 'active_storage_attachments', count(*) FROM map_attachments
UNION ALL SELECT 'profile_locations', count(*) FROM map_profile_locations;

\echo '--- BEGIN GENERATED SQL ---'
SELECT 'BEGIN;';

SELECT format(
  'INSERT INTO users (id, status, deleted_at, created_at, updated_at, first_name, last_name, metadata) VALUES (%s, %s, %s, %s, %s, %s, %s, %L);',
  mu.new_id, u.status, quote_nullable(u.deleted_at), quote_literal(u.created_at), quote_literal(u.updated_at),
  quote_nullable(u.first_name), quote_nullable(u.last_name), '{}'
)
FROM users u JOIN map_users mu ON mu.old_id = u.id;

SELECT format(
  'INSERT INTO identity_identifiers (id, user_id, kind, normalized_value, verified_at, last_seen_at, metadata, deleted_at, created_at, updated_at, brand_id) VALUES (%s, %s, %s, %L, %s, %s, %L, %s, %s, %s, 3);',
  mii.new_id, mu.new_id, ii.kind, ii.normalized_value, quote_nullable(ii.verified_at), quote_nullable(ii.last_seen_at),
  ii.metadata::text, quote_nullable(ii.deleted_at), quote_literal(ii.created_at), quote_literal(ii.updated_at)
)
FROM identity_identifiers ii
JOIN map_identity_identifiers mii ON mii.old_id = ii.id
JOIN map_users mu ON mu.old_id = ii.user_id
ORDER BY mii.new_id;

SELECT format(
  'INSERT INTO credentials (id, user_id, identity_identifier_id, kind, status, verified_at, last_used_at, metadata, deleted_at, created_at, updated_at) VALUES (%s, %s, %s, %s, %s, %s, %s, %L, %s, %s, %s);',
  mc.new_id, mu.new_id, mii.new_id, c.kind, c.status, quote_nullable(c.verified_at), quote_nullable(c.last_used_at),
  c.metadata::text, quote_nullable(c.deleted_at), quote_literal(c.created_at), quote_literal(c.updated_at)
)
FROM credentials c
JOIN map_credentials mc ON mc.old_id = c.id
JOIN map_identity_identifiers mii ON mii.old_id = c.identity_identifier_id
JOIN map_users mu ON mu.old_id = c.user_id
ORDER BY mc.new_id;

SELECT format(
  'INSERT INTO credential_password_hashes (credential_id, credential_kind, password_hash, password_changed_at, created_at, updated_at) VALUES (%s, %s, %L, %s, %s, %s);',
  mc.new_id, cph.credential_kind, cph.password_hash, quote_literal(cph.password_changed_at),
  quote_literal(cph.created_at), quote_literal(cph.updated_at)
)
FROM credential_password_hashes cph
JOIN map_credentials mc ON mc.old_id = cph.credential_id
ORDER BY mc.new_id;

SELECT format(
  'INSERT INTO brand_memberships (id, user_id, brand_id, status, deleted_at, created_at, updated_at) VALUES (%s, %s, 3, %s, %s, %s, %s);',
  mbm.new_id, mu.new_id, bm.status, quote_nullable(bm.deleted_at), quote_literal(bm.created_at), quote_literal(bm.updated_at)
)
FROM brand_memberships bm
JOIN map_brand_memberships mbm ON mbm.old_id = bm.id
JOIN map_users mu ON mu.old_id = bm.user_id
ORDER BY mbm.new_id;

SELECT format(
  'INSERT INTO profiles (id, user_id, brand_id, brand_membership_id, display_name, bio, birthdate, gender, status, visibility, metadata, deleted_at, created_at, updated_at, country_code, city, occupation, height_cm, body_type, languages_spoken, smoking, drinking, fitness, public_id, pronouns, job_title, company_name, school_or_institution, looking_for_text, children_count, languages, relocation_preferences) VALUES (%s, %s, 3, %s, %s, %s, %s, %s, %s, %s, %L, %s, %s, %s, %s, %s, %s, %s, %s, %L, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %L, ARRAY[]::character varying[]);',
  mp.new_id, mu.new_id, mbm.new_id,
  quote_nullable(p.display_name), quote_nullable(p.bio), quote_nullable(p.birthdate), quote_nullable(p.gender),
  p.status, p.visibility, p.metadata::text, quote_nullable(p.deleted_at), quote_literal(p.created_at), quote_literal(p.updated_at),
  quote_nullable(p.country_code), quote_nullable(p.city), quote_nullable(p.occupation), quote_nullable(p.height_cm),
  quote_nullable(p.body_type), p.languages_spoken::text, quote_nullable(p.smoking), quote_nullable(p.drinking),
  quote_nullable(p.fitness), quote_literal(p.public_id), quote_nullable(p.pronouns), quote_nullable(p.job_title),
  quote_nullable(p.company_name), quote_nullable(p.school_or_institution), quote_nullable(p.looking_for_text),
  quote_nullable(p.children_count), p.languages::text
)
FROM profiles p
JOIN map_profiles mp ON mp.old_id = p.id
JOIN map_users mu ON mu.old_id = p.user_id
JOIN map_brand_memberships mbm ON mbm.old_id = p.brand_membership_id
ORDER BY mp.new_id;

SELECT format(
  'INSERT INTO profile_photos (id, profile_id, user_id, brand_id, position, status, visibility, metadata, deleted_at, created_at, updated_at, processing_state, processed_at, public_id) VALUES (%s, %s, %s, 3, %s, %s, %s, %L, %s, %s, %s, %s, %s, %s);',
  mpp.new_id, mp.new_id, mu.new_id, pp.position, pp.status, pp.visibility, pp.metadata::text,
  quote_nullable(pp.deleted_at), quote_literal(pp.created_at), quote_literal(pp.updated_at),
  pp.processing_state, quote_nullable(pp.processed_at), quote_literal(pp.public_id)
)
FROM profile_photos pp
JOIN map_profile_photos mpp ON mpp.old_id = pp.id
JOIN map_profiles mp ON mp.old_id = pp.profile_id
JOIN map_users mu ON mu.old_id = pp.user_id
ORDER BY mpp.new_id;

SELECT format(
  'INSERT INTO active_storage_blobs (id, key, filename, content_type, metadata, service_name, byte_size, checksum, created_at) VALUES (%s, %L, %L, %s, %s, %L, %s, %s, %s);',
  mb.new_id, asb.key, asb.filename, quote_nullable(asb.content_type), quote_nullable(asb.metadata),
  CASE WHEN asb.service_name = 'r2_hookus_staging' THEN 'r2_hookus_production' ELSE asb.service_name END,
  asb.byte_size, quote_nullable(asb.checksum), quote_literal(asb.created_at)
)
FROM active_storage_blobs asb
JOIN map_blobs mb ON mb.old_id = asb.id
ORDER BY mb.new_id;

SELECT format(
  'INSERT INTO active_storage_attachments (id, name, record_type, record_id, blob_id, created_at) VALUES (%s, %L, %L, %s, %s, %s);',
  ma.new_id, asa.name, asa.record_type, mpp.new_id, mb.new_id, quote_literal(asa.created_at)
)
FROM active_storage_attachments asa
JOIN map_attachments ma ON ma.old_id = asa.id
JOIN map_profile_photos mpp ON mpp.old_id = asa.record_id AND asa.record_type = 'ProfilePhoto'
JOIN map_blobs mb ON mb.old_id = asa.blob_id
ORDER BY ma.new_id;

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

SELECT 'SELECT setval(''' || t || ''', ' || m || ', true) -- ' || t
FROM (VALUES
  ('users_id_seq', (SELECT max(new_id) FROM map_users)),
  ('identity_identifiers_id_seq', (SELECT coalesce(max(new_id),1605) FROM map_identity_identifiers)),
  ('credentials_id_seq', (SELECT coalesce(max(new_id),925) FROM map_credentials)),
  ('brand_memberships_id_seq', (SELECT coalesce(max(new_id),980) FROM map_brand_memberships)),
  ('profiles_id_seq', (SELECT coalesce(max(new_id),972) FROM map_profiles)),
  ('profile_photos_id_seq', (SELECT coalesce(max(new_id),1627) FROM map_profile_photos)),
  ('active_storage_blobs_id_seq', (SELECT coalesce(max(new_id),3617) FROM map_blobs)),
  ('active_storage_attachments_id_seq', (SELECT coalesce(max(new_id),3580) FROM map_attachments)),
  ('profile_locations_id_seq', (SELECT coalesce(max(new_id),76) FROM map_profile_locations))
) AS s(t, m);

SELECT 'COMMIT;';
\echo '--- END GENERATED SQL ---'
