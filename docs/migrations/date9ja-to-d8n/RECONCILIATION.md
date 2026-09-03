# Reconciliation Plan

No production counts were collected in Phase 1 because production access remains out of scope. Run against the approved snapshot and staging/import output, recording snapshot/run IDs and timestamps.

## Source census

The source column is produced by `scripts/date9ja/source_census.sql` — a
read-only, schema-fingerprint-guarded script that emits one row per measure plus
the sub-state breakdowns an importer needs to make "equal after documented
exclusions" unambiguous. Run it against `date9ja_snapshot_sanitized` (row counts
are identical to the pristine restore — the sanitizer preserves every row):

```
psql -v ON_ERROR_STOP=1 -d date9ja_snapshot_sanitized -f scripts/date9ja/source_census.sql
```

Paste the full output into the run record and fill the table below from it.

### Snapshot 2026-09-02 (rehearsal artifact) — headline source counts

Operator-verified after `sanitize → verify → pg_dump → pg_restore` into
`date9ja_snapshot_package_test`; all row counts survived the round trip.

| Measure | Source | Target | Acceptance |
|---|---:|---:|---|
| users/accounts | 288 | 280 (rehearsal 2026-09-03) | 288 = 280 imported + 8 skipped (`source_soft_deleted`) + 0 failed; idempotent on rerun |
| published profiles | pending (census: `onboarding_completed_at NOT NULL`) | pending | equal after state mapping; definition confirmed with product |
| photos | 279 | pending | equal; exceptions listed |
| profile videos | 35 | pending | equal; exceptions listed |
| active storage blobs | 443 | pending | every object preflights; checksum/size/type match |
| verified users | pending (census: `verification_tier > 0`) | pending | equal under approved definition |
| likes | 546 | pending | equal after valid mapping |
| passes | pending (census: `profile_passes`) | pending | equal or approved exclusion |
| matches | 82 | pending | equal canonical unique pairs |
| conversations | 82 (one container per match; Date9ja has no separate table) | pending | one per retained match |
| messages | 1025 | pending | equal per retention policy |
| profile views | 1627 | pending | equal per retention policy |
| blocks | 3 | pending | equal same-brand rows |
| reports | 3 | pending | equal retained reports |

Also reconcile profile videos, message reactions, profile views, verification records/status/history, trust records/status, notification preferences/deliveries, Community, Dating Hub, Aunty Phobie, subscription/entitlement state, and any other active capability in [CAPABILITY-PARITY.md](CAPABILITY-PARITY.md). For retained features, an “approved exclusion” is not a cutover pass: the feature must have a supported target or an explicitly approved transition that preserves user access.

Validate that every mapped user has exactly one D8N user and at most one Date9ja membership/profile; every relationship is same-brand, non-self, directional where applicable; every match is canonical and unique; every conversation has exactly two match participants; every message has a valid participant sender and same-conversation reply; and read state maps to the correct participant.

For media, verify every source blob/object exists, matches checksum/size/type, maps to a destination public ID, and is deliverable under D8N privacy rules. Missing or unsupported objects are exceptions, not skips.

Run the importer twice against the same snapshot: the second run must create zero users, profiles, relationships, conversations, or messages, and destination IDs/fingerprints must remain unchanged. Test interruption/resume as well.

## Identity importer reconciliation contract (Wave A slice 3)

`Date9ja::Import::IdentityImport` (in the Date9ja adapter, `domains/date9ja/`)
emits `Date9ja::Import::Reconciliation#to_h` — deterministic and **PII-free**
(counts and reason codes only; no email, phone, bcrypt hash, or free text). Every
source row lands in exactly one disposition and every non-import carries a reason
code, so `source_users_considered == sum(dispositions)` always holds.

