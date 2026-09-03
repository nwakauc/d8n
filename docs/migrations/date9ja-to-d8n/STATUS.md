# Date9ja → D8N Status

- Current phase: **Phase 1 — Shared Platform Foundations** (Wave A)
- Current capability: Batches 2 & 3 reviewed; sanitized snapshot milestone VERIFIED; reconciliation census + schema-signature v2 VERIFIED (independent review); import execution model RESOLVED; **bcrypt compatibility proof VERIFIED (2026-09-02, operator ran `scripts/date9ja/bcrypt_proof.rb` against a real `$2a$12$` account → `$2a$ 12 PASS`)**; identity + membership + non-sensitive profile importer — implementation reviewed + **operator rehearsal VERIFIED (2026-09-03)** against `date9ja_snapshot_sanitized` (288 source rows → 280 imported / 8 skipped `source_soft_deleted` / 0 failed; second pass 280 already_imported / 0 created; source reconciliation balanced); **profile-photo pass 2 implementation VERIFIED + L2 synthetic-corpus rehearsal VERIFIED (Codex independent review 2026-09-03: FINAL VERDICT ACCEPT)**; **profile-video pass 1 (media preflight) VERIFIED (Codex 2026-09-03: ACCEPT WITH SMALL FIX — documentation correction completed), sanitized rehearsal 35/35 preflighted + idempotent; legacy `duration_seconds` NULL for all 35 (no row known to exceed the limit; actual duration unproven — pass 2 must derive it from the container)**. **NOT PARITY_ACCEPTED, NOT production-ready, NOT cutover-ready. L3 NOT YET READY.**
- Builder: Claude (senior engineer)
- Reviewer: Independent reviewer — Codex (batches 1–3 + profile-photo pass 2 / L2 reviewed)
- Review cadence: bounded batches (~3–5 slices), not per-slice. Significant work remains **SELF_VERIFIED** until independent review.
- Last verified: 2026-09-02
- Cutover: **BLOCKED** until data parity and feature parity both pass.

## Wave A slice 3 — Date9ja identity importer — **VERIFIED (2026-09-03)**

First structural movement of Date9ja members into D8N. Reads a **restored scratch
PostgreSQL** copy of a Date9ja backup (never a live connection) and imports, per
source `users` row:

`User` → `IdentityIdentifier`(email, +phone when parseable) → `Credential`(password)
+ `CredentialPasswordHash` (**legacy bcrypt digest copied byte-for-byte, never
`PasswordEngine.set!`**) → Date9ja `BrandMembership` → shared `Profile`
(non-sensitive fields only) → `Migration::ReferenceMap` bindings → PII-free
`Reconciliation`.

**Architecture — "no empires inside kingdoms":**

| Unit | Location | Kind |
|---|---|---|
| `Date9ja::Snapshot::{Connection,SchemaGuard,UserSource,UserRecord}` | `domains/date9ja/snapshot/` | Date9ja source adapter — legacy-schema-aware |
| `Date9ja::Import::{FieldMapping,Reconciliation,IdentityImport}` | `domains/date9ja/import/` | Date9ja importer — legacy→D8N mapping |
| `Migration::DestinationTypes` — added `"Credential" => :platform` | `domains/migration/` | shared primitive — the sanctioned one-entry-per-slice extension |
| `date9ja:import_identity` rake task | `lib/tasks/date9ja_import.rake` | operator rehearsal entry point |

Shared `Identity::*`, `Profiles::*`, `Migration::ReferenceMap` are consumed
unchanged. No Date9ja schema knowledge in any shared domain.

**Safety fences:** `DATE9JA_SNAPSHOT_DATABASE_URL` is required and explicit (no
fallback to D8N's own DB); production-looking names/hosts and D8N's own primary
are rejected; the shared v2 schema signature
(`scripts/date9ja/schema_signature.sql`) runs before any row is read; `UserSource`
SELECTs only the columns this slice may import; `FieldMapping::SENSITIVE_DENYLIST`
is asserted by test to be disjoint from the SELECT list, the record shape, and
`Profile.column_names`.

**Idempotency:** per-row savepointed transaction; a re-run reports a row as
`already_imported` only after validating every required downstream binding and
record. Missing or inconsistent downstream state is `incomplete_binding` and
fails closed. Profiles are created draft/hidden until dependent profile slices
complete the D8N publication contract.

**Sensitive-field firewall:** tribe / religion / denomination / ethnicity /
state_of_origin / is_nigerian / nationality / preferred_* / genotype /
intertribal_marriage_openness / polygamy_openness / aunty_phobie_language /
interest_in_nigerian_culture — never selected, never mapped, test-enforced.

**Out of scope (unchanged):** media, likes/passes/matches/messages/reactions,
profile views, blocks/reports, verification/RealMe, trust/reputation,
subscriptions/entitlements, notification prefs, devices/push, Community, Dating
Hub, Aunty Phobie, Careers, Feedback, attribution, frontend.

**Tests:** `test/domains/date9ja/**` plus migration/reference tests — 63 runs,
197 assertions, green; synthetic
values only (bcrypt via `BCrypt::Password.create(pw, cost: 4)`). RuboCop clean;
`git diff --check` clean. Covers clean import, email/phone identifiers, bcrypt
byte-identity + real-path auth, membership/profile lifecycle, reference bindings,
second-run idempotency (no duplicates), email/phone normalization collisions,
missing identifier, malformed/blank hash, invalid profile, soft-deleted/banned
skip, dangling binding, wrong/inactive brand, schema-signature failure, unsafe DB
config rejection, firewall, reconciliation totals, and no-PII reconciliation
output.

**Review outcome:** ACCEPT WITH SMALL FIXES. Source URL query-override and
percent-encoding fences were tightened; incomplete prior bindings now fail
closed; unused free-form `languages_spoken` was removed from the adapter
record; imported profiles remain draft/hidden until dependent slices complete.

### Operator rehearsal — VERIFIED (2026-09-03)

Ran against `date9ja_snapshot_sanitized` into a throwaway D8N database. Schema
preflight **PASS** — v2 signature `41a653a8d4c25621071fb76e6e59fbc0`, 51 public
base tables, 574 columns.

| | First pass | Second pass (idempotency) |
|---|---:|---:|
| `source_users_considered` | 288 | 288 |
| imported | 280 | 0 |
| already_imported | 0 | 280 |
| skipped | 8 | 8 |
| failed | 0 | 0 |
| users / credentials / password_hashes / memberships / profiles created | 280 each | 0 |
| identifiers_created | 460 | 0 |
| legacy_references_created | 1580 | 0 |
| anomalies (all four) | 0 | 0 |
| reason codes | `source_soft_deleted: 8` | `source_soft_deleted: 8`, `already_imported: 280` |

**Source reconciliation (no unexplained rows):** the authoritative census
reports 288 total = 280 kept + 8 soft-deleted. First pass: 288 = 280 imported +
8 skipped + 0 failed. Second pass: 288 = 280 already_imported + 8 skipped + 0
failed. Census also confirmed distinct `lower(email)` = 288 and distinct
`public_id` = 288 (no identifier collisions), so `normalization_collisions: 0`
and `missing_identifiers: 0` are expected, not silent loss. `identifiers_created`
460 = 280 email + 180 phone; the 180 is below the census `phone present: 184`
because soft-deleted rows and any absent/unparseable phone value produce no
identifier, and `normalization_collisions: 0` confirms none were dropped by
collision. No parity decisions are inferred from the other census counts
(confirmed 209 / unconfirmed 79 / phone verified 13 / suspended 7 / banned 0).

**Lifecycle:** Wave A Slice 3 is **implementation-reviewed + rehearsal VERIFIED**
— sanitized rehearsal completed, source reconciliation completed, idempotency
demonstrated across two full passes.

**Explicitly NOT:** `PARITY_ACCEPTED` · production-ready · cutover-ready. Open
deferred decisions remain open: first/last-name mapping, country normalization,
sensitive profile fields, final profile publication/completion semantics,
phone-collision reconciliation policy, final treatment of deleted/banned
accounts, and every later migration domain (media, relationship graph,
verification, trust, entitlements, Community, Dating Hub, Aunty Phobie).

Next bounded slice: profile-photo importer — see below.

## Wave A — media preflight foundation + Date9ja profile-photo pass 1 — **VERIFIED (2026-09-03)** · pass 2 design checkpoint

Codex review of the earlier "blocked at design" proposal returned REQUEST
CHANGES (correct); the corrected architecture is **ADR 0027 (Accepted)**,
implemented and independently reviewed. Profile-photo capability **overall
remains PARTIAL** — bytes, `ProfilePhoto` creation, processing/delivery,
frontend acceptance and cutover are not done. **NOT `PARITY_ACCEPTED`, NOT
production-ready, NOT cutover-ready.**

### Generic migration-media primitives (platform, not Date9ja)

| Primitive | Canonical identity | Owns |
|---|---|---|
| `Migration::MediaObjectRef` (`migration_media_object_refs`) | `(source_system, source_blob_id)` | source-blob integrity metadata + preflight state + transfer state |
| `Migration::MediaAttachmentRef` (`migration_media_attachment_refs`) | `(source_system, source_attachment_id)` | one source attachment/use → its `MediaObjectRef` + the source record it hangs off |

Written only through `.preflight!` / `.record!` (single-write-path, like
`Migration::ReferenceMap`), never read by consumer code. One blob may back many
attachments (blob reuse). **`Migration::ReferenceMap` stays the sole
source→destination identity binding** — these tables carry no
`legacy_reference_id` / `destination_*`. The legacy storage locator is **never
read or stored** in pass 1.

### Date9ja profile-photo pass 1 (media preflight only)

`Date9ja::Snapshot::PhotoSource` — v2-schema-guarded, column-allowlisted,
deterministic (`ORDER BY id`), same DB-safety fences as Slice 3. Reads the
`photos` table and only `record_type='Photo' AND name='image'` attachments +
their blobs' `id/byte_size/checksum/content_type` (never `key`/`filename`/
`metadata`/`service_name`).

