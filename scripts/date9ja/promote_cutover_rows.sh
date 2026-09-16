#!/usr/bin/env bash
# Promotes ONLY the date9ja-brand rows built in the disposable
# d8n_date9ja_rehearsal_cutover DB into a real destination (production, or a
# test stand-in). Every table is filtered to brand_id=2 (or joined to it) so
# no other brand's data is ever touched. FK-ordered, single transaction --
# an interrupted or failed run rolls back atomically and is safe to retry
# from scratch. See docs/migrations/date9ja-to-d8n/PRODUCTION-CUTOVER-RUNBOOK.md
# section 4.4.
#
# Required env:
#   SOURCE_CONN      - psql connection string/args for the disposable DB
#   DEST_CONN        - psql connection string/args for the destination
#   DATE9JA_BRAND_ID - the date9ja Brand#id in BOTH databases (must match)
set -euo pipefail

: "${SOURCE_CONN:?Set SOURCE_CONN}"
: "${DEST_CONN:?Set DEST_CONN}"
: "${DATE9JA_BRAND_ID:?Set DATE9JA_BRAND_ID}"

SOURCE_PSQL="psql ${SOURCE_CONN} -v ON_ERROR_STOP=1 -q"
BID="${DATE9JA_BRAND_ID}"

sql_file="$(mktemp)"
query_dir="$(mktemp -d)"
trap 'rm -f "${sql_file}"; rm -rf "${query_dir}"' EXIT

copy_step() {
  local table="$1" select_sql="$2"
  local query_file="${query_dir}/${table}.sql"
  # Each source query lives in its own file -- no shell-quoting nesting at
  # all, so table filters can freely contain single quotes.
  printf 'COPY (%s) TO STDOUT' "${select_sql}" >"${query_file}"
  cat >>"${sql_file}" <<SQL
\echo Promoting ${table}...
\copy ${table} FROM PROGRAM '${SOURCE_PSQL} -f ${query_file}'
SQL
}

cat >"${sql_file}" <<'SQL'
BEGIN;
SQL

copy_step "users" \
  "SELECT u.* FROM users u JOIN brand_memberships bm ON bm.user_id = u.id AND bm.brand_id = ${BID}"

copy_step "identity_identifiers" \
  "SELECT ii.* FROM identity_identifiers ii JOIN brand_memberships bm ON bm.user_id = ii.user_id AND bm.brand_id = ${BID}"

copy_step "credentials" \
  "SELECT c.* FROM credentials c JOIN brand_memberships bm ON bm.user_id = c.user_id AND bm.brand_id = ${BID}"

copy_step "credential_password_hashes" \
  "SELECT cph.* FROM credential_password_hashes cph JOIN credentials c ON c.id = cph.credential_id JOIN brand_memberships bm ON bm.user_id = c.user_id AND bm.brand_id = ${BID}"

copy_step "brand_memberships" \
  "SELECT * FROM brand_memberships WHERE brand_id = ${BID}"

copy_step "profiles" \
  "SELECT * FROM profiles WHERE brand_id = ${BID}"

copy_step "profile_preferences" \
  "SELECT * FROM profile_preferences WHERE brand_id = ${BID}"

copy_step "profile_option_selections" \
  "SELECT * FROM profile_option_selections WHERE brand_id = ${BID}"

copy_step "likes" \
  "SELECT * FROM likes WHERE brand_id = ${BID}"

copy_step "profile_passes" \
  "SELECT * FROM profile_passes WHERE brand_id = ${BID}"

copy_step "matches" \
  "SELECT * FROM matches WHERE brand_id = ${BID}"

copy_step "conversations" \
  "SELECT * FROM conversations WHERE brand_id = ${BID}"

copy_step "messages" \
  "SELECT * FROM messages WHERE brand_id = ${BID}"

copy_step "message_reactions" \
  "SELECT * FROM message_reactions WHERE brand_id = ${BID}"

copy_step "profile_blocks" \
  "SELECT * FROM profile_blocks WHERE brand_id = ${BID}"

copy_step "reports" \
  "SELECT * FROM reports WHERE brand_id = ${BID}"

copy_step "verification_assertions" \
  "SELECT * FROM verification_assertions WHERE brand_id = ${BID}"

copy_step "date9ja_history_records" \
  "SELECT * FROM date9ja_history_records WHERE brand_id = ${BID}"

copy_step "trust_events" \
  "SELECT * FROM trust_events WHERE brand_id = ${BID}"

copy_step "trust_adjustments" \
  "SELECT * FROM trust_adjustments WHERE brand_id = ${BID}"

copy_step "profile_photos" \
  "SELECT * FROM profile_photos WHERE brand_id = ${BID}"

copy_step "profile_videos" \
  "SELECT * FROM profile_videos WHERE brand_id = ${BID}"

