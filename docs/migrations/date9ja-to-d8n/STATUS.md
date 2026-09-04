# Date9ja → D8N Status

- Current phase: **Phase 1 — Shared Platform Foundations** (Wave A)
- Current capability: **Migrated-account authentication transition + recovery/reactivation (Wave A Step 3 closeout) — IMPLEMENTED / SELF_VERIFIED 2026-09-04, READY FOR FEATURE-BOUNDARY CODEX REVIEW** (`AUTH-TRANSITION.md`). Earlier: Batches 2 & 3 reviewed; sanitized snapshot milestone VERIFIED; reconciliation census + schema-signature v2 VERIFIED (independent review); import execution model RESOLVED; **bcrypt compatibility proof VERIFIED (2026-09-02, operator ran `scripts/date9ja/bcrypt_proof.rb` against a real `$2a$12$` account → `$2a$ 12 PASS`)**; identity + membership + non-sensitive profile importer — implementation reviewed + **operator rehearsal VERIFIED (2026-09-03)** against `date9ja_snapshot_sanitized` (288 source rows → 280 imported / 8 skipped `source_soft_deleted` / 0 failed; second pass 280 already_imported / 0 created; source reconciliation balanced); **profile-photo pass 2 implementation VERIFIED + L2 synthetic-corpus rehearsal VERIFIED (Codex independent review 2026-09-03: FINAL VERDICT ACCEPT)**; **profile-video pass 1 (media preflight) VERIFIED (Codex 2026-09-03: ACCEPT WITH SMALL FIX — documentation correction completed), sanitized rehearsal 35/35 preflighted + idempotent; legacy `duration_seconds` NULL for all 35 (no row known to exceed the limit; actual duration unproven — pass 2 must derive it from the container)**. **NOT PARITY_ACCEPTED, NOT production-ready, NOT cutover-ready. L3 NOT YET READY.**
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

## Wave A Step 3 closeout — migrated-account authentication transition + recovery/reactivation — **IMPLEMENTED / SELF_VERIFIED (2026-09-04)**

Completes Wave A Step 3. **No Date9ja-specific auth infrastructure** — the
migrated account is an ordinary D8N identity driving the shared services
(`Identity::PasswordLogin` / `Session` / `SessionAuthenticator` /
`RecoveryRequester` → `RecoveryVerifier` → `PasswordReset` /
`Accounts::DeactivateAccount` ↔ `Identity::AccountReactivation`). Date9ja
behaviour lives only in the brand contract
(`auth_methods`, `phone_country_calling_code`, email/SMS delivery config).
Full reference: [`AUTH-TRANSITION.md`](AUTH-TRANSITION.md).

**Code:**

| Unit | Change |
|---|---|
| `Date9ja::Import::IdentityImport` / `FieldMapping` | Unusable legacy digest + an **operable recovery channel** (`FieldMapping.operable_recovery_channel?` = **verified email**; a verified phone alone does NOT count — the shared runtime resolves the password credential through the requested identifier and it is bound to email) → **recovery-required credential** (active password credential, **no `CredentialPasswordHash`**). Otherwise → **fail closed** (`credential_hash_unusable`, no unreachable account). |
| `IdentityImport#credential_completeness` | Rerun verdict `:complete` / `:incomplete` / `:corrupt_credential`. A usable-legacy-digest credential is complete only with a **supported** bcrypt hash (`BCRYPT_RE` + `BCrypt::Password.new`) — verbatim legacy copy OR a valid member replacement (a re-run never clobbers a reset password). Missing hash → `:incomplete`; unsupported hash → `:corrupt_credential` (`credential_hash_corrupt`, fail closed). |
| `Date9ja::Import::Reconciliation` | New `credentials_recovery_required` counter + `credential_recovery_required` / `credential_hash_corrupt` reason codes. `password_hashes_created` stays exact. |
| `Date9ja::Import::AuthTransitionCheck` (new) | Drives a migrated account through the whole signed-out auth journey against the real shared services; deterministic PII-free `to_h` tally. `Subject.recovery_expected` models the no-operable-channel case. `parse_manifest` fails closed on empty / unknown-lifecycle. `lifecycle_supported` check + zero-subject run is not a pass. Broad companion to `scripts/date9ja/bcrypt_proof.rb`. |
| `lib/tasks/date9ja_import.rake` | `date9ja:verify_auth_transition` — **DB fence** `Date9ja::Snapshot::Connection.assert_runtime_safe!` (accepted disposable-DB contract, refuses before any check), manifest validation via `parse_manifest`, secret-scrubbed output. |

**Product decision closed by source analysis (no new blocker):** Date9ja
self-deleted accounts have **no consumer undelete/reactivation route**
(`active_for_authentication?` false; 30-day grace → `AccountHardDeleteJob`
anonymisation). Date9ja "account recovery" = password reset only, which D8N
preserves. The importer skipping `deleted_at` rows is parity-correct.
`AccountReactivation` covers D8N-native self-deactivation only.