`Date9ja::Import::PhotoImport` — per source Photo row: validate moderation enum
(authoritative `pending:0/approved:1/rejected:2`), resolve the single image
attachment + blob, upsert `MediaObjectRef` + `MediaAttachmentRef`, resolve
whether the owner profile was imported (via the existing `profile`
`LegacyReference`), and record a terminal disposition. **Creates no
`ProfilePhoto`, no D8N Active Storage record, enqueues no job, copies no bytes,
binds no `ReferenceMap`, reorders nothing, sets no visibility.** Suspended owners
are classified structurally, not excluded. All source rows are processed —
owner-not-imported is a disposition, never a silent drop.

Dispositions (mutually exclusive, invariant `photos_considered == Σ
dispositions`): `preflighted`, `already_preflighted`, `owner_not_imported`,
`unavailable`, `malformed`, `failed`, `explicitly_skipped`. Full reason-code +
measure contract in `RECONCILIATION.md`. Primary-photo / >6-photo anomalies are
**measured, never normalized** (pass-2 quarantine — see `DECISIONS.md`).

### Idempotency

`preflight!` / `record!` upsert by canonical identity; identical rerun →
`already_preflighted`, zero new rows. Drift in checksum / byte size / content
type / attachment owner / source record / attachment name → `Drift` → the row
fails closed (`blob_metadata_drift` / `attachment_drift`).

### Files

- `db/migrate/20260903120000_create_migration_media_object_refs.rb`, `…120100_create_migration_media_attachment_refs.rb`
- `app/models/migration/media_object_ref.rb`, `media_attachment_ref.rb`
- `domains/date9ja/snapshot/{photo_source,photo_record,attachment_record,blob_record}.rb`
- `domains/date9ja/import/{photo_moderation,photo_reconciliation,photo_import}.rb`
- `lib/tasks/date9ja_import.rake` (+ `date9ja:preflight_photos`)
- `docs/adr/0027-migration-media-preflight-architecture.md`
- tests: `test/models/migration/media_{object,attachment}_ref_test.rb`, `test/domains/date9ja/snapshot/photo_source_test.rb`, `test/domains/date9ja/import/photo_import_test.rb`

### Tests / checks

`test/models/migration/` + `test/domains/date9ja/` + `test/models/` — 402 runs,
1551 assertions, **0 failures**. RuboCop clean (27 files). `git diff --check`
clean. Coverage: schema guard before reads, source allowlist, Photo/image
filter, deterministic ordering, every moderation bucket + unknown value, blob
reuse, missing/duplicate attachment, missing blob, unsupported content type,
owner imported / not imported / suspended, >6-photo + primary-state measurement,
duplicate-primary detection (measure only), `MediaObjectRef` / `MediaAttachmentRef`
uniqueness, metadata + attachment drift fail-closed, rerun idempotency, no
`ProfilePhoto` / no Active Storage / no job enqueue, cross-source isolation,
reconciliation invariant, PII/locator-free output, wrong-brand refusal.

### Pass-1 sanitized rehearsal — VERIFIED (2026-09-03)

Against `date9ja_snapshot_sanitized` (schema preflight PASS), throwaway D8N DB,
after the identity rehearsal.

| | first pass | second pass |
|---|---:|---:|
| `photos_considered` / `balanced` | 279 / true | 279 / true |
| `preflighted` | 276 | 0 |
| `already_preflighted` | 0 | 276 |
| `owner_not_imported` | 3 | 3 |
| `unavailable` / `malformed` / `failed` / `explicitly_skipped` | 0 each | 0 each |
| `MediaObjectRef` / `MediaAttachmentRef` created | 279 / 279 | 0 / 0 |

Stable measures: 279 photos · moderation 2 pending / 266 approved / 11 rejected ·
164 primary rows · `owners_total` 166 · `owners_with_one_primary` 164 ·
`owners_with_zero_primary` 2 · `owners_with_multiple_primary` 0 · `owners_over_six`
0 · `max_photos_per_owner` 6 · `owners_suspended` 3 · every anomaly counter 0 ·
`blob_reuse_objects` 0. The 3 `owner_not_imported` and 3 `owners_suspended` are
**not** proven to be the same accounts.

### Lifecycle

| Unit | State |
|---|---|
| Media preflight foundation (`Migration::MediaObjectRef` / `MediaAttachmentRef`, ADR 0027) | **VERIFIED** |
| Date9ja profile-photo pass 1 implementation | **VERIFIED** |
| Date9ja profile-photo pass 1 sanitized rehearsal | **VERIFIED** |
| Profile-photo capability overall | **PARTIAL** — not `PARITY_ACCEPTED`, not production-ready, not cutover-ready |
| Profile-photo **pass 2** (byte transfer + `ProfilePhoto` creation) | **IMPLEMENTATION VERIFIED (Codex FINAL bounded re-review 2026-09-03: ACCEPT). L2 279-row synthetic-corpus rehearsal VERIFIED (Codex independent review 2026-09-03: manifest byte_size exact typing YES, NULL-safe complete blob drift YES, existing L2 evidence still valid YES; focused verification 34 runs / 140 assertions / 0 failures; `git diff --check` CLEAN; FINAL VERDICT: ACCEPT — this closes the L2 review) — `date9ja_snapshot_sanitized_media_v2` + `Date9ja::Snapshot::SyntheticMedia` + `Date9ja::Storage::LocalCorpusReader` + `Date9ja::Storage::SafeObjectKey`; identity 280, pass-1 276+3, pass-2 transferred 276 / owner_not_imported 3, idempotent + interrupt-safe, raw purge clean, no R2, no production. NOT PARITY_ACCEPTED / cutover-ready / L3-ready.** Implementation-review rounds 1 + 2 (Codex BLOCK) fixes applied. Round 2: single authoritative `Media::DisplayDerivative.valid?` (bounded remote + checksum) on every job ready/finalize/purge path, run outside all DB locks; Phase-B `finalize_binding` rejects same-user/wrong-profile existing bindings (`mapping_drift`). ADR 0028 ACCEPTED. Code + L1 automated tests landed and green (`Migration::MediaTransfer` + `CanonicalKey` + `AdoptOrUpload`, `Date9ja::Storage::SourceReader`, `Date9ja::Snapshot::MediaLocatorSource`, `Date9ja::Import::PhotoTransfer` / `PhotoOrderPlan` / `PhotoTransferReconciliation`, `Profiles::PhotoUpload.build_photo!` extraction, `ProfilePhoto` claim-token processing hardening + `Media::ProfilePhotoProcessingSweeper`). RuboCop / Zeitwerk / Brakeman clean. **NOT independently reviewed, NOT `VERIFIED`, NOT `PARITY_ACCEPTED`.** L1: covered by tests. L2 (`_media_v2` artifact): NOT built. L3 (real R2): NOT wired (transport only). No bytes moved. |

### Date9ja profile-video pass 1 (media preflight only) — VERIFIED (Codex independent review, 2026-09-03: ACCEPT WITH SMALL FIX — documentation correction completed)

The video analogue of profile-photo pass 1. **Reuses the same generic
migration-media spine** (`Migration::MediaObjectRef` / `MediaAttachmentRef` /
`ReferenceMap`) with no new framework and no change to their shared semantics.

`Date9ja::Snapshot::VideoSource` — v2-schema-guarded (same
`scripts/date9ja/schema_signature.sql` signature `41a653a8…`, which already
classifies `profile_videos`), column-allowlisted, deterministic (`ORDER BY id`),
same DB-safety fences as Slice 3. Reads `profile_videos`
(`id/user_id/duration_seconds/moderation_status/created_at/reviewed_at`) and only
`record_type='ProfileVideo' AND name='video'` attachments + their blobs'
`id/byte_size/checksum/content_type` — never `key`/`filename`/`metadata`/
`service_name`/`rejection_reason`.