copy_step "active_storage_blobs" \
  "SELECT b.* FROM active_storage_blobs b JOIN active_storage_attachments a ON a.blob_id = b.id WHERE (a.record_type = 'ProfilePhoto' AND a.record_id IN (SELECT id FROM profile_photos WHERE brand_id = ${BID})) OR (a.record_type = 'ProfileVideo' AND a.record_id IN (SELECT id FROM profile_videos WHERE brand_id = ${BID}))"

copy_step "active_storage_attachments" \
  "SELECT a.* FROM active_storage_attachments a WHERE (a.record_type = 'ProfilePhoto' AND a.record_id IN (SELECT id FROM profile_photos WHERE brand_id = ${BID})) OR (a.record_type = 'ProfileVideo' AND a.record_id IN (SELECT id FROM profile_videos WHERE brand_id = ${BID}))"

copy_step "legacy_references" \
  "SELECT * FROM legacy_references WHERE brand_id = ${BID}"

cat >>"${sql_file}" <<SQL

\\echo Advancing sequences...
SELECT setval(pg_get_serial_sequence('users','id'), (SELECT COALESCE(MAX(id),1) FROM users), true);
SELECT setval(pg_get_serial_sequence('identity_identifiers','id'), (SELECT COALESCE(MAX(id),1) FROM identity_identifiers), true);
SELECT setval(pg_get_serial_sequence('credentials','id'), (SELECT COALESCE(MAX(id),1) FROM credentials), true);
SELECT setval(pg_get_serial_sequence('brand_memberships','id'), (SELECT COALESCE(MAX(id),1) FROM brand_memberships), true);
SELECT setval(pg_get_serial_sequence('profiles','id'), (SELECT COALESCE(MAX(id),1) FROM profiles), true);
SELECT setval(pg_get_serial_sequence('profile_preferences','id'), (SELECT COALESCE(MAX(id),1) FROM profile_preferences), true);
SELECT setval(pg_get_serial_sequence('profile_option_selections','id'), (SELECT COALESCE(MAX(id),1) FROM profile_option_selections), true);
SELECT setval(pg_get_serial_sequence('likes','id'), (SELECT COALESCE(MAX(id),1) FROM likes), true);
SELECT setval(pg_get_serial_sequence('profile_passes','id'), (SELECT COALESCE(MAX(id),1) FROM profile_passes), true);
SELECT setval(pg_get_serial_sequence('matches','id'), (SELECT COALESCE(MAX(id),1) FROM matches), true);
SELECT setval(pg_get_serial_sequence('conversations','id'), (SELECT COALESCE(MAX(id),1) FROM conversations), true);
SELECT setval(pg_get_serial_sequence('messages','id'), (SELECT COALESCE(MAX(id),1) FROM messages), true);
SELECT setval(pg_get_serial_sequence('message_reactions','id'), (SELECT COALESCE(MAX(id),1) FROM message_reactions), true);
SELECT setval(pg_get_serial_sequence('profile_blocks','id'), (SELECT COALESCE(MAX(id),1) FROM profile_blocks), true);
SELECT setval(pg_get_serial_sequence('reports','id'), (SELECT COALESCE(MAX(id),1) FROM reports), true);
SELECT setval(pg_get_serial_sequence('verification_assertions','id'), (SELECT COALESCE(MAX(id),1) FROM verification_assertions), true);
SELECT setval(pg_get_serial_sequence('date9ja_history_records','id'), (SELECT COALESCE(MAX(id),1) FROM date9ja_history_records), true);
SELECT setval(pg_get_serial_sequence('trust_events','id'), (SELECT COALESCE(MAX(id),1) FROM trust_events), true);
SELECT setval(pg_get_serial_sequence('trust_adjustments','id'), (SELECT COALESCE(MAX(id),1) FROM trust_adjustments), true);
SELECT setval(pg_get_serial_sequence('profile_photos','id'), (SELECT COALESCE(MAX(id),1) FROM profile_photos), true);
SELECT setval(pg_get_serial_sequence('profile_videos','id'), (SELECT COALESCE(MAX(id),1) FROM profile_videos), true);
SELECT setval(pg_get_serial_sequence('active_storage_blobs','id'), (SELECT COALESCE(MAX(id),1) FROM active_storage_blobs), true);
SELECT setval(pg_get_serial_sequence('active_storage_attachments','id'), (SELECT COALESCE(MAX(id),1) FROM active_storage_attachments), true);
SELECT setval(pg_get_serial_sequence('legacy_references','id'), (SELECT COALESCE(MAX(id),1) FROM legacy_references), true);

COMMIT;
SQL

psql ${DEST_CONN} -v ON_ERROR_STOP=1 -f "${sql_file}"