**Evidence:**

- **L1** — `auth_transition_rehearsal_test.rb`: import → full auth journey per
  lifecycle (login / brand session / cross-brand rejection / logout / recovery→reset / reactivation) across active / suspended / recovery-required; fail-closed on unusable
  digest + no channel; PII-free tally.
- **L2 (scaled synthetic)** — `auth_transition_l2_rehearsal_test.rb`: 19-row
  cohort spanning every lifecycle + credential edge → import, reconciliation
  balance, pre-sign-in idempotency (0 rows changed), full `AuthTransitionCheck`
  (0 failures), post-recovery re-run (member-set passwords never clobbered).
- **Operator L2 tool** proven (2026-09-04) against a compliant throwaway DB with
  3 synthetic imported accounts: all pass / exit 0 / PII-free; unknown lifecycle,
  empty manifest, and a non-approved `DATABASE_URL` (even with `RAILS_ENV=test`)
  each refused with a clear non-secret abort **before any check**.
  **Real-seed-account operator L2 (real cost-12 + real plaintexts) NOT run —
  operator task, like `bcrypt_proof.rb`.**
- bcrypt cost-12 byte compatibility VERIFIED separately (`bcrypt_proof.rb`,
  2026-09-02).

**Semantic difference surfaced (Phase-5 parity-acceptance question, not a
blocker):** an unverified email can authenticate by password post-migration but
is not a signed-out reset channel (ADR 0012); Date9ja's Devise `:recoverable`
allowed reset to an unconfirmed email. 79 / 288 census accounts are unconfirmed.

**Tests / gates (2026-09-04):** `test/domains/date9ja` + `test/domains/migration`
+ `test/models/migration` + `test/controllers/api/v1/auth` green; identity +
brands + profiles + auth controllers + account-deactivations regression green;
identity-import + auth-transition (L1 + scaled L2) focused 28 / 172 / 0.
RuboCop clean; `bin/rails zeitwerk:check` "All is good!"; Brakeman 0 warnings;
`git diff --check` clean.

**Feature-boundary Codex review (2026-09-04): CHANGES REQUESTED — overall
architecture PASSED; 4 bounded findings fixed without redesign:**

1. (HIGH) phone-only recovery was not operational — shared recovery resolves the
   password credential through the requested identifier (bound to email). Fix:
   `operable_recovery_channel?` = verified email only; verified-phone-only →
   fail closed. No Date9ja-specific cross-identifier recovery invented.
2. (MED) `credential_hash_consistent?` too weak (`present?`). Fix:
   `credential_completeness` — supported bcrypt required (`BCRYPT_RE` +
   `BCrypt::Password.new`); missing → `:incomplete`, unsupported →
   `:corrupt_credential` (`credential_hash_corrupt`), member replacement →
   `:complete`; re-run still never clobbers.
3. (MED) operator DB fence — reuse `Connection.assert_runtime_safe!`
   (accepted disposable-DB contract), refuses before any check.
4. (MED) manifest validation — `parse_manifest` rejects empty / unknown
   lifecycle before any check; zero-subject run is not a pass.

Retest: identity-import + auth-transition focused 35 / 0; `test/domains/date9ja`
+ migration + identity + brands + auth controllers + bcrypt-proof 512 / 0; auth
controllers + identity + account-deactivations + dateza-controls 132 / 0.
RuboCop / Zeitwerk / Brakeman clean; `git diff --check` clean.

**Lifecycle:** IMPLEMENTED / SELF_VERIFIED, Codex findings addressed — awaiting
narrow fix confirmation. NOT `VERIFIED`, NOT `PARITY_ACCEPTED`. Frontend/mobile
adapters, Devise error-envelope mapping, API contract surface, and the
parity-acceptance journey are **Phase 5**.

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
| Profile-video **pass 2A** (source bytes → authoritative verification + duration → deterministic destination adoption) | **IMPLEMENTED / SELF_VERIFIED (2026-09-04) — NOT independently reviewed, NOT `VERIFIED`.** See "Pass 2A" section below. |
| Profile-video **pass 2B** (domain binding + processing + playback/poster validation) | **IMPLEMENTED / SELF_VERIFIED (2026-09-04) — NOT independently reviewed, NOT `VERIFIED`.** See "Pass 2B" section below. |
| Profile-video **pass 2C** (deterministic synthetic 35-video L2 corpus + verifier + full isolated rehearsal + interruption/adversarial evidence) | **IMPLEMENTED / SELF_VERIFIED + OPERATOR_L2_COMPLETE (2026-09-04).** Independent CODE review ACCEPTED (Codex). Operator L2 evidence (`VIDEO-L2.md` §12) NOT yet independently reviewed. NOT `VERIFIED`. |

### Profile-video pass 2 — architecture closeout (2026-09-03, pre-2A)