| Section | Keys |
|---|---|
| `dispositions` | `imported`, `already_imported`, `skipped`, `failed` |
| `created` | `users_created`, `identifiers_created`, `credentials_created`, `password_hashes_created`, `memberships_created`, `profiles_created`, `legacy_references_created` |
| `anomalies` | `normalization_collisions`, `missing_identifiers`, `malformed_rows`, `binding_conflicts` |
| `reason_codes` | only codes with a positive count |

Reason codes:

| Code | Disposition | Meaning |
|---|---|---|
| `source_soft_deleted` | skipped | `users.deleted_at` present — documented exclusion for this slice |
| `source_banned` | skipped | `users.banned_at` present — enforcement tombstone, not migrated here |
| `already_imported` | already_imported | the `user` `LegacyReference` resolves and all required identity, membership, and profile bindings are present and consistent; nothing created |
| `email_unparseable` | failed | `users.email` fails D8N canonical email normalization (required identifier) |
| `email_collision` | failed | the normalized email already exists on another D8N identity — **never merged**, row fails closed |
| `phone_unparseable` | (row still imported) | `users.phone` present but fails E.164 normalization — phone identifier skipped |
| `phone_collision` | (row still imported) | normalized phone already exists elsewhere — phone identifier skipped, never merged |
| `credential_hash_unusable` | skipped (blank) / failed (malformed) | `encrypted_password` empty or not a 60-char bcrypt string |
| `profile_invalid` | failed | shared `Profile` validation rejected the mapped row (e.g. birthdate < 18) |
| `dangling_binding` | failed | a `user` reference exists but its destination row is gone — fail closed |
| `incomplete_binding` | failed | a prior `user` reference resolves, but one or more required downstream bindings/records are missing or inconsistent — never reported as complete |
| `binding_conflict` | failed | `Migration::ReferenceMap` reported an immutable-binding / destination conflict |
| `source_row_error` | failed | any other error inside the per-row transaction (nothing persisted) |

Each source row is imported inside its own savepointed transaction: a failed row
leaves nothing behind and is retried cleanly on the next run. Re-running is
idempotent — the second run reports every row as `already_imported` and creates
zero rows.

Operator rehearsal command (against the sanitized snapshot — validates structure,
mapping, idempotency, reference mapping, counts, collision handling and
reconciliation; it does **not** re-prove bcrypt auth, which is already VERIFIED):

```
createdb d8n_date9ja_rehearsal_20260903
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 bin/rails db:schema:load
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 \
  DATE9JA_API_HOST=date9ja.rehearsal.local bin/rails brands:install_date9ja
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 \
  DATE9JA_SNAPSHOT_DATABASE_URL=postgres://localhost:5432/date9ja_snapshot_sanitized \
  bin/rails date9ja:import_identity
```

### Wave A Slice 3 rehearsal result — VERIFIED (2026-09-03)

Source: `date9ja_snapshot_sanitized`. Schema preflight PASS (v2 signature
`41a653a8d4c25621071fb76e6e59fbc0`, 51 tables, 574 columns). Two full passes into
a throwaway D8N database.

| Reconciliation measure | First pass | Second pass |
|---|---:|---:|
| `source_users_considered` | 288 | 288 |
| dispositions: imported / already_imported / skipped / failed | 280 / 0 / 8 / 0 | 0 / 280 / 8 / 0 |
| eligible | 280 | 280 |
| users / credentials / password_hashes / memberships / profiles created | 280 | 0 |
| identifiers_created | 460 | 0 |
| legacy_references_created | 1580 | 0 |
| anomalies (normalization_collisions, missing_identifiers, malformed_rows, binding_conflicts) | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| reason_codes | `source_soft_deleted: 8` | `source_soft_deleted: 8`, `already_imported: 280` |

Source-census cross-check (authoritative `source_census.sql`): users total 288 =
users kept 280 + users soft-deleted 8. Distinct `lower(email)` 288 and distinct
`public_id` 288 → no identifier collisions, consistent with
`normalization_collisions: 0` / `missing_identifiers: 0`. No unexplained source
rows in either pass. Idempotency demonstrated: the second pass created nothing
and reported every kept row `already_imported`.

