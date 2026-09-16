#!/usr/bin/env bash
set -euo pipefail
: "${SOURCE_CONN:?}"; : "${DEST_CONN:?}"
SOURCE_PSQL="psql ${SOURCE_CONN} -v ON_ERROR_STOP=1 -q"
DEST_PSQL="psql ${DEST_CONN} -v ON_ERROR_STOP=1 -tAq"
TABLES=(users identity_identifiers credentials credential_password_hashes)
pk_for() { case "$1" in credential_password_hashes) echo "credential_id" ;; *) echo "id" ;; esac; }
sql_file="$(mktemp)"; query_dir="$(mktemp -d)"
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
echo "\\echo Advancing sequences..." >>"${sql_file}"
for table in "${TABLES[@]}"; do
  pk="$(pk_for "${table}")"
  [ "${pk}" = "credential_id" ] && continue
  echo "SELECT setval(pg_get_serial_sequence('${table}','${pk}'), (SELECT COALESCE(MAX(${pk}),1) FROM ${table}), true);" >>"${sql_file}"
done
echo "COMMIT;" >>"${sql_file}"
psql ${DEST_CONN} -v ON_ERROR_STOP=1 -f "${sql_file}"