**ADR 0029 ACCEPTED.** The Codex-verified `Migration::MediaTransfer` spine is
generalized across media kinds via a small injected `MediaKind` strategy — **not**
a separate video framework. `MediaKind::Image` reproduces today's Profile Photo
behaviour byte-for-byte; locking, canonical identity structure, `AdoptOrUpload`
state machine, deterministic recovery, and `ReferenceMap` semantics are **not**
parameterized. ADR 0028 remains the historical accepted image architecture.

**Refined duration contract (ADR 0029).** Pass 2 **Phase A** derives authoritative
duration BEFORE any destination adoption/upload, outside DB locks:
source bytes → bounded local temp → checksum/byte-size verify → container verify
(`Media::VideoContainerValidator`) → authoritative duration (ffprobe via a new
thin `Media::VideoProcessor.probe`) → policy check → **only then** deterministic
destination adoption. Duration unreadable → FAIL CLOSED `quarantined` /
`duration_unreadable`. Duration > brand limit → FAIL CLOSED `quarantined` /
`duration_over_limit`. Neither creates a destination blob, `ProfileVideo`,
`ReferenceMap` binding, or processing job. `Media::ProcessProfileVideoJob`
re-validates duration during processing as defence in depth. The
grandfather / trim-reencode / quarantine-remove product decision stays
evidence-gated (`DECISIONS.md`).

**ffmpeg/ffprobe evidence (2026-09-03).** `ffmpeg`/`ffprobe` 9.0.1 on `PATH` in
local dev; the production image installs them (`Dockerfile` line 23, explicit
comment). `Media::VideoProcessor` already shells out to both and has no fallback
(`Errno::ENOENT` → `VideoProcessor::Error` → terminal `processing_state: failed`);
its tests stub `VideoProcessor.call`, so CI does not require the binaries.
`Media::VideoContainerValidator`'s "not available in this deployment image"
header comment is stale (contradicts the Dockerfile) — a one-line comment fix is
folded into Pass 2B.

**Synthetic L2 direction (Pass 2C).** Generate the deterministic synthetic video
corpus with the already-required ffmpeg toolchain from fixed inputs/options
(e.g. `lavfi testsrc` + a fixed CFR/GOP/`-c:v libx264 -preset ultrafast` recipe,
patched deterministically), independently verified for determinism, valid
container, valid codec, expected duration, manifest ↔ DB binding, complete
blob-table drift, strict `byte_size` typing, NULL-safe equality and path
containment — rather than a bespoke H.264 encoder / ISO-BMFF writer. If ffmpeg
output cannot be made byte-identical across environments, fall back to a small
set of checked-in reference clips patched deterministically.

**Slices (design only, not implemented):**

- **Pass 2A** — `MediaKind` (image path unchanged) + `MediaKind::Video` +
  `Media::VideoProcessor.probe` + `Date9ja::Snapshot::VideoLocatorSource` +
  `Date9ja::Import::VideoTransfer` Phase A + `VideoTransferReconciliation`.
  source bytes → authoritative verification → authoritative duration → policy
  acceptance → deterministic destination adoption. **No `ProfileVideo`.**
- **Pass 2B** — `Profiles::VideoUpload.build_video!` + Phase B/C (`ProfileVideo`
  create + exact `ReferenceMap` binding + processing + playback/poster +
  `Media::PlaybackDerivative.valid?`) + video processing claim-token hardening +
  `Media::ProfileVideoProcessingSweeper` + recovery/idempotency state machine.
- **Pass 2C** — deterministic synthetic video artifact + verifier + full
  isolated L2 rehearsal + interruption/adversarial evidence.

**Recommended first slice: Pass 2A.** Repository state verified
safe to begin (HEAD `25dbdb1` contains the VERIFIED Pass-1 implementation + its
closeout doc corrections; working tree clean).

### Profile-video pass 2A — IMPLEMENTED / SELF_VERIFIED (2026-09-04)

Implements ONLY ADR 0029 Pass 2A: legacy `ProfileVideo` source bytes → bounded
source read → integrity verification → ISO-BMFF container verification →
authoritative ffprobe duration → Date9ja duration-policy acceptance →
deterministic destination adoption. **Maximum success state for a video is a
destination ACTIVE STORAGE ORIGINAL BLOB** — lifecycle
`SOURCE_ACCEPTED / DESTINATION_ADOPTED`, **never `transferred`.**

