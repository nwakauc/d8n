# Date9ja Backend Production Closure — Pass 2

## Migration Parity + Cutover Readiness Audit

**Date:** 2026-09-15
**Branch:** `date9ja-parity`
**Base:** GO-NO-GO-CUTOVER-REPORT.md (2026-09-10, commit `9903c8a`) — prior verdict **CUTOVER READY**
**This pass audits:** everything committed/changed since that report, plus an independent re-verification of test-suite health, before accepting the verdict as still current.

---

# Executive Summary

The 2026-09-10 GO-NO-GO report's data-migration engineering (identity, profile/preference, media, historical graph, sensitive-value preservation, verification import) is sound and this pass found **no defect in it**. However, **6 feature commits landed after that report** (RealMe verification/moderation, Trust Score System ADR 0025, progressive RealMe gate, genotype/compatibility contract, Community foundation ADR 0033) and were never covered by a migration-parity audit. This pass closes that gap.

**One real, concrete parity gap was found and fixed**: the Trust Score System (ADR 0025) reads a `TrustEvent`/`TrustAdjustment` ledger that migrated members' historical trust data never reached, because the importer that produces it (`Date9ja::Import::TrustLedgerImport`, itself correctly built and tested) was never wired into the operator-facing rake task chain. Without this fix, every migrated Date9ja member would cut over with a **visibly zero trust score**, silently discarding real Date9ja history. **Fixed**: added `date9ja:import_trust_ledger` rake task and inserted it into the documented cutover run order.

