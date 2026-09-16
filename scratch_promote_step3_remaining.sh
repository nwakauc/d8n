#!/usr/bin/env bash
set -euo pipefail
: "${SOURCE_CONN:?}"; : "${DEST_CONN:?}"
SOURCE_PSQL="psql ${SOURCE_CONN} -v ON_ERROR_STOP=1 -q"
DEST_PSQL="psql ${DEST_CONN} -v ON_ERROR_STOP=1 -tAq"
TABLES=(
  profile_preferences profile_option_selections
  likes profile_passes matches conversations messages message_reactions
  profile_blocks reports verification_assertions date9ja_history_records
  trust_events trust_adjustments profile_photos profile_videos
  active_storage_blobs active_storage_attachments legacy_references
)
sql_file="$(mktemp)"; query_dir="$(mktemp -d)"
trap 'rm -f "${sql_file}"; rm -rf "${query_dir}"' EXIT
echo "BEGIN;" >"${sql_file}"
for table in "${TABLES[@]}"; do
  max_id=$(${DEST_PSQL} -c "SELECT COALESCE(MAX(id), 0) FROM ${table}")
  query_file="${query_dir}/${table}.sql"
  printf 'COPY (SELECT * FROM %s WHERE id > %s ORDER BY id) TO STDOUT' "${table}" "${max_id}" >"${query_file}"
  cat >>"${sql_file}" <<SQL
\echo Promoting new rows in ${table} (id > ${max_id})...
\copy ${table} FROM PROGRAM '${SOURCE_PSQL} -f ${query_file}'
SQL
done
echo "\\echo Advancing sequences..." >>"${sql_file}"
for table in "${TABLES[@]}"; do
  echo "SELECT setval(pg_get_serial_sequence('${table}','id'), (SELECT COALESCE(MAX(id),1) FROM ${table}), true);" >>"${sql_file}"
done
echo "COMMIT;" >>"${sql_file}"
psql ${DEST_CONN} -v ON_ERROR_STOP=1 -f "${sql_file}"