**MediaKind generalization (ADR 0029).** `Migration::MediaTransfer::MediaKind`
with `MediaKind::Image` (default everywhere — pre-0029 Profile Photo behaviour
byte-for-byte, accepted reason code `not_an_image` preserved) and
`MediaKind::Video`. The kind parameterizes ONLY: accepted content types
(`video/mp4`, `video/quicktime`), byte ceiling (`Media::VideoPolicy`
`DEFAULT_MAX_BYTE_SIZE`), magic/`ftyp` detection, structural container
validation + authoritative duration derivation, and the remote re-verification
body (container re-validation, no ffprobe on reuse). **Unchanged:** `LockGuard` /
`RemoteIOUnderLock`, canonical identity structure, `VERSION =
migration-media-transfer:v3`, `KEY_NAMESPACE`, `AdoptOrUpload` cases 1–6 / the
A→B→C shape, deterministic recovery, `ReferenceMap`, concurrency. The ONLY
canonical-identity change is two rows added to `CanonicalKey::EXTENSIONS`
(`video/mp4 → mp4`, `video/quicktime → mov`). `MediaTransfer.call` /
`AdoptOrUpload.call` take `media_kind:` defaulting to `MediaKind::Image`.

**Canonical identity for video:** `version: migration-media-transfer:v3`,
`source_system: date9ja`, `destination_purpose: profile_video_original`,
`destination_brand: date9ja`, `canonical_content_type:` authoritatively detected.
Destination shape
`migrations/media/v3/date9ja/profile_video_original/<uuidv5>/original.<ext>`.
Source content-type drift (detected ≠ preflighted) fails closed `source_changed`.

**`Media::VideoProcessor.probe(bytes)`** — new thin ffprobe-only class method
(argv array via Open3, `PROBE_TIMEOUT` wall clock, no transcode / derivative /
upload / `ProfileVideo` mutation). Extracted from the existing private `probe!`;
existing `VideoProcessor.call` processing behaviour untouched (regression tests
green). Absent ffprobe / unparseable output / timeout → fail closed
`duration_unreadable`.

**Authoritative Phase-A order (all outside DB locks):** source bytes → byte
ceiling enforced mid-stream → exact byte-size vs `MediaObjectRef` → exact MD5 vs
`MediaObjectRef` → `ftyp` type detect → detected == preflighted type →
`Media::VideoContainerValidator` (box-tree + codec gate) → `VideoProcessor.probe`
→ authoritative duration → Date9ja `VideoPolicy` duration gate → ONLY THEN
`CanonicalKey.final_key` + `AdoptOrUpload`. Unreadable duration →
`quarantined` / `duration_unreadable`; over the brand limit →
`quarantined` / `duration_over_limit` — neither creates a destination blob,
`ProfileVideo`, `ReferenceMap` binding, or job. The grandfather / trim /
quarantine-remove product decision (PD-2) stays evidence-gated (`DECISIONS.md`).

**`Date9ja::Snapshot::VideoLocatorSource`** — SchemaGuard-verified,
column-allowlisted (`b.id, b.key, b.service_name`), filtered to
`record_type='ProfileVideo' AND name='video'`, `ORDER BY b.id`, strict
`SafeObjectKey` grammar (invalid key → nil → `source_unavailable`), never
persisted/logged. Separate from Pass-1 `VideoSource` (stays metadata-only) and
from the photo `MediaLocatorSource`.

**`Date9ja::Import::VideoTransfer` (Phase A only)** — per source video: resolve
owner `Profile` via `ReferenceMap`; single-service (`cloudflare`) global blocker;
multi-video-per-owner re-guarded (`quarantined` / `multiple_videos_per_owner`);
`MediaTransfer.call(media_kind: MediaKind::Video, media_gate: <brand duration
limit>)`. **No Phase B/C.** `Date9ja::Import::VideoTransferReconciliation` —
deterministic, PII-free, invariant `videos_considered == Σ dispositions`;
dispositions `destination_adopted` / `already_destination_adopted` /
`owner_not_imported` / `source_unavailable` / `source_changed` /
`validation_failed` / `quarantined` / `destination_failed` / `binding_conflict` /
`explicitly_skipped`; `to_h` reports `lifecycle` = `SOURCE_ACCEPTED /
DESTINATION_ADOPTED (pass 2A; NOT transferred)` and never emits `transferred`.

**Idempotency:** second identical run → `already_destination_adopted`,
same deterministic key, same blob, zero new uploads, zero `ProfileVideo`, zero
`profile_video` `ReferenceMap` binding, zero jobs (proven by tests).

**Files:** `domains/migration/media_transfer/media_kind.rb` (new),
`domains/migration/media_transfer.rb` + `.../adopt_or_upload.rb` +
`.../canonical_key.rb` (generalized), `domains/media/video_processor.rb`
(`.probe`), `domains/date9ja/snapshot/video_locator_source.rb` (new),
`domains/date9ja/import/video_transfer.rb` + `video_transfer_reconciliation.rb`
(new). Tests: `test/domains/migration/media_transfer/media_kind_test.rb`,
`test/domains/media/video_processor_probe_test.rb`,
`test/domains/date9ja/snapshot/video_locator_source_test.rb`,
`test/domains/date9ja/import/video_transfer_test.rb`, plus video + Image
regression cases added to `media_transfer_test.rb` / `canonical_key_test.rb`.