`Date9ja::Import::VideoPreflight` — per source `profile_videos` row: validate the
moderation enum (authoritative `pending:0/approved:1/rejected:2`), resolve the
single `video` attachment + blob, validate content type against the shared
`ProfileVideo::ALLOWED_CONTENT_TYPES` constant, upsert `MediaObjectRef` +
`MediaAttachmentRef` (`source_record_entity: "profile_video"`), resolve whether
the owner profile was imported (existing `profile` `ReferenceMap`), and record
one terminal disposition. **Creates no `ProfileVideo`, no D8N Active Storage
record, no `playback`/`poster` derivative, enqueues no job, opens/reads no blob
body, binds no `ReferenceMap`, sets no visibility.** Suspended owners are
classified structurally, not excluded.

Duration is **measured only** (`duration_present/missing/within_limit/
over_limit/invalid` against `Media::VideoPolicy.max_duration_seconds`). Pass 1
never rejects a structurally valid row for exceeding the current D8N limit — the
grandfather / trim / quarantine decision is a pass-2 product decision
(`DECISIONS.md`). The source table is 1:1 on `user_id` (UNIQUE), so
"multiple kept videos per owner" is structurally impossible; the preflight still
measures it and fails such an owner closed (`multiple_videos_per_owner`) rather
than arbitrarily choosing.

Dispositions (invariant `videos_considered == Σ dispositions`): `preflighted`,
`already_preflighted`, `owner_not_imported`, `unavailable`, `malformed`,
`failed`, `explicitly_skipped`.

**Files:** `domains/date9ja/snapshot/{video_source,video_record}.rb`,
`domains/date9ja/import/{video_moderation,video_preflight_reconciliation,video_preflight}.rb`,
`lib/tasks/date9ja_import.rake` (+ `date9ja:preflight_videos`), tests
`test/domains/date9ja/snapshot/video_source_test.rb` +
`test/domains/date9ja/import/video_preflight_test.rb`.

**Tests / checks:** focused 37 runs / 125 assertions / 0 failures; broader
`test/domains/date9ja` + `test/domains/migration` + `test/models/migration`
248 runs / 0 failures; profile-video model + upload tests green. RuboCop clean
(8 files), Zeitwerk `All is good!`, Brakeman 0/0, `git diff --check` clean.

**Pass-1 sanitized rehearsal — SELF_VERIFIED (2026-09-03).** Against
`date9ja_snapshot_sanitized` (schema preflight PASS), throwaway D8N DB, after the
identity rehearsal.

| | first pass | second pass |
|---|---:|---:|
| `videos_considered` / `balanced` | 35 / true | 35 / true |
| `preflighted` | 35 | 0 |
| `already_preflighted` | 0 | 35 |
| `owner_not_imported` / `unavailable` / `malformed` / `failed` | 0 each | 0 each |
| `MediaObjectRef` / `MediaAttachmentRef` created | 35 / 35 | 0 / 0 |
| `ProfileVideo` / Active Storage rows | 0 / 0 | 0 / 0 |

Stable measures (balance against `source_census.sql` measures 63/64: 35 total,
35 `moderation_status=0`): 35 videos · moderation 35 pending / 0 approved / 0
rejected · `owners_total` 35 · `owners_with_one_video` 35 ·
`owners_with_multiple_videos` 0 · `owners_suspended` 0 · every attachment/blob
anomaly counter 0 · `unsupported_content_types` 0 (source: 26 `video/mp4` + 9
`video/quicktime`, both accepted) · `blob_reuse_objects` 0 ·
`max_duration_limit_seconds` 60 · **`duration_missing` 35** (every legacy row's
`duration_seconds` is NULL — Date9ja never persisted it) · `duration_over_limit`
**0**.

**Duration finding.** No source row is known to exceed the current D8N duration
limit. Duration remains **unknown for all 35 observed legacy videos** because
Date9ja did not persist `duration_seconds` (`duration_missing` 35 / 35,
`duration_present` 0, `duration_over_limit` 0). Pass 2 must derive and validate
authoritative duration from the actual media/container before accepting a
migrated video; if the derived duration exceeds the limit, stop and require the
existing grandfather / trim-reencode / quarantine product decision
(`DECISIONS.md`). Pass 1 measures only and never rejects a row for duration.

| Unit | State |
|---|---|
| Date9ja profile-video pass 1 implementation | **VERIFIED** (Codex independent review 2026-09-03: ACCEPT WITH SMALL FIX — documentation correction completed) |
| Date9ja profile-video pass 1 sanitized rehearsal | **VERIFIED** (2026-09-03) |
| Profile-video capability overall | **PARTIAL** — unchanged; pass 1 does not move it. Not `PARITY_ACCEPTED`. |
| Profile-video **pass 2** (byte transfer + `ProfileVideo` creation + L2) | **NOT STARTED** — may now be PLANNED; must derive authoritative duration from the media container |

## Pass 2 (profile-photo byte transfer) — IMPLEMENTATION VERIFIED (Codex FINAL, 2026-09-03); L2 rehearsal VERIFIED (Codex, 2026-09-03)

Code + automated L1 tests landed against ACCEPTED ADR 0028. Full media / profiles
/ migration / date9ja suites green (0 failures); one pre-existing unrelated
failure elsewhere (`Notifications::DeliverProductNotificationJobTest` — DateZA
welcome-email template gained a CTA link the test was not updated for).

- **Shared migration:** `Migration::MediaTransfer` (`.call` — verify + adopt-or-upload),
  `Migration::MediaTransfer::CanonicalKey` (sole key producer),
  `Migration::MediaTransfer::AdoptOrUpload` (AS cases 1–6).
- **Date9ja adapter:** `Date9ja::Storage::SourceReader` (security contract,
  injected transport — NO real R2), `Date9ja::Snapshot::MediaLocatorSource`,
  `Date9ja::Import::PhotoTransfer` (Phase A/B/C), `PhotoOrderPlan`,
  `PhotoTransferReconciliation`.
- **Shared media (minimal extraction):** `Profiles::PhotoUpload.build_photo!` —
  internal domain seam; `attach!` behaviour unchanged and regression-tested.
- **Processing hardening:** `ProfilePhoto.processing_started_at` +
  `processing_claim_token` (migration `20260903130000`); concurrency-safe
  `Media::ProcessProfilePhotoJob` (claim / work-outside / finalize + ABA token);
  `Media::ProfilePhotoProcessingSweeper`.
- **Implementation-review round 1 (Codex BLOCK) fixes applied 2026-09-03:**
  (1) pre-Phase-A prefix inference → complete authoritative deterministic-chain
  validation (`resolve_existing_state`); owner mapping re-resolved in Phase B and
  compared to the RESOLVE-phase owner (fail closed on drift). (2) NO storage /
  network / libvips work under a DB lock — `Migration::MediaTransfer::LockGuard`
  (thread-local) fails closed; `AdoptOrUpload` refactored to A/B/C (short DB
  snapshot → external op outside lock → short authoritative re-check).
  (3) async never reports premature success — `transferred` only after
  `processing_ready` + `valid_accepted_display?`; bounded drain, timeout →
  `processing_failed`. (4) `Migration::MediaTransfer.valid_accepted_display?` —
  exact deterministic display key + service + bounded remote re-hash + decode.
  Security: bounded destination reads (`DestinationTooLarge`), EXACT
  canonical-content-type equality (row + remote), strict `SourceReader` key
  grammar, retry-exhaustion → terminal failure (no sweeper loop),
  post-commit-only raw purge gated on an owned finalization.
- **Implementation-review round 2 (Codex BLOCK — 2 defects) fixes applied 2026-09-03:**
  (1) ONE authoritative display-validation contract — new shared primitive
  `Media::DisplayDerivative.valid?` (D8N media domain, no migration semantics):
  proves display attachment ownership + EXACT deterministic key + expected
  service + content type + `Blob.checksum` integrity of the streamed bytes +
  JPEG decode, over a BOUNDED remote read. `Media::ProcessProfilePhotoJob` no
  longer trusts any metadata-only shape check as a success / ready-no-op / purge
  path: the strong check runs OUTSIDE every DB lock (CLAIM returns `:verify_ready`;
  `reconcile_ready` confirms, or rebuilds from a still-present raw, or fails
  closed `terminal` when the raw is already purged). The exact display key is
  re-derived after raw purge from persisted `ProfilePhoto#metadata`
  (`raw_object_key` / `display_object_key` / `display_service_name` — existing
  jsonb, not a new table) and cross-checked against the deterministic relation.
  `Migration::MediaTransfer.valid_accepted_display?` now delegates to the same
  primitive (keeping its `LockGuard` assertion as defence in depth).
  (2) Phase-B `finalize_binding` no longer accepts an existing
  Photo→ProfilePhoto ReferenceMap that belongs to the same user but the WRONG
  profile/brand: `existing_binding_outcome` requires
  `destination_type == "ProfilePhoto"` AND `profile_id == current_resolved_profile.id`
  AND `user_id == …` AND `brand_id == brand.id` (plus key/order/moderation);
  same-user/wrong-profile → `binding_conflict` / `mapping_drift`, never
  `already_transferred`, never a silent reparent.