Two stale test expectations were fixed (not a parity gap — a new D8N-only enrichment field, `faith_family_expectations`, added alongside the RealMe work, has no Date9ja source and was correctly implemented but the test's field list was never updated).

No other parity regression was found. RealMe badge logic was independently verified to be safe against the Date9ja-authoritative rule that email/phone verification must never become a false RealMe badge. Genotype and Community-foundation status were independently re-confirmed as **not** parity gaps.

**This pass's evidence gap**: no restored Date9ja source Postgres snapshot was available in this sandbox, so the snapshot-scale reconciliation numbers in this document are still the ones from the 2026-09-10 report. Fixture/unit-level re-execution of the full importer chain on current HEAD is clean (see below), but a full-scale rehearsal against the real snapshot, including the newly added trust-ledger step, has **not** been re-run since RealMe/Trust Score/genotype/Community landed. This is the basis for the "WITH EXPLICIT OPERATOR STEPS" qualifier below.

---

# Previous Migration State

Per `GO-NO-GO-CUTOVER-REPORT.md` (2026-09-10, commit `9903c8a`): 552/584 source users imported (32 soft-deleted tombstoned, 0 failed); 552 profiles (484 active+visible, 61 draft, 7 suspended); 552 `ProfilePreference` / 4,059 `ProfileOptionSelection`; 604 photos / 89 videos byte-transferred and verified; 1,014 likes / 1,302 passes / 120 matches / 120 conversations / 1,588 messages; 5 reports / 3 blocks / 7 moderation-state rows; 803 `VerificationAssertion`; 45,658 extended-history rows; sensitive-value reconciliation 100% preserved (mapped or raw); idempotency proven on full rerun; full suite 2,251 runs / 1 pre-existing failure / 0 errors. Verdict: **CUTOVER READY**, with one scheduled post-cutover item (message-media bytes).

This pass treats those counts as historical and does not restate them as current without new evidence — see Whole-System Rehearsal Results below.

---

# Changes Made (this pass)

| File | Change | Why |
|---|---|---|
| `lib/tasks/date9ja_import.rake` | Added `date9ja:import_trust_ledger` task | `Date9ja::Import::TrustLedgerImport` existed, was tested, and was correct — but no operator entry point called it. Migrated members' trust history would never reach the live Trust Score System (ADR 0025) without this. |
| `docs/migrations/date9ja-to-d8n/PRODUCTION-CUTOVER-RUNBOOK.md` | Inserted `date9ja:import_trust_ledger` into the documented §4.3 run order (after `import_extended_history`) and into the idempotency re-run line | The runbook must be real and repository-backed (Phase 17); it previously omitted a step now required for Trust Score parity. |
| `test/integration/date9ja_profile_contract_test.rb` | Added `faith_family_expectations` to the `ENABLED_PROFILE` expected-field list | The field was added to `Profiles::Date9jaProfileCatalog::ENABLED_PROFILE_FIELDS` in commit `a25954d` (bundled with unrelated RealMe work) but the test's expectation list was never updated. Implementation was correct; test was stale. |

No importer, schema, or migration-domain code was changed. No production data was touched. No snapshot/rehearsal database in this sandbox was written to production.

---

# Source-to-Destination Mapping / Enum-Catalog / Preference / Option-Selection / Media / User-State / Discovery / Matching Reconciliation

These phases (2–9) were exhaustively audited and evidenced in the pre-existing migration documentation set (`PROFILE-VALUE-MAPPING.md`, `CAPABILITY-PARITY.md`, `RECONCILIATION.md`, `MEDIA-TRANSFER.md`, `SENSITIVE-PRESERVATION-REPORT.md`, `COMPLETE-CONTRACT-AUDIT.md`) and re-confirmed as current by the 2026-09-10 GO-NO-GO report. This pass's job was to determine whether anything committed since then invalidated that evidence. It does not:

- **Profile/preference/option-selection/media/discovery/matching code**: zero commits since `9903c8a` touch `domains/date9ja/import/`, `domains/date9ja/snapshot/`, `domains/migration/`, `domains/profiles/date9ja_profile_catalog.rb` (other than the additive, source-less `faith_family_expectations` field), or `Matching::*`. These phases stand as evidenced in the 09-10 report.
- **Genotype / compatibility contract** (ADR touching 2026-09-12): re-confirmed this pass. `Date9ja::Import::SensitiveProfileImport` maps `genotype` through `SensitiveVocabularies::GENOTYPE`, and any unmapped/unclassified value is preserved **raw**, never dropped or defaulted (`preserve_unclassified_genotype!`). Real-corpus genotype import remains explicitly gated on census measure 327 + DPIA sign-off — unchanged, not regressed.
- **Community foundation** (ADR 0033, 2026-09-13): re-confirmed **moot** for migration purposes. The authoritative Date9ja production census (`AUTHORITATIVE-SNAPSHOT-20260908.md`, 52 tables / 592 columns) contains no questions/answers/stories/events/circles tables. Date9ja has no legacy community content to migrate — Community is a new capability being enabled going forward, not an unmigrated data source. `STATUS.md`'s own caveat ("historical import/reconciliation... remain open") describes a non-applicable future concern, not a current parity gap.

---

# RealMe / Verification Reconciliation

Independently re-verified against the new RealMe badge/moderation logic (commits `0b29567`, `a25954d`).

- RealMe badge eligibility (`domains/identity/realme_badge.rb`) reads the **same** `VerificationAssertion` table the Date9ja `VerificationImport` writes (803 rows: `verification_check` / `verification_event` / `selfie_verification`), requiring approved `selfie` + `video`/`liveness` + `government_id` assertions. It does not read a separate or parallel model.
- Date9ja source `check_type` values (`email, phone, selfie, video, government_id`) match D8N's canonical RealMe assertion types exactly — a migrated user gets a badge only if Date9ja itself recorded approved selfie+video+government_id checks for them.
- **No path converts migrated email/phone verification into a RealMe badge.** `IDENTIFIER_VERIFICATION_POINTS` (trust scoring) and `RealmeBadge` treat email/phone as categorically distinct from the badge requirement. Phase 11's prohibition is respected.
- **Verdict: no RealMe parity risk.**

Date9ja verification-state → D8N mapping:

| Date9ja verification state | D8N contact verification | D8N RealMe assertion | Messaging eligibility |
|---|---|---|---|
| Verified email | `IdentityIdentifier#verified_at` (email) | none | Does not alone unlock message send (progressive gate, ADR 0031) |
| Verified phone | `IdentityIdentifier#verified_at` (phone) | none | Unlocks message send |
| `verification_check` / `verification_event` / `selfie_verification` rows | n/a | `VerificationAssertion` (preserved, private, no public serializer path) | Contributes to RealMe badge only if approved selfie+video+government_id all present |

---

# Trust Score / Trust Ledger Reconciliation

**Gap found and fixed this pass.** `Date9ja::Import::TrustLedgerImport` re-projects the `trust_events`/`trust_adjustments` rows already written by `ExtendedHistoryImport` (as generic `Date9jaHistoryRecord` rows) into the ADR-0025 `TrustEvent`/`TrustAdjustment` tables the live Trust Score System reads. The importer itself is correct and has passing tests (`test/domains/date9ja/import/trust_ledger_import_test.rb`, 2 runs / 0 failures), but it was never called from `lib/tasks/date9ja_import.rake` — so a cutover run following the documented rake sequence would leave every migrated member's Trust Score at zero despite real preserved history.

**Fix applied**: `date9ja:import_trust_ledger` rake task added, and inserted into `PRODUCTION-CUTOVER-RUNBOOK.md` §4.3 immediately after `import_extended_history`, including in the idempotency re-run line. Verified this does not regress the existing importer test (`trust_ledger_import_test.rb` still 2/2 green after the task addition).

---

# Idempotency Results

- Fixture-level: full `test/domains/date9ja/` + `test/domains/migration/` suite (496 runs / 2,752 assertions / 0 failures) includes explicit rerun-creates-nothing assertions (`profile_preference_import_test.rb`, `contract_fidelity_test.rb`) and member-edit-preservation assertions.
- Snapshot-scale idempotency (two full passes against the real/pristine source) was proven in the 2026-09-10 report (0 new rows on rerun across every entity) and not invalidated by any commit since — no importer code changed.
- **Not re-proven this pass**: idempotency of the new `import_trust_ledger` task specifically at snapshot scale (only unit-tested). Recommend including it explicitly in the next operator rehearsal's double-run.

---

# Whole-System Rehearsal Results

**No restored Date9ja source Postgres snapshot was available in this sandbox** (`DATE9JA_SNAPSHOT_DATABASE_URL` unset). This pass therefore re-ran the full importer chain (identity → profile/preference → readiness → historical graph → extended history → verification → lifecycle) at **fixture scale** via the existing test suite's synthetic-adapter seam (the same seam prior rehearsals used before scaling up):

```
bin/rails test test/domains/date9ja/ test/domains/migration/
496 runs, 2752 assertions, 0 failures, 0 errors, 0 skips
```

This confirms importer **logic** correctness on current HEAD, including the genotype raw-preservation path and contract-fidelity chaining. It does **not** reproduce the snapshot-scale counts (552 users, 604 photos, etc.) against current code — those numbers are still from 2026-09-10, predating RealMe, Trust Score, the progressive RealMe gate, and the genotype/Community work. None of those commits touch migration code, so there is no specific reason to expect the counts to have changed — but this pass did not generate fresh evidence to confirm that, because the source snapshot database is not present in this environment.

**Operator action required before cutover**: re-run the full documented rake chain (§4.3 of `PRODUCTION-CUTOVER-RUNBOOK.md`, now including `import_trust_ledger`) against the real rehearsal snapshot, and reconcile against the 2026-09-10 baseline counts. Given no migration code changed, a clean rerun reproducing the same counts (plus non-zero `TrustEvent`/`TrustAdjustment` rows) is the expected and required outcome — a genuine drift would indicate an environment or data problem, not a code one.

---

# Post-Migration Product Journey

Not independently re-run this pass (would require the same unavailable snapshot). The 2026-09-10 report's discovery/matching proof (sample published viewers resolving 68–330 reciprocal candidates via the real `Matching::EligibilityScope`) stands, since no matching or discovery code changed since. Recommend re-running the documented HTTP journey (login → profile → preferences → photos → discovery → like → match → conversation → RealMe gate → message → block/report → admin lookup) against the next full rehearsal, specifically checking RealMe/Trust Score surfaces (`GET /api/v1/trust_score`, `GET /api/v1/me` RealMe fields) that did not exist in the 09-10 journey proof.

---

# Test Suite Health (Phase 19)

Full suite run against current HEAD, with two **local-environment** confounds identified and worked around (not code defects, not fixed — see below):

```
2,382 runs, 26,810 assertions, 3 failures, 0 errors, 0 skips
```

**Environment confound found and documented, not modified**: this workstation's `.env` sets `D8N_EMAIL_PROVIDER=resend` (with a live-shaped API key) and a production-shaped `D8N_CORS_ORIGINS` list. Because no `.env.test` exists, both leak into the test environment, causing ~12 tests (email-change/recovery/verification-code delivery, CORS preflight, browser-session origin checks) to fail against the real Resend API / a CORS allowlist missing local dev origins. This is **not a code regression** — confirmed by overriding both env vars for a clean run, which resolved all 12. `.env` was intentionally left untouched (operator's local file, may serve other manual testing). **Recommend**: add a `.env.test` (or equivalent) pinning `D8N_EMAIL_PROVIDER=action_mailer` so local `bin/rails test` runs are deterministic without manual env overrides — a repo/DX fix, not a migration-parity item.

