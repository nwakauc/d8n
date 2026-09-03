# Date9ja → D8N Status

- Current phase: **Phase 1 — Shared Platform Foundations** (Wave A)
- Current capability: Batches 2 & 3 reviewed; sanitized snapshot milestone VERIFIED; reconciliation census + schema-signature v2 VERIFIED (independent review); import execution model RESOLVED; **bcrypt compatibility proof VERIFIED (2026-09-02, operator ran `scripts/date9ja/bcrypt_proof.rb` against a real `$2a$12$` account → `$2a$ 12 PASS`)**; identity + membership + non-sensitive profile importer — implementation reviewed + **operator rehearsal VERIFIED (2026-09-03)** against `date9ja_snapshot_sanitized` (288 source rows → 280 imported / 8 skipped `source_soft_deleted` / 0 failed; second pass 280 already_imported / 0 created; source reconciliation balanced). **NOT PARITY_ACCEPTED, NOT production-ready, NOT cutover-ready**
- Builder: Claude (senior engineer)
- Reviewer: Independent reviewer — Codex (batches 1–3 reviewed)
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

## Wave A — media preflight foundation + Date9ja profile-photo pass 1 — **SELF_VERIFIED (2026-09-03)**

Codex review of the earlier "blocked at design" proposal returned REQUEST
CHANGES (correct). The corrected architecture is **ADR 0027** (Proposed) and is
implemented here. Independent review still pending — **not `VERIFIED`, not
`PARITY_ACCEPTED`**, no production/cutover claim.

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

### Lifecycle

Media preflight foundation + Date9ja photo pass 1: **IMPLEMENTED → SELF_VERIFIED.**
Awaiting independent Codex review. **NOT `VERIFIED`, NOT `PARITY_ACCEPTED`**, no
production/cutover readiness. Pass 2 (byte transfer + `ProfilePhoto` creation) is
documented in ADR 0027 and **not started**.

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
- **Profile video: legacy importer + migrated-media reconciliation** — needs the sanitized snapshot / data mapping. Public delivery wiring is **done** (slice 6, VERIFIED).

Profile video remains **PARTIAL** — public delivery wiring done; full parity still needs the legacy video importer, migrated-media reconciliation, the sanitized snapshot, and the frontend/API + parity acceptance journeys. Not `PARITY_ACCEPTED`.

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
| 5 shared media / profile-video — owner CRUD + public delivery | done | importer sub-slice blocked transitively on the identity importer (slice 3) |
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
