# Date9ja → D8N Status

- Current phase: **Phase 1 — Shared Platform Foundations** (Wave A)
- Current capability: Batches 2 & 3 reviewed; no capability currently implementing
- Builder: Claude (senior engineer)
- Reviewer: Independent reviewer — Codex (batches 1–3 reviewed)
- Review cadence: bounded batches (~3–5 slices), not per-slice. Significant work remains **SELF_VERIFIED** until independent review.
- Last verified: 2026-09-02
- Cutover: **BLOCKED** until data parity and feature parity both pass.

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
- **Profile video: legacy importer + migrated-media reconciliation** — needs the sanitized snapshot / data mapping. Public delivery wiring is **done** (slice 6, SELF_VERIFIED).

Profile video remains **PARTIAL** — public delivery wiring done; full parity still needs the legacy video importer, migrated-media reconciliation, the sanitized snapshot, and the frontend/API + parity acceptance journeys. Not `PARITY_ACCEPTED`.

### Phase 1 unblocked-work assessment (2026-09-02)

After slice 6 was verified, every remaining Phase 1 implementation path was
re-checked against `MASTER-PLAN.md`, `PARITY-BUILD-PLAN.md`, `DECISIONS.md`, and
`CAPABILITY-PARITY.md`:

| Wave A slice | Status | Gated on |
|---|---|---|
| 1 brand provisioning | done | — |
| 2 legacy reference mechanism | done | — |
| 3 bcrypt / session transition | **blocked** | sanitized snapshot (see `SNAPSHOT-RUNBOOK.md`) |
| 4 complete Date9ja profile capabilities / conditional completion / privacy serialization | **blocked** | sensitive-field product rows (tribe/ethnicity/denomination/genotype/preferred tribes) + which fields are required for completion — all "Awaiting Uchechi" in `DECISIONS.md` |
| 5 shared media / profile-video — owner CRUD + public delivery | done | importer sub-slice blocked on snapshot |
| 6 verification & trust records/status history | **blocked** | `DECISIONS.md` "Mixed" rows: evidence retention + provider + portability; user-visible trust presentation |
| 7 PAY / Entitlements primitives | **blocked** | `DECISIONS.md` "Mixed" row: which founding/premium access is retained |

No Phase 1 implementation slice is currently unblocked. Isolated-fork work on
Date9ja discovery/profile catalog is not safe to start because it depends on
Date9ja ranking/location semantics and sensitive-field decisions that are product
calls, not engineering defaults.

Next action: Uchechi produces the sanitized snapshot per
[`SNAPSHOT-RUNBOOK.md`](SNAPSHOT-RUNBOOK.md) **and/or** resolves the `DECISIONS.md`
rows in §9 of that runbook. Then the next batch is Wave A slice 3 (bcrypt proof) →
photo/video importer (first `Migration::ReferenceMap` consumers) → reconciliation
harness. Verification/Trust/Entitlement implementation stays gated regardless of
the snapshot.

### Snapshot sanitizer artifacts (2026-09-XX)

| Unit | Kind | State |
|---|---|---|
| **Sanitized-snapshot sanitizer** — `scripts/date9ja/sanitize_snapshot.sql` (deterministic, guarded, fail-closed in-place transform), `scripts/date9ja/verify_sanitized_snapshot.sql` (fail-closed verifier), `SANITIZATION-CONTRACT.md` (all 51 tables / 574 columns classified). Schema-fingerprint guard (`a317e7…`), 51-table guard, idempotency guard, `date9ja_snapshot_tmp` refusal, ack-token gate. | migration infrastructure | VERIFIED (independent review 2026-09-XX) — **SAFE TO EXECUTE AFTER SMALL FIXES**, fixes applied in review |

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
fires on tampered data. **Sanitizer NOT executed against any real snapshot. No
production access.**
Awaiting independent Codex review before the operator runs it.

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