- **Codex FINAL bounded re-review (2026-09-03): both round-2 defects ACCEPT;
  FINAL VERDICT: ACCEPT.** Pass 2 implementation is **VERIFIED**. Synthetic
  `date9ja_snapshot_sanitized_media_v2` generation APPROVED; L2 APPROVED; L3 NOT
  YET READY.
- **NOT** `PARITY_ACCEPTED` / production-ready / cutover-ready.

### L2 rehearsal — VERIFIED (Codex independent review, 2026-09-03)

Full 279-row synthetic-corpus rehearsal of the complete Pass 2 path. **No real
Date9ja R2, no production, no live media, no L3.**

- **Artifact:** `date9ja_snapshot_sanitized_media_v2` — a `CREATE DATABASE …
  TEMPLATE date9ja_snapshot_sanitized` copy on the isolated PG17 snapshot
  instance (`127.0.0.1:55432`), with only `active_storage_blobs.byte_size` /
  `checksum` rewritten on the 279 Photo image blobs to describe the synthetic
  bytes. Structural identity (photo / attachment / blob / owner ids, moderation,
  primary, order, storage key, `service_name`, `content_type`) preserved exactly.
- **Generator / verifier / transport:** `Date9ja::Snapshot::SyntheticMedia`
  (`.render` — deterministic AES-CTR keystream pixels → libvips-encoded
  jpeg/png/webp), `…::SyntheticMedia::Generator` (corpus + PII-free
  `manifest.json` + `manifest.fingerprint`), `…::SyntheticMedia::Verifier`
  (15 checks), `Date9ja::Storage::LocalCorpusReader` (drop-in for
  `SourceReader`; local files only, bounded, fail-closed). Rake:
  `date9ja:build_media_v2`, `date9ja:verify_media_v2`, `date9ja:transfer_photos`
  (now L2-wired via `DATE9JA_MEDIA_CORPUS_DIR`).
- **Corpus:** 279 objects (252 jpeg / 21 png / 6 webp — matches the source
  census), ~61 MB, manifest fingerprint `ebcff28a796a230807fbdbfeb19ff63a…`;
  byte-for-byte identical across two independent generator runs.
- **Verifier:** all 15 checks pass → `MEDIA_V2 ARTIFACT: VERIFIED FOR L2`.
- **Rehearsal DB:** fresh throwaway `d8n_date9ja_rehearsal_l2_20260903`
  (schema-loaded, `date9ja` brand seeded).
- **Identity import:** 288 considered → 280 imported / 8 `source_soft_deleted` /
  0 failed; 280 users/credentials/memberships/profiles, 460 identifiers, 1580
  legacy references. Second run: 0 imported / 280 already_imported / 0 counters.
- **Pass 1 preflight:** 279 considered, balanced; 276 preflighted /
  3 `owner_not_imported` (`source_suspended_owner`); 279 `MediaObjectRef` +
  279 `MediaAttachmentRef` created; every structural anomaly measure 0. Second
  run: 0 / 276 already_preflighted / 3.
- **Pass 2 first run:** balanced; `transferred` 276, `owner_not_imported` 3;
  276 `ProfilePhoto` + 276 `ReferenceMap` bindings + 276 destination originals
  created; 276 processing → `ready` with a validated deterministic display
  derivative; 0 `binding_conflict` / 0 `mapping_drift` / 0 `processing_failed`.
  `cutover_ready` false — the 3 `owner_not_imported` count as
  `unexplained_failures` (no reviewed-exception workflow in this build).
- **Moderation / ordering:** destination `pending_review`→visible (2),
  `approved`→visible (263), `rejected`→hidden (11); every owner exactly one
  `position 0`; per-owner counts 1–6, no truncation, no multiple-primary.
- **Raw purge:** 276 detached original blobs (250 jpg / 20 png / 6 webp) purge
  cleanly; all 276 ProfilePhotos stay `ready` and still pass
  `Media::DisplayDerivative.valid?` afterwards (post-purge display-key inference
  from `ProfilePhoto#metadata`).
- **Idempotency:** rerun (raw present) and rerun (raw purged) both →
  276 `already_transferred` / 3 `owner_not_imported`, zero new
  ProfilePhoto / Blob / Attachment / ReferenceMap / MediaRef rows; the purged
  raw is never required to re-exist.
- **Interruption / resume:** two hard `SIGKILL`s mid-run then resume → converged
  with no duplicate photos / blobs / bindings / false `already_transferred`; one
  photo whose `ProcessProfilePhotoJob` was killed mid-work held its claim token
  (correct ABA protection), was reclaimed by `Media::ProfilePhotoProcessingSweeper`
  after the stale window, and completed on the next run → 276/276 `ready`.
- **Security:** all work on disposable local / snapshot-instance resources; no
  R2 endpoint or credential contacted; no live Date9ja DB; corpus proven to be a
  byte-exact re-render of the checked-in generator (contains no production
  bytes); reports PII-free; corpus + rehearsal DBs safely droppable.
- **Artifact-tooling review round (Codex L2 BLOCK — 2 tooling issues) fixes
  applied 2026-09-03:** (1) new shared `Date9ja::Storage::SafeObjectKey` — the
  single accepted safe-key grammar + path-containment + symlink-escape contract;
  both `LocalCorpusReader` (read) and `SyntheticMedia::Generator` (write) now
  depend on it, so the generator fails closed on the whole run before writing
  any object if a source key is not the exact contract the reader enforces, and
  every write path is proven strictly under the corpus root (expanded-path
  containment, not string prefix). (2) `SyntheticMedia::Verifier` gained
  `16_manifest_rows_match_media_v2_blobs` (every manifest `source_blob_id` /
  `source_key` / `service_name` / `canonical_content_type` / `byte_size` /
  `checksum` bound field-for-field to the authoritative media_v2 blob row — the
  Photo attachment graph defines the authorized set, not the manifest; fail
  closed on any missing / duplicate / unexpected / mismatch) and
  `17_complete_blob_table_drift_is_authorized` (schema-driven full
  `active_storage_blobs` comparison parent vs media_v2: same row count, same ids,
  no insert/delete; the 279 authorized Photo blobs may differ ONLY in
  `byte_size`/`checksum`; every other row and every other column byte-identical).
  **Case A:** generator/verifier-only — corpus bytes byte-identical, manifest
  fingerprint unchanged (`ebcff28a…`), media_v2 DB contents unchanged; the
  accepted L2 transfer evidence still corresponds to the artifact. Re-verified
  end-to-end on a fresh rehearsal DB (`d8n_date9ja_rehearsal_l2b_20260903`):
  identical Pass-2 result (transferred 276 / owner_not_imported 3, rerun 276
  already_transferred).
- **Verifier equality-precision round (Codex L2 BLOCK — 2 verifier defects)
  fixes applied 2026-09-03:** (1) check 16 now types manifest `byte_size`
  strictly via `canonical_byte_size` — only a non-negative JSON integer is
  accepted; `"123junk"`, `" 123"`, `"123.0"`, floats, booleans, nil and
  negatives are rejected (no permissive `.to_i`), and the DB side is compared
  as `Integer(blob.byte_size)`. (2) check 17 replaced universal `.to_s`
  comparison with `db_value_equal?` — NULL vs `''`, `0` vs `false`, `0` vs
  `'0'` are now distinct drift; native types preserved (`exec_query` values are
  not stringified). Verifier-only: corpus bytes, manifest fingerprint
  (`ebcff28a…`), and media_v2 DB contents unchanged; existing L2 transfer
  evidence still valid; no L2 rerun required. All 17 checks green.
- **L2 review loop CLOSED — Codex independent verification 2026-09-03: FINAL
  VERDICT ACCEPT.** Manifest byte_size exact typing: YES. NULL-safe complete
  blob-table drift: YES. Existing L2 transfer evidence still valid: YES. Focused
  verification: 34 runs / 140 assertions / 0 failures / 0 errors / 0 skips;
  `git diff --check` CLEAN. No further L2 review loop unless genuinely new
  evidence later invalidates an accepted invariant.

#### L2 closeout statement (durable)

The L2 synthetic-media rehearsal has completed independent verification.
Accepted evidence: 279 source Photo rows considered; 276 transferred; 3
`owner_not_imported` expected exclusions; 276 `ProfilePhoto` destinations; 276
`ready` processing state; authoritative display-derivative validation
(`Media::DisplayDerivative.valid?`, bounded remote + `Blob.checksum` + JPEG
decode, run outside all DB locks); raw-purge recovery/inference from
`ProfilePhoto#metadata`; zero-growth idempotent reruns (raw present and raw
purged); interruption / `SIGKILL` recovery with correct ABA claim-token
protection and sweeper reclaim; deterministic synthetic corpus (fingerprint
`ebcff28a…`, byte-identical across runs); strict generator path containment
(`Date9ja::Storage::SafeObjectKey`, symlink-escape aware, fail-closed before any
write); manifest ↔ media_v2 DB field-for-field binding (check 16, authorized set
from the Photo attachment graph, strict integer `byte_size` typing); complete
schema-driven blob-table drift authorization (check 17, NULL-safe, every row /
every column). **This is L2 rehearsal verification only. It does NOT imply
production readiness, cutover readiness, or L3 approval.**