**Quality gates (2026-09-04):** focused new tests + `test/domains/{migration,media,date9ja}`
= 347 runs / 1137 assertions / 0 failures; RuboCop clean on touched Ruby;
`bin/rails zeitwerk:check` "All is good!"; Brakeman 0 warnings;
`git diff --check` clean.

**Rehearsal:** L1 automated only, against real ffmpeg/ffprobe-generated video
bytes (deterministic test fixtures, not source-census evidence). The full
35-video source-byte rehearsal requires safe media bodies that the current
sanitized snapshot does not contain — **deferred to Pass 2C synthetic L2**. No
claim of 35/35 source-byte verification is made.

**Lifecycle:** IMPLEMENTED / SELF_VERIFIED. NOT `VERIFIED` (needs independent
Codex review). Profile Video capability remains **PARTIAL**; `PARITY_ACCEPTED`:
**NO**. PD-2 (grandfather / trim / quarantine-remove) remains OPEN /
evidence-gated for the founder.

### Profile-video pass 2B — IMPLEMENTED / SELF_VERIFIED (2026-09-04)

Completes the DOMAIN side of a successfully adopted Pass-2A video (ADR 0029).
One orchestrator, two stages: `Date9ja::Import::VideoTransfer.call(stage: :domain)`
runs Pass 2A then, for each successful adoption:

1. **RESOLVE** — authoritative existing-chain check for idempotent resume
   (`ReferenceMap(profile_video/<id>)` → destination `ProfileVideo` → exact
   owner/brand/moderation → attached original key or (raw-purged) valid
   derivatives → `already_ready` / `resume_processing` / `binding_conflict`).
2. **PHASE A** — the Pass-2A verify + adopt pipeline (unchanged).
3. **PHASE B** — short `LockGuard`-held `ProfileVideo.transaction`: re-lock
   `MediaAttachmentRef`, re-resolve owner (must equal RESOLVE's profile — else
   `mapping_drift`), re-prove `blob.key == deterministic original key`, one-live-
   video invariant (`one_video_invariant`), moderation map → new
   `Profiles::VideoUpload.build_video!` (extracted internal domain seam, mirrors
   `PhotoUpload.build_photo!`) → `Migration::ReferenceMap.bind!`
   (`source_entity: "profile_video"`). **No remote I/O under the lock.**
4. **PHASE C** — after commit: `Media::ProcessProfileVideoJob` (inline
   `perform_now` for migration) → `Media::PlaybackDerivative.valid?` bounded
   remote validation of the EXACT deterministic playback + poster pair (via
   `Migration::MediaTransfer.valid_accepted_playback?`, `LockGuard`-asserted
   free) → `ready` + existing raw-original purge behaviour. Job success alone is
   **not** sufficient — a `processing_ready` video whose derivatives do not
   validate is `derivative_validation_failed`, never `ready`.

**Shared runtime hardening (ADR 0029 Pass 2B, benefits native uploads too):**

- **Schema:** `20260904120000_add_processing_claim_to_profile_videos` —
  `processing_started_at :datetime`, `processing_claim_token :uuid`,
  `metadata :jsonb default {}` + `[processing_state, processing_started_at]`
  index. Mirrors `AddProcessingClaimToProfilePhotos`. `processing_state` enum
  unchanged. This was already scoped into Pass 2B by ADR 0029.
- **`ProfileVideo`** gains `STALE_PROCESSING_AFTER`, `processing_terminal_failure?`,
  `processing_retryable?`, `processing_claim_stale?`, `processing_sweepable`
  scope — identical shape to `ProfilePhoto`.