**This rehearsal validates structure, mapping, idempotency, reference mapping,
counts, collision handling and reconciliation. It does not re-prove bcrypt auth
(independently VERIFIED, `$2a$` cost 12, `$2a$ 12 PASS`, 2026-09-02). It is NOT
`PARITY_ACCEPTED`, NOT production-ready, NOT cutover-ready** — see the open
deferred decisions in `STATUS.md` (first/last-name mapping, country
normalization, sensitive profile fields, publication/completion semantics,
phone-collision policy, deleted/banned treatment, later migration domains).

## Profile-photo MEDIA PREFLIGHT contract (Wave A, pass 1 — ADR 0027)

`Date9ja::Import::PhotoImport` emits `Date9ja::Import::PhotoReconciliation#to_h`
— deterministic, PII-free (counts + reason codes + aggregate measures only; no
storage key, filename, checksum value, email, name, or any per-row id). Pass 1
records `Migration::MediaObjectRef` / `Migration::MediaAttachmentRef` only — it
creates no `ProfilePhoto`, copies no bytes, binds no `ReferenceMap`.

**Invariant:** `photos_considered == preflighted + already_preflighted +
owner_not_imported + unavailable + malformed + failed + explicitly_skipped`.
On a clean first run `already_preflighted` is 0; `explicitly_skipped` is always 0
(no documented policy exclusion for photos).

| Disposition | Meaning |
|---|---|
| `preflighted` | blob + attachment recorded; owner profile resolved; fresh this run |
| `already_preflighted` | identical rerun — both refs unchanged |
| `owner_not_imported` | source `Photo.user_id` has no imported Date9ja `profile` `LegacyReference`; refs still recorded for a later pass |
| `unavailable` | `missing_attachment` (no `Photo`/`image` row) or `missing_blob` (attachment points at no blob) |
| `malformed` | `moderation_unmapped` — `moderation_status` outside `{0,1,2}` |
| `failed` | `duplicate_attachment`, `unsupported_content_type`, `checksum_size_inconsistent`, `blob_metadata_drift`, `attachment_drift` — evidence still recorded where a blob exists |
| `explicitly_skipped` | reserved; unused for photos |

| Reason code | Disposition | Meaning |
|---|---|---|
| `owner_not_imported` | owner_not_imported | owner profile not migrated |
| `source_suspended_owner` | (still preflighted) | owner imported but membership/profile suspended — classified, not excluded |
| `missing_attachment` | unavailable | no `record_type='Photo' AND name='image'` row for the Photo |
| `duplicate_attachment` | failed | >1 image attachment for one Photo (different blobs) |
| `missing_blob` | unavailable | attachment `blob_id` has no `active_storage_blobs` row |
| `unsupported_content_type` | failed | blob content type not JPEG/PNG/WebP |
| `checksum_size_inconsistent` | failed | blank checksum or non-positive byte size |
| `moderation_unmapped` | malformed | `moderation_status` not in the authoritative enum |
| `blob_metadata_drift` | failed | rerun sees changed checksum/size/type for the same source blob — fail closed |
| `attachment_drift` | failed | rerun sees the same source attachment id pointing at a different blob/record/name |

**Aggregate measures** (rehearsal acceptance baselines, not runtime truth):
`total_source_photos`, `moderation_pending|approved|rejected`,
`total_primary_rows`, `owners_total`, `owners_with_one_primary`,
`owners_with_zero_primary`, `owners_with_multiple_primary`, `owners_over_six`,
`max_photos_per_owner`, `owners_suspended`, `missing_attachments`,
`duplicate_attachments`, `missing_blobs`, `unsupported_content_types`,
`checksum_size_inconsistencies`, `malformed_moderation_values`,
`owner_not_imported`, `blob_reuse_objects`, `binding_conflicts`.

Primary-photo and >6-photo anomalies are **measured, never normalized** — pass 2
applies the primary-photo mapping and the photo-limit quarantine
(`DECISIONS.md`).