#### L3 boundary (unchanged — separate operational/security gate)

L3 is **NOT YET READY** and is **not** the automatic next step. It is a separate
gate because it introduces concerns L2 never exercised: real legacy media /
storage access; scoped read-only production credentials; production-derived
source media; network / egress controls; credential lifecycle and destruction;
the final production-restored sanitized snapshot; and operational-runbook
requirements. L2 verification must not be read as L3 approval. No L3 work is
authorized here.

- **NOT** `PARITY_ACCEPTED` / production-ready / cutover-ready. Profile Photo
  capability remains **PARTIAL**.

### Design record (unchanged) — DESIGN ACCEPTED (2026-09-03)

Full execution design: [`MEDIA-TRANSFER.md`](MEDIA-TRANSFER.md) (Revision 4 +
FINAL canonical-identity correction). Architecture decision:
`docs/adr/0028-migration-media-byte-transfer.md` (**ACCEPTED 2026-09-03**). ADR
0027 remains Accepted.

**FINAL canonical-identity correction (Codex FINAL acceptance check — sole
remaining defect):** `canonical_content_type` (the verified detected media type)
is now a **declared** canonical-identity field and appears in the canonical
string before the UUIDv5 — because it drives `original.<ext>`. The migration
storage key is now a **total deterministic function of the complete declared
identity**:
`version v3 | source_system | source_blob_id | source_attachment_id |
destination_purpose | destination_brand | canonical_content_type` → `UUIDv5` →
`migrations/media/v3/date9ja/profile_photo_original/<uuidv5>/original.<ext>`.
Verified source content-type drift → `source_changed` (never a silent re-key).
Everything else in Revision 4 is unchanged.

**Revision 4 — three Codex FINAL-review blockers closed in-design:**
1. **Destination key stability.** Rev 3 fed `Brand#slug` + `Profile#public_id`
   into the key; not guaranteed immutable. The migration storage key now depends
   **only on immutable migration/storage identity**: `version` v3 +
   `source_system` + `source_blob_id` + `source_attachment_id` +
   `destination_purpose` + `destination_brand` (stable token). A dedicated
   `Migration::MediaTransfer::CanonicalKey.final_key` produces
   `migrations/media/v3/date9ja/profile_photo_original/<uuidv5>/original.<ext>` —
   **not** via `Media::ObjectKey.profile_photo_original`. No user id, no profile
   public id, no mutable slug. Destination `Profile`/`User` remap → `mapping_drift`
   / `binding_conflict`, reconcile explicitly, **no re-key**.
2. **Short attachment lock.** No R2 streaming / hashing / upload / libvips under
   the `MediaAttachmentRef` `FOR UPDATE`. **Phase A** (prepare/verify, no lock) →
   **Phase B** (short finalization txn: lock, recheck, create/reuse Blob,
   `build_photo!`, bind) → **Phase C** (after commit: enqueue). Two Phase-A
   workers are safe because deterministic key + cases 1–5 prevent unsafe
   overwrite; Phase B serializes domain creation/binding. The tiny blob-row
   coordination txn is distinct from the finalization lock.
3. **Abandoned processing claim.** `ProfilePhoto` gains nullable
   `processing_started_at` + `processing_claim_token` (`ProfilePhoto`
   processing-lifecycle hardening — **not** a migration table). Claim /
   stale-reclaim / finalize / failure gate on
   `processing_state == processing AND processing_claim_token == my_token` — the
   token is **required** (a bare timestamp cannot defeat the ABA race). Sweeper
   reclaims stale `processing`; recent `processing` / `ready` / non-retryable
   `failed` are left alone.

**Shared seam is FINAL:** `Profiles::PhotoUpload.build_photo!` extraction (Codex
selected it). The standalone-duplication fallback is withdrawn.

- **Legacy storage:** Active Storage `S3` service → Cloudflare R2, single ENV
  bucket, private, flat random blob keys. Checksum = MD5-base64, identical Rails
  8.1 semantics to D8N.
- **`service_name` census — RUN 2026-09-03** against `date9ja_snapshot_sanitized`
  (`127.0.0.1:55432`): **`cloudflare` = 279** photo blobs; no `local`, no
  `amazon`, no `NULL`, no mixed-service corpus. **Blocker closed.** Pass 2 still
  re-asserts this against the final production snapshot at run time.
- **Shape:** `MediaObjectRef` → `Date9ja::Snapshot::MediaLocatorSource` +
  `Date9ja::Storage::SourceReader` (host-allowlisted, HTTPS-only, no-redirect,
  read-only, run-env creds) → `Migration::MediaTransfer` (shared: verify →
  adopt-or-upload → return object-backed blob) → `Profiles::PhotoUpload.build_photo!`
  (minimal extraction, explicit position/status/visibility — **no new `Media::`
  class**) → `Migration::ReferenceMap` bind `date9ja/photo/<Photo.id> →
  ProfilePhoto` (same txn) → **after commit** `Media::ProcessProfilePhotoJob`.
  `ProfilePhoto`, `Media::PhotoPolicy`, `MediaObjectRef`, `MediaAttachmentRef`
  unchanged.
- **Recovery** (Rev 4): **no destination state on `MediaObjectRef`, no new
  migration table** (§13 verdict — inference-based recovery still sufficient).
  Migration storage key `migrations/media/v3/date9ja/profile_photo_original/<UUIDv5>/original.<ext>`
  where `UUIDv5` hashes `version v3 | source_system | source_blob_id |
  source_attachment_id | destination_purpose | destination_brand |
  canonical_content_type` — a **total function of the declared identity**, no
  user/profile/slug, no undeclared input, immutable forever. Active Storage
  adopt-or-upload cases 1–6
  (**no case-4 adoption**; every reuse re-verifies the real remote object).
  Crash/concurrency interleavings **A–U** resolved. Short per-attachment
  serialization (Phase A/B/C — no network under the lock). Orphan model = four
  concepts, ownership-proof gated, never auto-delete.
- **Reused source blob** → one destination object **per use** (copy per use);
  dedup only the source download+verify. D8N purges raw blobs post-processing so
  sharing is unsafe. (Date9ja `blob_reuse_objects = 0`.)
- **Processing:** `Media::ProcessProfilePhotoJob` gains claim / work-outside /
  finalize + **`ProfilePhoto.processing_started_at` + `processing_claim_token`**
  (nullable; processing-lifecycle hardening, not a migration table). No libvips
  inside a transaction; ABA-safe via the claim token; sweeper reclaims stale
  `processing`. Regression tests required.
- **Moderation/visibility:** no shared-model change —
  `pending→pending_review/visible`, `approved→approved/visible`,
  `rejected→rejected/hidden`.
- **Rehearsal:** distinct `date9ja_snapshot_sanitized_media_v2` artifact
  (own manifest / fingerprints / Pass-1 rerun / reconciliation baseline);
  synthetic bytes carry their own self-consistent metadata; `v1`
  (`date9ja_snapshot_sanitized`) is **not** rewritten. Production transfer path
  unchanged — no test-only branch. L1 unit / L2 full 279 synthetic / L3
  controlled real pre-cutover. `v2` not created this turn.
- **Cutover:** hybrid — bulk pre-copy + final authoritative snapshot + explicit
  delta algorithm (new / removed / blob_id / checksum / size / type / moderation /
  position / primary / owner-status / owner-mapping changes) + reconciliation.
  Zero **unexplained** failures; reviewed exceptions tracked separately. No
  automatic destructive cleanup; `source_removed` → auto-flag, never auto-delete.

**RESOLVED this round:** `service_name` census; source access (dedicated
read-only bucket-scoped R2 token, run-env only; pre-exported bundle = fallback);
quarantine/publication (bad non-primary does not block the profile; only/primary
failure flags the profile for review; never auto-pick a new primary);
cutover gate (zero unexplained failures); suspended owners (retain structurally,
no photo-specific hiding); `source_removed`-at-delta (auto-flag, never
auto-delete).

**ADR 0028 ACCEPTED (2026-09-03).** The Codex FINAL acceptance check named the
canonical-identity defect (now fixed — `canonical_content_type` is a declared
identity field) as the sole remaining blocker and accepted every other reviewed
contract. **No unresolved architecture or product decision.**