- **`Media::ProcessProfileVideoJob`** rewritten for claim-token concurrency
  (CLAIM txn takes a per-run token; ffmpeg/ffprobe/storage + full remote
  validation of an existing ready run OUTSIDE any txn; FINALIZE txn mutates
  only while `owns_claim?`; stale `processing` reclaimed; ABA-safe — a stale
  worker cannot finalize/purge/mutate; `reconcile_ready` repairs or fails a
  ready video whose derivatives don't validate). Existing container + duration
  gates and the fresh-output "trust own transcode" path unchanged, so the 9
  existing job tests still pass (one timeout test split into
  retryable/terminal — matches `ProcessProfilePhotoJob`).
- **`Media::ProfileVideoProcessingSweeper`** — re-enqueues pending / retryable-
  failed / stale-`processing`; never ready / terminal / recent. Mirrors
  `ProfilePhotoProcessingSweeper`.
- **`Media::PlaybackDerivative`** — THE authoritative "valid completed
  playback + poster pair" contract (video analogue of `Media::DisplayDerivative`):
  exact attachment + key + service + content type + positive byte size + object
  exists + bounded remote re-read + checksum match + real container/decode
  validation. Metadata alone is never sufficient (the raw is purged).

**Interruption windows (ADR 0029 §15):** A (blob, no PV) → Phase A reuse +
Phase B build. **B, C structurally impossible** — `build_video!` +
`ReferenceMap.bind!` are one Phase-B transaction (savepoint-nested profile
lock rolls back with it). D/E (bound, processing incomplete/claim crashed) →
`resume_processing` → job CLAIM reclaims stale, re-derives. F/G (one derivative)
→ `PlaybackDerivative` fails → job repairs from still-present raw, or terminal.
H (both derivatives, not ready) → job reclaims, `derivative_blob` reuses by key,
finalize → ready. I (ready, raw not purged) → RESOLVE `complete` →
`already_ready` (+ purge re-scheduled). J (raw purged, restart) → RESOLVE via
`metadata` keys → `already_ready`; **Phase A is skipped**, the raw is never
recreated.

**Reconciliation:** `VideoTransferReconciliation.new(stage: :domain)` — invariant
`videos_considered == Σ dispositions`; terminals add `ready` / `already_ready` /
`processing_failed` / `derivative_validation_failed` to the Pass-2A vocabulary
(2A `destination_adopted` becomes a non-terminal step). `to_h` reports
`stage: "domain"`, `lifecycle: PROFILE_VIDEO_DOMAIN_MIGRATED (pass 2B) — …`, and
never emits `transferred`. Measures: `profile_videos_created/reused`,
`reference_map_bindings_created/reused`, `processing_attempts/succeeded/failures`,
`playback_validated`, `poster_validated`, `ready`, `already_ready`,
`originals_purged`, `processing_stale_reclaims`, `unexplained_failures`.

**`Migration::MediaObjectRef` semantics unchanged** — Pass 2B does not touch
`transfer_state` (Pass 2A already left it at its default). The existing model
expresses "domain-migrated" via the `ReferenceMap` binding + `ProfileVideo`
lifecycle state, exactly as Profile Photo Pass 2 does. No weakening of any model
to make the report say a completion word.

**Files:** `db/migrate/20260904120000_add_processing_claim_to_profile_videos.rb`
(new), `app/models/profile_video.rb`, `domains/media/process_profile_video_job.rb`
(rewritten), `domains/media/{playback_derivative,profile_video_processing_sweeper}.rb`
(new), `domains/media/video_processor.rb` (unchanged since 2A),
`domains/migration/media_transfer.rb` (`valid_accepted_playback?`),
`domains/profiles/video_upload.rb` (`build_video!` extraction),
`domains/date9ja/import/{video_transfer,video_transfer_reconciliation}.rb`
(stage: :domain), `lib/tasks/date9ja_import.rake` (`date9ja:transfer_videos`).
Tests: `test/domains/date9ja/import/video_domain_transfer_test.rb`,
`test/domains/media/{playback_derivative_test,process_profile_video_job_claim_test}.rb`,
`test/domains/media/process_profile_video_job_test.rb` (updated).

**Quality gates (2026-09-04):** focused new tests + relevant
`test/domains/{migration,media,date9ja,profiles}` + `test/jobs/media` +
profile-video model/serializer/controller = 478 runs / 1606 assertions / 0
failures; Profile Photo regression (`photo_transfer`, `media_transfer`, photo job
+ claim, `ProfilePhoto` model) 82 / 0; RuboCop clean on 24 touched Ruby files
(`db/schema.rb` machine-generated, not linted); `bin/rails zeitwerk:check` "All
is good!"; Brakeman 0 warnings; `git diff --check` clean.

**Rehearsal:** L1 automated only (real ffmpeg/ffprobe-generated fixtures). Full
35-video synthetic-corpus L2 rehearsal is **Pass 2C** — not done. No 35/35 claim.

**Lifecycle:** IMPLEMENTED / SELF_VERIFIED. NOT `VERIFIED`. Profile Video
capability remains **PARTIAL**; `PARITY_ACCEPTED`: **NO** (Pass 2C + later
migration gates remain). PD-2 remains OPEN / evidence-gated.

### Profile-video pass 2C — IMPLEMENTED / SELF_VERIFIED (2026-09-04)

Deterministic synthetic L2 video corpus + independent verifier + the FULL
isolated Pass 1 → 2A → 2B rehearsal + interruption/idempotency/adversarial
evidence. **Full write-up: [`VIDEO-L2.md`](VIDEO-L2.md).**

**Evidence rule (kept separate everywhere):** the sanitized snapshot has
metadata for 35 legacy `ProfileVideo` records but NOT their bodies. The synthetic
corpus mirrors that metadata topology (35 objects, 26 `video/mp4` + 9
`video/quicktime`, all ≤ 60 s) to exercise the machinery. It proves **nothing**
about the real videos' duration/codec/container — those stay **UNKNOWN**.

- **`Date9ja::Snapshot::SyntheticVideoMedia`** + `::Generator` + `::Verifier` —
  the video analogue of the Codex-verified `SyntheticMedia` photo tooling.
  Bodies are real ffmpeg-rendered H.264 MP4 / QuickTime, parameters a pure
  function of `SHA256(generator_version|seed|source_blob_id|content_type)`,
  encoded `-fflags +bitexact -x264-params bitexact=1 -map_metadata -1`. Only
  `byte_size`/`checksum` on the 35 authorized `video` blob rows are rewritten.
- **Determinism:** two clean generations are byte-identical with an identical
  manifest fingerprint (fixed-seed documentable fingerprint
  `5fbcc9dac1d7334859c5753b3c5b347589898af0ce3302e15cc117366433c378`,
  regression-locked). Cross-environment byte-identity is pinned to the
  ffmpeg/libx264 build — the verifier re-renders in the target environment and
  compares (checks 13/15) rather than trusting a stored value.
- **Verifier (28 checks):** re-render byte-exactness, container walk
  (`Media::VideoContainerValidator`), ffprobe (`Media::VideoProcessor.probe`)
  success + positive duration + ±0.75 s tolerance + ≤ 60 s happy-path gate,
  `MediaKind::Video` type detection, no source identity / graph / ownership /
  moderation drift, manifest↔`media_v3` field-for-field bijection, schema-driven
  full-`active_storage_blobs` drift proof (NULL-safe, 0 inserted/deleted),
  **full `active_storage_attachments` table byte-identical to the parent (check
  27)**, **unrelated table row counts unchanged (check 28)**, **manifest
  `source_key` path-containment before any file read (check 24 — review Finding
  3)**, no production endpoint/credential leakage. Generator and verifier do not
  share a self-validating path.
- **Full rehearsal (`test/domains/date9ja/import/video_l2_rehearsal_test.rb`,
  569 assertions, ~53 s):** 35-record topology → Pass 1 (35 preflighted, 0 D8N
  media) → Pass 2A `stage: :adopt` (35 `destination_adopted`, 35 duration
  derived+within-limit, 26 mp4 / 9 mov, **0 `ProfileVideo`**, 35 original blobs)
  → Pass 2B `stage: :domain` / window A (35 `ready`, 35 PV + bindings + playback
  + poster validated + originals purged, never `transferred`) → independent
  destination verifier (exactly one PV per source, one binding each, no
  cross-brand, moderation preserved, bounded remote playback+poster validation)
  → rerun (35 `already_ready`, zero growth, raw not recreated).
- **Interruption/recovery:** windows A / B-E / C / F-G exercised; B & C
  (attach/bind) proven structurally impossible (one Phase-B transaction).
  **Process-kill:** a true forked-worker SIGKILL is not safely automatable
  against the transactional test DB — the bounded alternative reproduces the
  exact durable killed-worker state (`processing` + token, no FINALIZE/ensure)
  and proves deterministic stale-reclaim recovery. The **real forked-worker
  SIGKILL was then run in the operator L2** (`VIDEO-L2.md` §12 step 9): worker
  CLAIMed → `kill -9` (shell `wait` rc 137) → durable `processing` + killed
  token, no FINALIZE → aged claim stale → operator restart reclaimed
  (`processing_stale_reclaims 1`), video reached validated READY with the raw
  purged, killed token could not own the claim (ABA).
- **Adversarial suite (separate from the census):** > 60 s →
  `quarantined`/`duration_over_limit` (0 domain artifacts); unreadable duration →
  `quarantined`/`duration_unreadable`; truncated → `malformed_container`; spoofed
  image → `not_a_video`; checksum / byte-size / content-type drift →
  `source_changed`; destination collision + remote orphan → `binding_conflict`
  fail closed (orphan never adopted); tampered playback → `derivative_validation_failed`
  (never `ready`); tampered poster → not `ready`.
- **PD-2:** NOT chosen. Real over-limit count = **UNKNOWN** (no real media
  inspected). The adversarial > 60 s fixture only proves fail-closed policy.
- **Rake:** `date9ja:build_video_media_v3`, `date9ja:verify_video_media_v3`
  (operator, against the `media_v3` restore + parent), `date9ja:transfer_videos`.
- **Operator L2 — RUN 2026-09-04 (committed `47362bb`):** `media_v3`
  `TEMPLATE`-copied from `date9ja_snapshot_sanitized`; throwaway D8N DB. Build 35
  objects / 35 blob rows patched / fingerprint
  `e134ed15b8327617929831569b633cc4b03dc0de3bb0b9b12f0101f1eb29e503` /
  byte-identical across two builds. `verify_video_media_v3` **all checks
  `ok: true`**. `import_identity` 280/8/0 → `preflight_videos` 35 (duration
  missing 35/35) → `transfer_videos_phase_a` 35 adopted / 0 domain → `transfer_videos`
  **35 ready** / 35 PV + bindings / 35+35 derivatives validated / 35 originals
  purged / never `transferred`. Independent verifier: 35 `deliverable?`, 0
  cross-brand, 35/35 playback + 35/35 poster independently re-validated. Rerun 35
  `already_ready`, zero growth. Real forked-worker SIGKILL: recovered to
  validated READY, ABA-safe. Raw blob/file GC is the standard async
  `ActiveStorage::PurgeJob` (drained explicitly: 0 orphans, originals not
  recreated) — not a defect. Full evidence: [`VIDEO-L2.md`](VIDEO-L2.md) §12.
  **Lifecycle: OPERATOR_L2_COMPLETE / READY_FOR_FINAL_INDEPENDENT_REVIEW —
  still PARTIAL, still NOT `PARITY_ACCEPTED`.** Real duration/codec/container
  UNKNOWN; **PD-2 OPEN**.

### Feature-boundary review — Codex BLOCKED — fixes applied (2026-09-04)

Codex reviewed the completed 2A→2B→2C feature: PASSED D8N/shared architecture,
Profile Photo regression, 2A duration gate, 2B domain binding, brand/tenant
isolation, the schema migration, and privacy. **BLOCKED** on three findings, now
fixed (feature not redesigned):

- **Finding 1 (BLOCKER) — derivative reuse could mark invalid media ready.**
  `Media::ProcessProfileVideoJob#finalize!` now: (A) locates the candidate
  playback/poster blob at each deterministic key (or creates it from the fresh
  render — an existing key is **never overwritten**); (B) **independently
  validates the candidate's actual remote bytes OUTSIDE all DB locks** via new
  `Media::PlaybackDerivative.playback_blob_valid?` / `poster_blob_valid?` (exact
  key + service + content type + positive size + remote object exists + remote
  byte-size match + **checksum/body-identity match** + real container walk /
  image decode); (C) short lock + `owns_claim?`; (D) re-proves the **exact
  validated blob rows** are still at those keys via a fingerprint recheck
  (defeats a candidate swap between B and C). A validation-failing candidate is
  **never attached, never marks ready, never purges the raw** — it retries then
  fails closed (`derivative_conflict` / retry-exhausted terminal). `Media::
  DisplayDerivative` and the photo job are untouched (Codex-PASSED). Regression:
  `test/domains/media/process_profile_video_job_derivative_integrity_test.rb`
  (10 tests, each FAILS on the reviewed code — playback/poster tamper,
  checksum/size mismatch, wrong content, wrong service, ABA swap, valid reuse
  with no duplicate blob, fresh-create, non-owning-worker).
- **Finding 4 — `deliverable?` weaker than the ready invariant.**
  `ProfileVideo#safe_derivative_ready?` now requires **both** `playback.attached?`
  **and** `poster.attached?` (mirrors `MessageAttachment#deliverable?`), so
  READY is never stronger than public deliverability. The job (Finding 1) only
  persists READY after both derivatives independently validate; raw purge
  follows that.
- **Finding 2 — L2 DB drift proof too narrow.** Verifier gains **check 27**
  (full `active_storage_attachments` table byte-identical to the parent — every
  column, every row, NULL-safe; 0 inserted/deleted/changed) and **check 28**
  (row counts for a fixed allowlist of unrelated tables — users, profiles,
  brand_memberships, profile_videos, photos, active_storage_*, likes, matches,
  messages, blocks, reports, profile_views, credentials — match the parent).
  The generator's only write is one `UPDATE active_storage_blobs SET byte_size,
  checksum`, so both pass.
- **Finding 3 — verifier path safety.** `Verifier#object_path` now resolves
  every manifest `source_key` through `Date9ja::Storage::SafeObjectKey`
  (`resolve_within` — grammar + `..`/absolute/backslash/`%`/whitespace rejection
  + symlink-escape containment), and **check 24** validates every key BEFORE any
  file is read. `File.binread` is never called on a caller-supplied path.
  Adversarial tests: 6 unsafe-key shapes + a symlinked-ancestor escape.

**Retest (2026-09-04, post-fix):** `test/domains/{date9ja,migration,media,profiles}`
+ `test/jobs/media` + profile-video/photo model + message-attachment +
profiles-completion + video controller = **546 runs / 2516 assertions / 0
failures / 0 errors** (incl. the full 35-record L2 rehearsal + fingerprint
lock). Profile Photo + photo-L2 regression **125 / 0**. RuboCop clean (32 touched
Ruby files); `zeitwerk:check` "All is good!"; Brakeman 0; `git diff --check`
clean. `DOC_FINGERPRINT` unchanged (generator/manifest untouched).

**Lifecycle:** Pass 2A / 2B / 2C all **IMPLEMENTED / SELF_VERIFIED**; independent
CODE review **ACCEPTED** (Codex, with the one doc fix); **OPERATOR_L2_COMPLETE
(2026-09-04)** — see the operator-L2 bullet above and [`VIDEO-L2.md`](VIDEO-L2.md)
§12. NOT `VERIFIED`. Profile Video capability **PARTIAL**; `PARITY_ACCEPTED`
**NO**. Remaining: **final independent review of the operator L2 evidence**.

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
