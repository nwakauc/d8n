# PostgreSQL Backup And Restore Runbook

## Scope and ownership

D8N has two production PostgreSQL databases:

- `primary`: identity, profiles, matching, messaging metadata, and application data;
- `queue`: Solid Queue operational state.

Both should be backed up, but the primary database is the authoritative recovery
priority. R2 media requires its own lifecycle and recovery policy; a PostgreSQL
backup does not contain object bytes.

The founder must choose the backup destination, retention, encryption/key owner,
recovery-point target, recovery-time target, and operator. Backup files must live
off the database host. Do not place them in the repository, container image, or
app-local persistent volume.

## Create backups

Use normal PostgreSQL connection variables (`PGHOST`, `PGPORT`, `PGUSER`, and
`PGPASSWORD` or a protected password file). Never put a password on a command
line. Run once for each database:

```sh
D8N_BACKUP_DATABASE=d8n_production \
D8N_BACKUP_LABEL=d8n-primary \
D8N_BACKUP_OUTPUT_DIR=/mounted/off-host-backups \
script/operations/postgres_backup

D8N_BACKUP_DATABASE=d8n_production_queue \
D8N_BACKUP_LABEL=d8n-queue \
D8N_BACKUP_OUTPUT_DIR=/mounted/off-host-backups \
script/operations/postgres_backup
```

The script creates a compressed custom-format dump and SHA-256 checksum with
owner-only permissions. Uploading, retention, encryption, and alerting are
provider/operator responsibilities and are intentionally not guessed in code.
Use PostgreSQL client tools from the same major version as the server (or a newer
compatible client). A failed dump is written to an owner-only temporary path and
removed instead of being published as a backup.

## Prove a restore

Copy one dated backup to an isolated PostgreSQL host. The restore script accepts
only a new database beginning with `d8n_restore_`, refuses to overwrite or drop
anything, validates the archive first, and retains the restored database for
inspection:

```sh
D8N_RESTORE_CONFIRM=CREATE_DISPOSABLE_RESTORE_DATABASE \
D8N_RESTORE_KIND=primary \
D8N_RESTORE_BACKUP=/secure/path/d8n-primary-YYYYMMDDTHHMMSSZ.dump \
D8N_RESTORE_TARGET=d8n_restore_primary_YYYYMMDD \
script/operations/postgres_restore_drill
```

Repeat with `D8N_RESTORE_KIND=queue` for the queue dump. Record start/end time,
archive timestamp and checksum, PostgreSQL version, source/target environment,
representative counts, application boot result, gaps, and operator. Verify more
than table existence: authenticate a synthetic account and read a representative
profile using an isolated application process with all outbound delivery disabled.

Database removal is deliberately not automated. After evidence is recorded, an
authorized operator may drop the exact disposable restore database manually.

## Failure rules

- A successful dump is not a proven backup until a restore drill succeeds.
- Never restore over staging or production. Restore into a new isolated database.
- Stop if the checksum differs, `pg_restore --list` fails, or the PostgreSQL major
  version is incompatible.
- Do not treat the queue backup as a substitute for idempotent jobs. After a
  disaster, reconcile side effects before resuming workers.
- Do not restore signed sessions or old credentials into a publicly reachable
  environment during a drill.

## Evidence still required

The scripts and safety boundary can be tested locally, but DR-05 remains open
until a dated staging-like off-host backup is restored and verified. Automated
scheduling, off-host transfer, retention, encryption, and alerting require the
founder's provider and policy decisions.