**Readiness:** PASS 2 IMPLEMENTATION: READY · L1/L2: READY AFTER IMPLEMENTATION
(build the `date9ja_snapshot_sanitized_media_v2` artifact first) · L3 real R2:
NOT YET READY. **OPEN (L3 only, execution parameters not decisions):** R2 token
custody, `STALE_THRESHOLD` / drain-timeout values, freeze-window length,
bulk-copy destination confirmation.

## Batch 1 — VERIFIED

| # | Slice | State | Committed |
|---|---|---|---|
| 1 | Date9ja brand provisioning (installer, contract, profile catalogue skeleton, NG geography, registry wiring) | VERIFIED | yes (`fd13d0d`) |
| 2 | Date9ja operational provisioning path (`brands:install_date9ja` + docker-entrypoint hook, dev/test only) | VERIFIED | no (working tree) |
| 3 | **Platform:** brand-contract-governed profile *preference* fields — completes remediation-plan slice 7 for preferences | VERIFIED | no (working tree) |

Codex corrected Date9ja photo policy `:moderate_first` → `:immediate` (verified legacy behaviour: pending photos visible, rejected excluded). **ADR 0022** accepted by review.

## Batch 2 — VERIFIED

| # | Slice | State | Committed |
|---|---|---|---|
| 4 | **Platform: D8N Migration external-reference mechanism** (`LegacyReference` + `legacy_references` table + `Migration::ReferenceMap` + `DestinationTypes`/`SourceSystems`) per ADR 0022. | VERIFIED | no (working tree) |

Review outcome (batch 2): plain `destination_type`/`destination_id` columns accepted (a deleted destination is a `dangling` reconciliation finding, not an invalid binding). `DestinationTypes` allowlist **trimmed** to the Wave-A set actually needed (`User`, `IdentityIdentifier`, `BrandMembership`, `Profile`, `ProfilePreference`, `ProfilePhoto`, `ProfileVideo`); later importer slices add their own types.

## Batch 3 — VERIFIED (Slice 5) / ADRs Accepted

Product owner resolved: retain profile video, verification, trust/reputation, and existing entitlements (no new commercial behaviour). Sensitive profile fields still blocked. bcrypt still gated on a snapshot.

| # | Slice / unit | Kind | State |
|---|---|---|---|
| 5 | **Profile video as a shared D8N Media capability** — `ProfileVideo` + `profile_videos` table, `media.profile_video.*` + `profile.video` capabilities, `BrandContract::VideoConfiguration`, `Media::VideoPolicy`, `Profiles::VideoUpload`, `Media::ProcessProfileVideoJob` (reuses `Media::VideoProcessor`), `Profiles::VideoLibrary`, `Api::V1::ProfileVideosController` (+ 4 routes + OpenAPI). Date9ja enabled; HookUs/DateZA unaffected. | ADR 0023 + implementation | VERIFIED |
| 6 | **Profile video public delivery** — `Profiles::DetailSerializer` exposes a re-authorized `video` payload on `GET /api/v1/profiles/{id}` for brands enabling `profile.video` (Date9ja only); `Profile#profile_video` (kept-scoped `has_one`), `PublicProfile` preloads the playback/poster blobs, OpenAPI `PublicProfileVideo` schema. Delivery eligibility rechecked per read (ADR 0011) via `VideoLibrary.public_payload` + `Media::VideoPolicy`. HookUs/DateZA responses carry no `video` key. | implementation | VERIFIED |
| — | **ADR 0023** — profile video as shared Media capability | ADR | **Accepted** |
| — | **ADR 0024** — shared verification-evidence architecture | ADR | **Accepted** (implementation gated) |
| — | **ADR 0025** — Trust ledger / derived reputation | ADR | **Accepted** (implementation gated) |
| — | **ADR 0026** — entitlement preservation | ADR | **Accepted** (implementation gated) |

Review amendments (batch 3), applied:

- **WEBM removed** from profile video — MP4/MOV only until the shared validator can structurally walk Matroska. Signature-only validation is not accepted.
- **Structural validation + duration enforcement moved to the async job** (whole object), matching `MessageAttachmentUpload`; attach does a cheap `ftyp` sniff + size bound only. A file that fails ends at `processing_state: failed`.
- Small fix: `lib/load_testing/synthetic_dataset.rb#cleanup!` now deletes `AnalyticsEvent` rows before profiles/users (was producing FK-violation flakiness in broad test runs); regression test added.

Slice 6 review (Codex, 2026-09-02): **ACCEPT WITH SMALL FIXES → VERIFIED.** Defence-in-depth fix applied: `Profiles::DetailSerializer#video_section` now requires the resolved `ProfileVideo.brand_id` to equal `Profile.brand_id` before serializing (`test/models/profiles_detail_serializer_video_test.rb` "a video with a mismatched brand is never delivered"). Profile video stays **PARTIAL**. Do not revisit slice 6 unless later integration requires it.

Post-batch-3 infrastructure check (2026-09-02): the SyntheticDataset cleanup FK-ordering bug is **already fixed and covered** — `AnalyticsEvent` (added by commit `4d70392`, restricting FKs to `profiles`/`users`/`sessions`) is deleted first in `cleanup!`, sessions after it in `delete_identity_activity!`; `synthetic_dataset_test.rb` asserts `AnalyticsEvent.where(user_id:).count == 0` after cleanup and the test is green (3 runs, 41 assertions). No new restricting FK to `users`/`profiles`/`sessions` in the recent Product Intelligence work is left unhandled. Nothing to do here. The two broad-suite failures seen in the slice-6 run (DateZA welcome-email `href=` assertion; `LocationSearchControllerTest` rate-limit parallel flake, passes in isolation) are unrelated and pre-existing.

### Still gated (not started)

- **Verification / Trust / Entitlements**: architecture accepted (ADRs 0024–0026); implementation waits on the ADR 0011 human gates and the `DECISIONS.md` "Mixed" rows (evidence retention + provider + portability; user-visible trust presentation).
- **bcrypt / session transition**: approved sanitized snapshot + data dictionary (ops action).
- **Complete Date9ja profile / conditional onboarding**: sensitive-field product rows.
- **Profile video: legacy importer + migrated-media reconciliation** — **pass 1 (media preflight) VERIFIED (Codex 2026-09-03: ACCEPT WITH SMALL FIX)**; pass 2 (byte transfer + `ProfileVideo` creation + L2 synthetic-corpus rehearsal) NOT STARTED — may now be PLANNED. Public delivery wiring is **done** (slice 6, VERIFIED).

Profile video remains **PARTIAL** — public delivery wiring done, pass-1 media preflight VERIFIED; full parity still needs pass-2 byte transfer + L2 (pass 2 must derive authoritative duration from the media container), migrated-media reconciliation, and the frontend/API + parity acceptance journeys. Not `PARITY_ACCEPTED`.

### Sanitized snapshot milestone — VERIFIED FOR ENGINEERING USE (2026-09-02)

The operator restored a 2026-09-02 Date9ja production backup into an isolated
PG17 instance, ran `scripts/date9ja/sanitize_snapshot.sql` +
`verify_sanitized_snapshot.sql` (verifier **PASSED, 0 violations**), packaged
`date9ja_sanitized_20260902.dump`, and confirmed a full `pg_dump`/`pg_restore`
round trip preserves every row count and the pristine-vs-sanitized relationship
fingerprints (users, likes, matches, messages incl. `match_id`/`sender_id`/
`reply_to_id`, profile_views, blocks). Record: `SNAPSHOT-RUNBOOK.md` §10.

Classification: **SANITIZED SNAPSHOT REHEARSAL ARTIFACT — VERIFIED FOR
ENGINEERING USE.** Not a cutover snapshot.

**What the milestone unblocked**

| Now unblocked | Why | State |
|---|---|---|
| Reconciliation **source census** — `scripts/date9ja/source_census.sql` | Needs only aggregate source counts, which now exist and are operator-verified | **Implemented this batch** (below) |
| Importer **dry-run capability** for the operator | A real-shaped, FK-intact, PII-free dataset the operator can run an importer against locally | Enabled — no importer to run yet |
| `RECONCILIATION.md` source column | Headline counts filled; census fills the rest | Updated this batch |

**What the milestone did NOT unblock**

| Still blocked | Gated on |
|---|---|
| bcrypt credential compatibility proof (Wave A slice 3, first half) | **VERIFIED 2026-09-02 by operator** — real `$2a$12$` account passed through the D8N password/session path with byte-identical storage; sanitized artifact remains insufficient for this proof. |
| Identity + membership + profile importer (first `Migration::ReferenceMap` consumer) | **One blocker left:** the bcrypt proof — its credential step copies the hash verbatim, which `AUTHENTICATION.md` says must be *proven* first (`SNAPSHOT-RUNBOOK.md` §6, procedure defined, awaiting operator run). ~~Import execution model~~ — **RESOLVED 2026-09-02: restored scratch PostgreSQL database** (`DECISIONS.md`). Reader shape is now fixed: `restore → Date9ja source adapter → shared `Migration` primitives → `ReferenceMap` → D8N ID/Profile → reconciliation`. |
| Media importer (Wave A slice 5 sub-slice) | Transitively — media attaches to imported profiles; needs the identity importer first. |
| Complete Date9ja profile capabilities / sensitive fields (Wave A slice 4) | `DECISIONS.md` product rows (tribe/ethnicity/denomination/genotype/preferred tribes — "Awaiting Uchechi"). The sanitizer nulled all of these, so the artifact cannot inform them either. |
| Verification / Trust implementation (Wave A slice 6) | `DECISIONS.md` "Mixed" rows (evidence retention + provider + portability; user-visible trust presentation) + ADR 0011 human gates. |
| Entitlements implementation (Wave A slice 7) | ADR 0026 accepted and the product row is RESOLVED (retain all, no new pricing), but there is no PAY/Entitlements primitive or importer to carry the state yet — follows the identity importer. |