The 3 remaining failures, all confirmed unrelated to Date9ja migration:

1. **`OpenapiContractTest#test_documents_every_API_v1_route_exactly_once`** — `docs/api/openapi.yaml` is missing 7 live routes, all from the RealMe/Trust Score commits (`GET/POST /api/v1/realme_verifications`, `.../uploads`, `GET/PATCH /api/v1/admin/realme_verifications...`, `GET /api/v1/trust_score`, `GET/POST /api/v1/admin/profiles/{id}/trust_adjustments`). Real drift, one-file fix, genuinely unrelated to Date9ja migration — left for a later pass per this task's own allowance.
2. **`Notifications::DeliverProductNotificationJobTest#test_welcome_email_uses_the_DateZA_template_and_a_brand_sender_exactly_once`** — pre-existing, DateZA-only (the welcome email intentionally includes a "Complete your profile" CTA `href`; the test's no-links premise is stale). Confirmed 100% DateZA, not Date9ja.
3. **`Identity::OtpThrottleLockTest#test_serializes_concurrent_verification_requests_for_the_same_brand_and_identifier`** — a generic (non-brand-specific) two-thread concurrency test, reproducible standalone in this environment. Traced and ruled out as a consequence of Pass 1's `VerificationRequester` capability-gate change: the test's randomly-slugged brand is unregistered in `D8n::Platform::BrandRegistry`, so `capability_enabled?` raises `UnsupportedBrand`, which the gate rescues to `true` — the gate never engages. Root cause not further pursued (out of scope: not Date9ja-specific, not touched by any commit in this migration's history).

**Fixed this pass** (previously failing, now passing): the two `faith_family_expectations` test-expectation mismatches (`test/integration/date9ja_profile_contract_test.rb`).

RuboCop / Brakeman / `zeitwerk:check` were not re-run this pass (no production/domain code was changed beyond the additive rake task); Pass 1 already certified those clean.

---

# Remaining Risks

| Risk | Severity | Disposition |
|---|---|---|
| Snapshot-scale rehearsal not re-run since RealMe/Trust Score/genotype/Community landed | Medium | Operator step required before cutover (this pass's evidence gap, not a known defect) |
| `import_trust_ledger` not yet exercised at snapshot scale / in a double-run | Low-Medium | Operator step, same rehearsal as above |
| Message-media/selfie/verification-evidence **bytes** (22 message rows) | Low | Carried over from 2026-09-10 report, scheduled immediately post-cutover, unchanged |
| `docs/api/openapi.yaml` missing 7 RealMe/Trust Score routes | Low | Unrelated to Date9ja migration; documentation-only |
| `OtpThrottleLockTest` concurrency failure | Low | Unrelated to Date9ja migration; not investigated further this pass |
| Local `.env` email/CORS values leaking into test runs | Low (DX) | Documented; recommend `.env.test`; not a migration-parity item |

---

# Files Changed

- `lib/tasks/date9ja_import.rake` — added `import_trust_ledger` task
- `docs/migrations/date9ja-to-d8n/PRODUCTION-CUTOVER-RUNBOOK.md` — added the trust-ledger step to the documented run order
- `test/integration/date9ja_profile_contract_test.rb` — added `faith_family_expectations` to the expected enabled-field list

# Tests Added/Changed

- `test/integration/date9ja_profile_contract_test.rb` — expectation fix (9 runs / 144 assertions / 0 failures)

# Test Results

- Full suite (env-corrected): 2,382 runs / 26,810 assertions / **3 failures / 0 errors** (down from the 16 failures seen before the `.env` confound was identified and worked around)
- `test/domains/date9ja/` + `test/domains/migration/`: 496 runs / 2,752 assertions / 0 failures
- `trust_ledger_import_test.rb`: 2 runs / 0 failures (unaffected by the rake-task addition)

---

# Final Parity Decision

**PARITY_ACCEPTED — CUTOVER READY WITH EXPLICIT OPERATOR STEPS**

The underlying migration engineering (identity, profile/preference, media, historical graph, sensitive values, verification, discovery/matching) remains sound and unregressed since the 2026-09-10 CUTOVER READY verdict — no code in those paths changed. This pass found and closed one real, concrete gap (Trust Score ledger wiring) that would otherwise have silently zeroed out migrated members' trust history, and confirmed the newer RealMe, genotype, and Community work introduces no parity regression.

The qualifier is evidentiary, not a known defect: this sandbox has no restored Date9ja snapshot, so the snapshot-scale reconciliation numbers are unverified against current HEAD (though no migration code changed to suggest they would drift). Required operator steps before actual cutover:

1. Re-run the full `PRODUCTION-CUTOVER-RUNBOOK.md` §4.3 rake sequence (now including `date9ja:import_trust_ledger`) against the real rehearsal/pristine snapshot.
2. Reconcile against the 2026-09-10 baseline counts; confirm `TrustEvent`/`TrustAdjustment` rows are non-zero for members with migrated trust history.
3. Re-run the double-pass idempotency check including the new trust-ledger step.
4. Re-run the post-migration product journey, additionally exercising `GET /api/v1/trust_score` and the RealMe surfaces on `GET /api/v1/me`.

None of these are expected to surface new defects — they close an evidence gap this sandbox could not close directly.

```
Migration parity: ACCEPTED (with operator steps)
Source users reconciled: 552/552 (2026-09-10 evidence; unchanged migration code, not re-verified at scale this pass)
Eligible preferences migrated: 552/552 (2026-09-10 evidence, as above)
Profile option selections reconciled: 4,059/4,059 (2026-09-10 evidence, as above)
Media reconciled: 604/604 photos, 89/89 videos (2026-09-10 evidence, as above)
Unexpected discovery exclusions: 0 (2026-09-10 evidence, as above)
Unexplained source values: 0
Idempotency: PASS (fixture-scale this pass; snapshot-scale from 2026-09-10, not re-verified for the new trust-ledger step)
Migrated-user core journey: NOT VERIFIED this pass (no snapshot DB available; PASS at 2026-09-10 pre-RealMe/Trust Score)
Rollback runbook: READY (unchanged from 2026-09-10, posture still valid — additive/idempotent migration writes)
Cutover readiness: READY WITH OPERATOR STEPS
```
