-- Run this on the STAGING box (Oracle server) against d8n-staging-db.
-- It is READ-ONLY against staging (temp tables + SELECTs only) and just
-- prints ready-to-run INSERT statements for production, with every id
-- already remapped past production's current max ids (passed in below).
-- Review the output before running any of it against production.

CREATE TEMP TABLE map_users AS
SELECT u.id AS old_id, 952 + row_number() OVER (ORDER BY u.id) AS new_id
FROM users u
JOIN brand_memberships bm ON bm.user_id = u.id
JOIN brands b ON b.id = bm.brand_id AND b.slug = 'hookus'
WHERE u.created_at >= '2026-09-14';

CREATE TEMP TABLE map_identity_identifiers AS
SELECT ii.id AS old_id, 1575 + row_number() OVER (ORDER BY ii.id) AS new_id
FROM identity_identifiers ii
JOIN map_users mu ON mu.old_id = ii.user_id;

CREATE TEMP TABLE map_credentials AS
SELECT c.id AS old_id, 895 + row_number() OVER (ORDER BY c.id) AS new_id
FROM credentials c
JOIN map_identity_identifiers mii ON mii.old_id = c.identity_identifier_id;

CREATE TEMP TABLE map_brand_memberships AS
SELECT bm.id AS old_id, 950 + row_number() OVER (ORDER BY bm.id) AS new_id
FROM brand_memberships bm
JOIN map_users mu ON mu.old_id = bm.user_id;

CREATE TEMP TABLE map_profiles AS
SELECT p.id AS old_id, 947 + row_number() OVER (ORDER BY p.id) AS new_id
FROM profiles p
JOIN map_users mu ON mu.old_id = p.user_id;

CREATE TEMP TABLE map_profile_photos AS
SELECT pp.id AS old_id, 1574 + row_number() OVER (ORDER BY pp.id) AS new_id
FROM profile_photos pp
JOIN map_profiles mp ON mp.old_id = pp.profile_id;

CREATE TEMP TABLE map_blobs AS
SELECT DISTINCT asb.id AS old_id, 3576 + row_number() OVER (ORDER BY asb.id) AS new_id
FROM active_storage_blobs asb
JOIN active_storage_attachments asa ON asa.blob_id = asb.id
JOIN map_profile_photos mpp ON mpp.old_id = asa.record_id AND asa.record_type = 'ProfilePhoto';

CREATE TEMP TABLE map_attachments AS
SELECT asa.id AS old_id, 3539 + row_number() OVER (ORDER BY asa.id) AS new_id
FROM active_storage_attachments asa
JOIN map_profile_photos mpp ON mpp.old_id = asa.record_id AND asa.record_type = 'ProfilePhoto';

\echo '--- counts (sanity check before generating SQL) ---'
SELECT 'users' t, count(*) FROM map_users
UNION ALL SELECT 'identity_identifiers', count(*) FROM map_identity_identifiers
UNION ALL SELECT 'credentials', count(*) FROM map_credentials
UNION ALL SELECT 'brand_memberships', count(*) FROM map_brand_memberships
UNION ALL SELECT 'profiles', count(*) FROM map_profiles
UNION ALL SELECT 'profile_photos', count(*) FROM map_profile_photos
UNION ALL SELECT 'active_storage_blobs', count(*) FROM map_blobs
UNION ALL SELECT 'active_storage_attachments', count(*) FROM map_attachments;

\echo '--- BEGIN GENERATED SQL (copy everything from here down) ---'
SELECT 'BEGIN;';

SELECT format(
  'INSERT INTO users (id, status, deleted_at, created_at, updated_at, first_name, last_name, metadata) VALUES (%s, %s, %s, %s, %s, %s, %s, %L);',
  mu.new_id, u.status, quote_nullable(u.deleted_at), quote_literal(u.created_at), quote_literal(u.updated_at),
  quote_nullable(u.first_name), quote_nullable(u.last_name), '{}'
)
FROM users u JOIN map_users mu ON mu.old_id = u.id ORDER BY mu.new_id;

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
  asb.service_name, asb.byte_size, quote_nullable(asb.checksum), quote_literal(asb.created_at)
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

SELECT 'COMMIT;';
\echo '--- END GENERATED SQL ---'