### Snapshot reconciliation census + schema-signature v2 — VERIFIED (2026-09-02)

Independent review of the census first returned **CHANGES REQUESTED**
(schema-fingerprint contract insufficient; census omissions; grouped enum
leakage). All three addressed; Codex re-review verdict **ACCEPT WITH SMALL FIXES —
no substantive findings remain**. Both scripts and the v2 guard consolidation are
now **VERIFIED**.

| Unit | Kind | State |
|---|---|---|
| `scripts/date9ja/schema_signature.sql` — shared canonical source-schema signature (v2), `\ir`-included verbatim by the sanitizer, verifier and census. Asserts exact 51-table set, 574-column count, and a full structural `md5` over `table_schema, table_name, ordinal_position, column_name, data_type, udt_name, is_nullable, char_max_length, numeric_precision/scale, datetime_precision, column_default` (sequence defaults normalised). Signature `41a653a8d4c25621071fb76e6e59fbc0`. | Date9ja source-adapter infrastructure | **VERIFIED** |
| `scripts/date9ja/source_census.sql` — read-only (`READ ONLY` txn, always rolled back), v2-guarded. 97 measures: identity/lifecycle, verification/trust state + ledger sums, entitlements, media by moderation/type, relationship graph, notifications, extended-capability counts, attribution shape, retained Careers/Feedback, phone verification, rewind. Every `value:count` breakdown emits allowlisted buckets only; unknown/adversarial values fold to `OTHER` — a raw source value is never echoed. | Date9ja source-adapter infrastructure | **VERIFIED** |
| Sanitizer / verifier v2 guard consolidation (`\ir schema_signature.sql` replacing the inline v1 blocks) | migration infrastructure | **accepted** by re-review; both scripts re-tested green under v2 |

v1 → v2: the v1 guard (`a317e7fb…`) hashed only `table_name.column_name`, so a
type-only / nullability-only / ordinal-only change could pass. Proven in review:
`int→bigint`, a `DROP NOT NULL`, and a pure column reorder each leave the v1
fingerprint **identical** while v2 aborts on all three.

Self- and adversarial verification (schema-only artifact + synthetic fixtures,
never the snapshot DBs): 15/15 checks pass — exact schema → PASS; wrong DB,
missing table, extra table, added column, renamed column, changed type, changed
nullability, reordered columns → all FAIL CLOSED under v2; mutation under
`READ ONLY` → rejected; empty tables → census emits all 97 rows; malformed enum
values (`777`, `-3`, `SketchyModel<script>`, `evil/haxx; DROP TABLE…`,
`weird_leaked_value user@secret.com`, `totally_bogus_status`) → output contains
`OTHER` only, verified by a raw-value/PII sweep of the output; ordinals unique and
monotonic; all 44 referenced tables + all referenced columns exist. Sanitizer +
verifier re-run under v2: sanitize `COMMIT` + post-checks passed, verifier
**PASSED (0 violations)**. **No production access; real snapshot not accessed.**

### Phase 1 unblocked-work assessment (2026-09-02, refreshed post-milestone)

After slice 6 was verified and the snapshot milestone landed, every remaining
Phase 1 implementation path was re-checked against `MASTER-PLAN.md`,
`PARITY-BUILD-PLAN.md`, `DECISIONS.md`, and `CAPABILITY-PARITY.md`:

| Wave A slice | Status | Gated on |
|---|---|---|
| 1 brand provisioning | done | — |
| 2 legacy reference mechanism | done | — |
| 3 bcrypt / session transition | **credential step VERIFIED + READY** | Format discovery done (operator, 2026-09-02): **one bucket — `$2a$` cost 12, 288 accounts, 0 malformed, no Devise pepper**. Proof `scripts/date9ja/bcrypt_proof.rb` **executed by the operator 2026-09-02 against a real `$2a$12$` account → `$2a$ 12 PASS`** (verified through `PasswordEngine.matches?` / `PasswordLogin` session / byte-identical stored hash). Manifest deleted after the run. Session/recovery design follows `AUTHENTICATION.md` (fresh D8N session on first login; one-time secure recovery only on a hash failure). Import execution model **RESOLVED** (restored scratch DB). |
| 4 complete Date9ja profile capabilities / conditional completion / privacy serialization | **blocked** | sensitive-field product rows (tribe/ethnicity/denomination/genotype/preferred tribes) + which fields are required for completion — all "Awaiting Uchechi" in `DECISIONS.md` |
| 5 shared media / profile-video — owner CRUD + public delivery | done | photo importer pass 1 + pass 2 + L2 VERIFIED; **video importer pass 1 VERIFIED (Codex 2026-09-03: ACCEPT WITH SMALL FIX)**; video pass 2 + L2 not started (may be planned) |
| — reconciliation **source census** | **done** | `scripts/date9ja/source_census.sql`, VERIFIED (independent re-review) |
| 6 verification & trust records/status history | **blocked** | `DECISIONS.md` "Mixed" rows: evidence retention + provider + portability; user-visible trust presentation |
| 7 PAY / Entitlements primitives | **blocked** | no PAY/Entitlements primitive or importer yet; follows the identity importer (product row RESOLVED, ADR 0026) |

The snapshot milestone unblocked the reconciliation source census and the
structural identity importer rehearsal. The **import execution model** is
RESOLVED (2026-09-02): restored scratch PostgreSQL database, not a live
connection, NDJSON/CSV only as later diagnostics. The identity + membership +
non-sensitive profile importer is now independently **VERIFIED** for its
bounded rehearsal scope. Isolated-fork work on Date9ja discovery/profile
catalog is still not safe to start (ranking/location semantics +
sensitive-field decisions are product calls).

Next action: **DONE (2026-09-02)** — Uchechi ran the bcrypt compatibility proof
(`BCRYPT_PROOF_MANIFEST=… bin/rails runner -e test scripts/date9ja/bcrypt_proof.rb`)
with a real operator-owned `$2a$12$` Date9ja account → `$2a$ 12 PASS`. Wave A
slice 3's credential step is `READY`. Current batch: **identity + membership +
profile importer** (first `Migration::ReferenceMap` consumer, reading a restored
scratch DB via the Date9ja source adapter, non-sensitive fields only) — see the
"Wave A slice 3 — identity importer" section below. Next after that: photo/video
importer → importer reconciliation against `source_census.sql`. Verification/Trust
implementation stays gated on the `DECISIONS.md` "Mixed" rows regardless.

**Importer dependency reassessment (2026-09-02):**

| Dependency | State |
|---|---|
| `Migration::ReferenceMap` + `DestinationTypes` (`User`, `IdentityIdentifier`, `BrandMembership`, `Profile`, `ProfilePreference`, `ProfilePhoto`, `ProfileVideo`) | done / VERIFIED |
| Import execution model | **RESOLVED** — restored scratch PostgreSQL DB |
| Date9ja source-schema signature guard (v2) | done / VERIFIED — reusable by the adapter's schema preflight |
| Reconciliation source census (97 measures) | done / VERIFIED — importer reconciles against it |
| Sanitized rehearsal artifact (real-shaped, FK-intact, PII-free) | VERIFIED FOR ENGINEERING USE — importer dry-run target |
| Date9ja email/phone normalization contract | in `AUTHENTICATION.md` (normalize once, no collision merge) — READY |
| **bcrypt compatibility proof** | **VERIFIED (2026-09-02)** — operator ran `scripts/date9ja/bcrypt_proof.rb` with a real `$2a$12$` account → `$2a$ 12 PASS`; legacy digest safe to copy verbatim |
| Date9ja `users` → D8N field mapping for profile/lifecycle/entitlement | `SNAPSHOT-RUNBOOK.md` §4 preserve/redact/drop lists — READY for non-sensitive fields; sensitive fields stay out (product rows) |
| Date9ja source adapter / snapshot reader (Date9ja-specific adapter boundary + shared `Migration` orchestration primitive) | **VERIFIED** — schema-guarded and throwaway-test-runtime fenced |