**Census baseline (2026-09-02, `date9ja_snapshot_sanitized`) — acceptance targets, not hard-coded:**
`total_source_photos` 279 · `moderation_pending` 2 · `moderation_approved` 266 ·
`moderation_rejected` 11 · `total_primary_rows` 164 · `active_storage_attachments` 428 ·
`active_storage_blobs` 443. Expected pass-1 result: every one of the 279 rows in
exactly one disposition, `preflighted` + `owner_not_imported` covering the rows
with a valid image attachment + blob, `already_preflighted` 0 on the first run.

Operator rehearsal command (no byte transfer, no `ProfilePhoto`):

```
createdb d8n_date9ja_rehearsal_20260903
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 bin/rails db:schema:load
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 \
  DATE9JA_API_HOST=date9ja.rehearsal.local bin/rails brands:install_date9ja
# identity pass first (photo owners must resolve):
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 \
  DATE9JA_SNAPSHOT_DATABASE_URL=postgres://localhost:55432/date9ja_snapshot_sanitized \
  bin/rails date9ja:import_identity
RAILS_ENV=test DATABASE_URL=postgresql:///d8n_date9ja_rehearsal_20260903 \
  DATE9JA_SNAPSHOT_DATABASE_URL=postgres://localhost:55432/date9ja_snapshot_sanitized \
  bin/rails date9ja:preflight_photos
```

### Pass-1 rehearsal result — VERIFIED (2026-09-03)

Source `date9ja_snapshot_sanitized`, schema preflight PASS, throwaway D8N DB,
run after the identity rehearsal. Two full passes.

| Reconciliation measure | first pass | second pass |
|---|---:|---:|
| `photos_considered` / `balanced` | 279 / true | 279 / true |
| `preflighted` | 276 | 0 |
| `already_preflighted` | 0 | 276 |
| `owner_not_imported` | 3 | 3 |
| `unavailable` / `malformed` / `failed` / `explicitly_skipped` | 0 | 0 |
| `MediaObjectRef` created | 279 | 0 |
| `MediaAttachmentRef` created | 279 | 0 |

Stable measures matched the census baseline: `total_source_photos` 279 ·
moderation 2 / 266 / 11 · `total_primary_rows` 164 · `owners_total` 166 ·
`owners_with_one_primary` 164 · `owners_with_zero_primary` 2 ·
`owners_with_multiple_primary` 0 · `owners_over_six` 0 · `max_photos_per_owner` 6 ·
`owners_suspended` 3 · every anomaly counter 0 · `blob_reuse_objects` 0.

Invariant closed both passes (`279 = 276 + 0 + 3 + 0` first; `279 = 0 + 276 + 3 + 0`
second). Idempotency demonstrated: zero refs created on the second pass. The 3
`owner_not_imported` photos are **not** proven to be the 3 `owners_suspended` —
aggregate output does not establish that.

**Lifecycle:** media preflight foundation VERIFIED · pass-1 implementation
VERIFIED · pass-1 sanitized rehearsal VERIFIED · profile-photo capability
overall **PARTIAL** (bytes/`ProfilePhoto`/processing/delivery/frontend/cutover
outstanding — pass 2, see `MEDIA-TRANSFER.md`). NOT `PARITY_ACCEPTED`.

### Pass-2 `service_name` census — RUN 2026-09-03

Metadata-only census (no bytes, no `key`) against `date9ja_snapshot_sanitized`
(`postgresql://127.0.0.1:55432`):

| `service_name` | photo blob count |
|---|---:|
| `cloudflare` | 279 |

No `local`, no `amazon`, no `NULL`, no mixed-service corpus. The Pass-1 gap
(`MediaObjectRef` did not record `service_name`) is closed for this slice. Pass 2
re-asserts the single-service invariant against the final production snapshot at
run time and treats any non-`cloudflare` value as a global blocker.

