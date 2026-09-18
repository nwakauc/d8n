BEGIN;
INSERT INTO users (id, status, deleted_at, created_at, updated_at, first_name, last_name, metadata) VALUES (983, 0, NULL, '2026-08-20 17:40:55.360687', '2026-08-20 17:40:55.360687', NULL, NULL, '{}');
INSERT INTO identity_identifiers (id, user_id, kind, normalized_value, verified_at, last_seen_at, metadata, deleted_at, created_at, updated_at, brand_id) VALUES (1607, 983, 1, '27859852278', NULL, '2026-08-24 06:51:34.128024', '{}', NULL, '2026-08-20 17:40:55.363126', '2026-08-24 06:51:34.134394', 3);
INSERT INTO credentials (id, user_id, identity_identifier_id, kind, status, verified_at, last_used_at, metadata, deleted_at, created_at, updated_at) VALUES (927, 983, 1607, 0, 0, NULL, '2026-08-24 06:51:34.13655', '{}', NULL, '2026-08-20 17:40:55.365173', '2026-08-24 06:51:34.145329');
INSERT INTO credential_password_hashes (credential_id, credential_kind, password_hash, password_changed_at, created_at, updated_at) VALUES (927, 0, '$2a$12$ccj44CAb3f6M0TqhzLGCTOIPG.spjl5J.c9vC5kec1uLcRn15wmHW', '2026-08-20 17:40:55.617314', '2026-08-20 17:40:55.617976', '2026-08-20 17:40:55.617976');
INSERT INTO brand_memberships (id, user_id, brand_id, status, deleted_at, created_at, updated_at) VALUES (982, 983, 3, 0, NULL, '2026-08-20 17:40:55.62046', '2026-08-20 17:40:55.62046');
INSERT INTO profiles (id, user_id, brand_id, brand_membership_id, display_name, bio, birthdate, gender, status, visibility, metadata, deleted_at, created_at, updated_at, country_code, city, occupation, height_cm, body_type, languages_spoken, smoking, drinking, fitness, public_id, pronouns, job_title, company_name, school_or_institution, looking_for_text, children_count, languages, relocation_preferences) VALUES (974, 983, 3, 982, 'Nikkie', 'I am a decent sweet lady', '1997-06-07', 'woman', 1, 1, '{}', NULL, '2026-08-20 17:41:51.157', '2026-08-20 17:42:03.130176', 'ZA', 'Bellvile', NULL, NULL, NULL, '[]', NULL, NULL, NULL, 'dab7e160-719a-4df8-9090-e68aad5f7b10', NULL, NULL, NULL, NULL, NULL, NULL, '[]', ARRAY[]::character varying[]);
INSERT INTO profile_locations (id, profile_id, user_id, brand_id, latitude, longitude, accuracy_meters, source, captured_at, deleted_at, created_at, updated_at, place_id) VALUES (78, 974, 983, 3, -33.5452690, 18.6026707, 113, 'device', '2026-09-15 15:52:47.576', NULL, '2026-08-24 06:51:42.344274', '2026-09-15 15:52:47.9553', NULL);
SELECT setval('users_id_seq', 983, true); -- users_id_seq
SELECT setval('identity_identifiers_id_seq', 1607, true); -- identity_identifiers_id_seq
SELECT setval('credentials_id_seq', 927, true); -- credentials_id_seq
SELECT setval('brand_memberships_id_seq', 982, true); -- brand_memberships_id_seq
SELECT setval('profiles_id_seq', 974, true); -- profiles_id_seq
SELECT setval('profile_photos_id_seq', 1627, true); -- profile_photos_id_seq
SELECT setval('active_storage_blobs_id_seq', 3617, true); -- active_storage_blobs_id_seq
SELECT setval('active_storage_attachments_id_seq', 3580, true); -- active_storage_attachments_id_seq
SELECT setval('profile_locations_id_seq', 78, true); -- profile_locations_id_seq
COMMIT;