Conclusion: the bcrypt proof passed (2026-09-02), and the first structural
identity + membership + non-sensitive profile slice is **VERIFIED** for an
isolated sanitized rehearsal only. It is not `PARITY_ACCEPTED`, production
ready, or cutover ready. Next: photo/video importer → importer reconciliation
against `source_census.sql`.

### Snapshot sanitizer artifacts — VERIFIED (independent review 2026-09-02)

| Unit | Kind | State |
|---|---|---|
| **Sanitized-snapshot sanitizer** — `scripts/date9ja/sanitize_snapshot.sql` (deterministic, guarded, fail-closed in-place transform), `scripts/date9ja/verify_sanitized_snapshot.sql` (fail-closed verifier), `SANITIZATION-CONTRACT.md` (all 51 tables / 574 columns classified). Now guarded by the shared **v2** schema signature (`schema_signature.sql`), idempotency guard, `date9ja_snapshot_tmp` refusal, ack-token gate. | migration infrastructure | **VERIFIED** — independent review verdict **B (safe to execute after small fixes; fixes applied)**; operator-executed 2026-09-02 **under schema guard v1**, verifier PASSED, round-trip reconciled (see milestone section above). v2 strengthening is for future runs. |

**Impact on the 2026-09-02 sanitized artifact:** none. It was produced and
verified under schema guard v1. v1 already guarantees no table/column was
added, removed or renamed; the residual v1 gap (type/nullability/ordinal drift
between the classified schema and the sanitized DB) cannot apply here because
both derive from the **same** 2026-09-02 backup — there is no version skew. The
artifact **remains acceptable for engineering rehearsal**; **no new
raw-production sanitization run is required.** Recommended non-blocking follow-up:
the operator runs the read-only v2 one-liner against `date9ja_snapshot_sanitized`
(`SNAPSHOT-RUNBOOK.md` §3) to confirm `41a653a8…` and retroactively close the gap
at zero cost.

Independent review outcome: **B — SAFE TO EXECUTE AFTER SMALL FIXES**; the small
fixes were applied during review and re-verified. Changes made in review:
coordinates dropped to NULL (was 1-dp round, R6); sensitive religious/ethnic/tribal
attributes (`tribe`, `denomination`, `state_of_origin`, `nationality`, `religion`,
`ethnicity`, `intertribal_marriage_openness`, `polygamy_openness`, `is_nigerian`)
dropped to NULL (was hashed-bucket / PRESERVE, R1); `notification_preferences` /
`email_notification_preferences` reduced to boolean-valued entries only (was
PRESERVE, R4); `career_jobs` long free-text redacted (R5);
`daily_life_entries.mood`/`focus_tag` and `company_journal_entries.title`
redacted; verifier redaction/pseudonymisation coverage widened to ~40 more
columns + a non-boolean-preference assertion + coordinate-null assertion.
R2 / R3 / R7 accepted as-is (stay destroyed/emptied — no current test justifies
richer treatment; a later gated importer needs its own approved extract).

Self- and adversarial verification: loaded the operator's safe schema-only
artifact into throwaway local PG DBs (never the snapshot DBs — separate isolated
PG17 instance, untouched), confirmed the embedded column fingerprint matches a
real `information_schema` build, ran sanitizer + verifier against synthetic
fixtures of realistic-looking PII (incl. array/scalar/mixed notification-pref
JSON) — clean pass — and confirmed every guard and every added verifier assertion
fires on tampered data. Independent review completed (verdict B, fixes applied);
operator executed it against `date9ja_snapshot_sanitized` on 2026-09-02 — verifier
PASSED, `pg_dump`/`pg_restore` round trip reconciled. **The builder never executed
it and never accessed a real snapshot. No production access.**

## Slice 1 scope delivered

- `Brands::Date9jaInstaller` (mirrors `Brands::DatezaInstaller`), wired into `Brands::Provisioner` and `bin/rails 'brands:provision[date9ja]'`.
- `D8n::Platform::Brands::Date9ja` brand contract, registered in `D8n::Platform::BrandRegistry`. No discovery / match / chat / opener capability enabled.
- `Profiles::Date9jaProfileCatalog` — non-sensitive skeleton only (no faith/ethnicity/tribe/denomination/preferred-tribes/genotype).
- `Geography::NigeriaCatalog` + `bin/rails geography:seed_nigeria` — shared platform geography.

## Slice 2 scope delivered

- `brands:install_date9ja` rake task (mirrors `brands:install_dateza`): maps `DATE9JA_API_HOST` to the `date9ja` brand idempotently.
- `bin/docker-entrypoint` provisions Date9ja before serving **only** when `DATE9JA_API_HOST` is set; inert otherwise.
- **Not** added: any production host mapping in `config/deploy.production.yml`. Date9ja production routing stays gated on the cutover decision.

## Slice 3 scope delivered (platform, not Date9ja-specific)

- `Profiles::FieldPolicy` gains `writable_preference_fields`, `validate_preference_write!`, `preference_enabled?` — same `brand.profile_completion_requirements` source as `Profiles::Configuration`.
- `Api::V1::ProfilePreferencesController#update` rejects known preference fields the brand has not enabled (`invalid_preference_fields`, 422) and permits only the enabled set; `#show`/`#update` payload emits only enabled preference fields plus the stable `id`/`profile_id`/`brand` envelope.
- OpenAPI: `InvalidPreferenceFields` schema, `PreferenceValidationFailed` response, `ProfilePreferencesUpdate` note.
- HookUs unchanged (no explicit `enabled_preference_fields` → broad contract retained, exactly as for profile scalars). DateZA now enforces its explicit 4-field preference contract (`country`/`relationship_intent` rejected — both are unread by any backend logic and already absent from DateZA's advertised config).

## Slice 4 scope delivered (platform, not Date9ja-specific)

- `db/migrate/20260902120000_create_legacy_references.rb` + `LegacyReference` model: `(source_system, source_entity, source_id) → (destination_type, destination_id)` binding, nullable `brand_id`, `source_fingerprint`/`importer_version` metadata. DB unique indexes in **both** directions; binding columns immutable after create (`before_update` guard); `redacted_key` for safe logging.
- `Migration::ReferenceMap` — `resolve`/`resolved` (read-only), `bind!` (idempotent, transactional, row-locking, immutable, concurrency-safe via both-direction reload), `dangling` (reconciliation helper).
- `Migration::DestinationTypes` (brand-owned vs platform allowlist, fail-closed) and `Migration::SourceSystems` (`date9ja` only; entity by format).
- No routes, no consumer API, no importer, no data mapping. Raw legacy IDs never leave the table.

## Slice 5 scope delivered (platform, not Date9ja-specific)

- `db/migrate/20260902130000_create_profile_videos.rb` + `ProfileVideo` — brand-profile-owned placement (one per profile, partial-unique index), `has_one_attached :video` (raw) / `:playback` / `:poster`, `status`/`visibility`/`processing_state` enums + soft deletion. Mirrors `ProfilePhoto`.
- `media.profile_video.{upload,attach,process,deliver,delete,moderation}` + `profile.video` capabilities (all `available`); `media.video` stays `planned`.
- `BrandContract::MediaConfiguration` gains an optional `video:` (`VideoConfiguration`). Absent ⇒ no profile video. Existing HookUs/DateZA contracts + tests unaffected.
- `Media::VideoPolicy` (brand video config reader, fail-closed) mirrors `Media::PhotoPolicy`.
- `Profiles::VideoUpload` — control/data-plane direct-to-R2, real-object verification, ISO-BMFF container check (reuses `Media::VideoContainerValidator`), **server-enforced duration limit** (Date9ja trusted the client field; D8N does not).
- `Media::ProcessProfileVideoJob` — reuses `Media::VideoProcessor` for the H.264/AAC playback rendition + poster; purges the raw; idempotent, deletion-tolerant, transient-retry, terminal-fail.
- `Profiles::VideoLibrary` + `Api::V1::ProfileVideosController` — `GET/POST/DELETE /api/v1/profile/video`, `POST /api/v1/profile/video/uploads`; 404 for a brand whose contract does not enable `profile.video`.
- Date9ja config: `initial_visibility: :immediate`, `max_duration_seconds: 60`, `max_byte_size: 50 MB` (legacy parity).

## Gated questions carried forward (do not invent answers)

- Should the Date9ja foundation contract enable the generic profile-participant `match.*` / `chat.*` primitives now (as DateZA does) with discovery still deferred? — Coder question for Slice 1 review.
- `PERSISTENT_LOCATION` is accepted for this foundation slice: Date9ja stores a persistent city/coordinate location rather than a freshness-window activity signal. Discovery remains gated independently.
- Photo publication policy, verification gates, sensitive-field retention/mapping, entitlements — all in `DECISIONS.md`.

See [MASTER-PLAN.md](MASTER-PLAN.md) for phase authority, [PARITY-BUILD-PLAN.md](PARITY-BUILD-PLAN.md) for capability sequencing, and [FEATURE-PARITY-ACCEPTANCE.md](FEATURE-PARITY-ACCEPTANCE.md) for cutover journeys.