### Pass-2 L2 synthetic-corpus rehearsal — SELF_VERIFIED (2026-09-03)

Full 279-row rehearsal against `date9ja_snapshot_sanitized_media_v2` + the
deterministic synthetic corpus (`Date9ja::Snapshot::SyntheticMedia`), read
through `Date9ja::Storage::LocalCorpusReader`. No real R2, no production.

| Measure | First run | Rerun (raw present) | Rerun (raw purged) |
|---|--:|--:|--:|
| `photos_considered` / `balanced` | 279 / true | 279 / true | 279 / true |
| `transferred` | 276 | 0 | 0 |
| `already_transferred` | 0 | 276 | 276 |
| `owner_not_imported` | 3 | 3 | 3 |
| all other dispositions | 0 | 0 | 0 |
| `profile_photos_created` | 276 | 0 | 0 |
| `reference_map_bindings_created` | 276 | 0 | 0 |
| `destination_uploads_created` | 276 | 0 | 0 |
| `processing_succeeded` | 276 | 0 | 0 |
| `binding_conflicts` / `mapping_drift` | 0 / 0 | 0 / 0 | 0 / 0 |
| `unexplained_failures` | 3 | 3 | 3 |
| `cutover_ready` | false | false | false |

Invariant `photos_considered == Σ dispositions` holds every run
(`279 = 276 + 0 + 3` first; `279 = 0 + 276 + 3` reruns). `cutover_ready` is
false only because the 3 known `owner_not_imported` (suspended source owners)
count as `unexplained_failures` — there is no reviewed-exception workflow in this
build. Destination state after the first run: 276 `ProfilePhoto` all
`processing_ready` with a validated deterministic display derivative;
moderation `pending_review`→visible 2 / `approved`→visible 263 /
`rejected`→hidden 11; every owner exactly one `position 0`; per-owner 1–6, no
truncation. 276 detached original blobs purge cleanly and every ProfilePhoto
stays `ready` + `Media::DisplayDerivative.valid?` afterwards. An interrupted run
(two `SIGKILL`s) converged with zero duplicates; one claim-held photo was
reclaimed by `Media::ProfilePhotoProcessingSweeper` after the stale window and
completed on the next run (276/276). Output is PII-free (no storage key,
checksum, email, or per-row id). **NOT independently reviewed; NOT
`PARITY_ACCEPTED` / cutover-ready / L3-ready.**

### Pass-2 transfer reconciliation contract

Defined in [`MEDIA-TRANSFER.md`](MEDIA-TRANSFER.md) §15 (design checkpoint —
Revision 4, not implemented; `binding_conflict` covers `remote_orphan`,
`destination_collision`, and `mapping_drift` (destination `ReferenceMap(profile)`
resolution changed after pre-copy — the storage object is never re-keyed), and
every reused destination object is re-verified by a real streamed re-hash).
Terminal dispositions: `transferred`,
`already_transferred`, `owner_not_imported`, `source_unavailable`,
`source_changed`, `validation_failed`, `destination_failed`, `binding_conflict`,
`processing_failed`, `quarantined`, `explicitly_skipped`. Invariant
`photos_considered == Σ dispositions`. Every non-success disposition is
additionally `unexplained_failure` or `reviewed_exception`; cutover requires
`unexplained_failure == 0`. PII-free; no storage locator or checksum value in
output. Baseline: 276 transfer-eligible, 3 `owner_not_imported`,
`profile_photos_created` 276 on a clean first run / 0 on rerun.

```text
Snapshot <id> / run <id>
Users <source> → <target> ✓
Profiles <source> → <target> ✓
Photos <source> → <target> ✓
Likes <source> → <target> ✓
Matches <source> → <target> ✓
Conversations <source> → <target> ✓
Messages <source> → <target> ✓
Blocks <source> → <target> ✓
Reports <source> → <target> ✓
Orphans 0 ✓ / Duplicate identities 0 ✓ / Broken media 0 ✓
Unmapped records 0 or approved exception list
```
