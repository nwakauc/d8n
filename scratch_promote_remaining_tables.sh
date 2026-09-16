#!/usr/bin/env bash
# Promotes rows created by a SECOND import pass (e.g. resolving a specific
# user's identity collision after the bulk promotion already ran) into a real
# destination. Unlike promote_cutover_rows.sh (which filters by brand_id, for
# the initial bulk promotion), this filters each table to "id > the max id
# already present in the destination" -- valid because the disposable DB's
# sequences continue exactly from the same production baseline and nothing
# else has written to it since the original bulk promotion, so any row with a
# higher id is unambiguously new. FK-ordered, single transaction -- an
# interrupted or failed run rolls back atomically and is safe to retry.
#
# Required env:
#   SOURCE_CONN - psql connection string/args for the disposable DB
#   DEST_CONN   - psql connection string/args for the destination
set -euo pipefail

: "${SOURCE_CONN:?Set SOURCE_CONN}"
: "${DEST_CONN:?Set DEST_CONN}"

SOURCE_PSQL="psql ${SOURCE_CONN} -v ON_ERROR_STOP=1 -q"
DEST_PSQL="psql ${DEST_CONN} -v ON_ERROR_STOP=1 -tAq"

TABLES=(
  users identity_identifiers credentials credential_password_hashes
  profile_preferences profile_option_selections
  likes profile_passes matches conversations messages message_reactions
  profile_blocks reports verification_assertions date9ja_history_records
  trust_events trust_adjustments profile_photos profile_videos
  active_storage_blobs active_storage_attachments legacy_references
)

# credential_password_hashes' primary key is credential_id, not id -- it has
# no independent identity of its own (see db/schema.rb).
pk_for() {
  case "$1" in
    credential_password_hashes) echo "credential_id" ;;
    *) echo "id" ;;
  esac
}

sql_file="$(mktemp)"
query_dir="$(mktemp -d)"
trap 'rm -f "${sql_file}"; rm -rf "${query_dir}"' EXIT

echo "BEGIN;" >"${sql_file}"

for table in "${TABLES[@]}"; do
  pk="$(pk_for "${table}")"
  max_id=$(${DEST_PSQL} -c "SELECT COALESCE(MAX(${pk}), 0) FROM ${table}")
  query_file="${query_dir}/${table}.sql"
  printf 'COPY (SELECT * FROM %s WHERE %s > %s ORDER BY %s) TO STDOUT' "${table}" "${pk}" "${max_id}" "${pk}" >"${query_file}"
  cat >>"${sql_file}" <<SQL
\echo Promoting new rows in ${table} (${pk} > ${max_id})...
\copy ${table} FROM PROGRAM '${SOURCE_PSQL} -f ${query_file}'
SQL
done

cat >>"${sql_file}" <<'SQL'

\echo Advancing sequences...
SQL

for table in "${TABLES[@]}"; do
  pk="$(pk_for "${table}")"
  # credential_password_hashes' PK isn't a real sequence-backed column (it's
  # just the FK to credentials), so there's no sequence to advance for it.
  [ "${pk}" = "credential_id" ] && continue
  echo "SELECT setval(pg_get_serial_sequence('${table}','${pk}'), (SELECT COALESCE(MAX(${pk}),1) FROM ${table}), true);" >>"${sql_file}"
done

echo "COMMIT;" >>"${sql_file}"

psql ${DEST_CONN} -v ON_ERROR_STOP=1 -f "${sql_file}"
