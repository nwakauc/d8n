# Date9ja → D8N — GO / NO-GO Cutover Report

**Date:** 2026-09-10
**Branch:** `date9ja-parity`
**Mode:** Migration closure — fix demonstrated runtime blockers, preserve
non-blocking legacy data losslessly, run a fresh full rehearsal, reconcile,
decide.

**Snapshot:** `backups_db_production_20260908030000.dump`, SHA-256
`e1770ef340082bffc9f3a7f5975cbf23c9d6958b45b5c0c8080d352fe3f03f72` (authoritative
rehearsal snapshot, schema v3 `0b0e2e2b4b6df617558834f859c44750`, 52 tables /
592 columns). Restored to a disposable local PostgreSQL instance, sanitized
(`sanitize_snapshot.sql`) and verified (`verify_sanitized_snapshot.sql` —
**0 violations**). No production access.

---

## Verdict: **GO**, conditional on two cutover-window execution steps

The migration importer suite is **lossless, idempotent, fail-loud, and
reconciles cleanly** on a full fresh rehearsal of the authoritative snapshot.
No demonstrated blocker remains in importer code.

Cutover may proceed once the following runbook steps — which are *execution*,
not missing code — are completed in the window and reconciled:

1. **Media byte transfer** for profile photos and videos
   (`date9ja:transfer_photos`, `date9ja:transfer_videos`). Transfer code is
   implemented and self-verified against synthetic corpora; preflight on the
   real snapshot is clean (0 missing blobs, 0 checksum/size inconsistencies,
   0 unsupported content types). Shipping without it = every migrated profile
   shows broken images ⇒ this step is a **gate**, not backlog.
2. **Pristine sensitive-value reconciliation.** The sanitizer redacts the
   Nigerian identity / cultural / faith / genotype columns, so this rehearsal
   cannot prove their preservation. Destinations and the gated importer
   (`date9ja:import_sensitive_profile`) exist and are exercised; a pristine
   census run plus `SANITIZATION-CONTRACT` R1 / genotype-at-rest sign-off must
   confirm zero loss before the window.

Everything else is post-migration backlog (§4).

---

## 1. Demonstrated blockers found and fixed this session

Each item below was reproduced on the fresh rehearsal, would have caused a
user-facing regression / unrecoverable loss / integrity-signal corruption at
cutover, and is now fixed with tests.

| # | Blocker (evidence) | Impact class | Fix |
|---|---|---|---|
| 1 | **Media messages silently dropped.** 22 image/video messages (incl. 4 that carry reactions) hit `invalid_message_body` because the source `messages` table stores media as an Active Storage attachment, not an inline reference. Rehearsal before fix: `messages.imported 1569`, 19 dropped, 4 reactions orphaned. | User-facing regression (conversation history gaps) + unrecoverable loss (reactions) | Snapshot source now joins the message's blob and emits a PII-free reference (`date9ja-blob:<id>` + checksum/size/content-type). Message imports with its real `kind`; `source_metadata.media_bytes_transferred=false` marks the pending byte pass. After: **1588/1590 messages, 22/22 media, 22/22 reactions.** |
| 2 | **Resolved reports dropped or mis-filed.** Source `Report.category` (`fake_profile=0, scam=1, harassment=2, inappropriate=3, other=4`) was decoded to string labels that are not D8N `Report.reason` values ⇒ 3 of 5 reports dropped (`unsupported_report_reason`). The 2 that imported landed as `open`, i.e. phantom moderation queue for already-resolved tickets. | User-facing / safety regression + data loss | Exact decode to D8N reasons (`inappropriate→inappropriate_content`, etc.; `scam→other` with the original integer preserved in `evidence.source_category`). `resolved_at` ⇒ status `dismissed` with `evidence.source_resolution="resolved_outcome_unknown"` and `source_resolved_at`. After: **5/5 reports, 0 open, full provenance.** |
| 3 | **Extended-history schema drift ⇒ 100% silent drops.** The per-entity column config was written against assumed names. On the real v3 schema: `explore_impressions` (owner `user_id`→`viewer_id`), `notifications` (`user_id`→`recipient_id`), `notification_deliveries` (no owner column — child of notification), `daily_introductions`/`tracked_contacts` counterparty, `community_events` owner, `trust_events.event_type`, `exit_attempts.reason_code`, etc. Result: **35,000+ member-visible/operational rows dropped**, each mislabelled `owner_not_migrated` — a false reconciliation signal. | Unrecoverable loss + integrity-signal corruption | Column maps corrected against the live schema. New `ExtendedHistorySource::SchemaDrift` raises loudly when a configured owner/counterparty column is absent, so drift can never again masquerade as `owner_not_migrated`. After: **45,658 rows imported, 0 failed**, skips are genuine non-migrated owners only. |
| 4 | **`trust_xp_delta = 5000` false finding.** The importer's own independent check (blocker-ledger item 6) reported a 5,000-point mismatch. Cause: `trust_event_points_total` summed *all* events; `entitlement_trust_xp_total` summed *migrated* users only. The 5,000 = the 32 soft-deleted members' events. | Would block / mislead sign-off | Points sum is now scoped to the migrated cohort (owner resolvable). After: **delta = 0.** |
| 5 | **`NoMethodError: User#public_id` in lifecycle import.** Moderation-state rows for a retained restricted member call `.public_id` on a `User` (which has none). Any suspended/discovery-restricted retained member crashes the importer. | Runtime crash | Resolve the restricting actor's brand `Profile` and use its `public_id`. |

RuboCop clean on all changed files; Brakeman 0 warnings; full suite
**2251 runs / 1 failure** (pre-existing, unrelated — see §4).

---

## 2. Fresh full rehearsal — reconciliation

Disposable D8N DB, schema loaded, brand installed, importers run in dependency
order, then re-run for idempotency.

### Identity / profile / preference

| Stage | Result |
|---|---|
| `import_identity` | 584 considered → **552 imported / 32 skipped (`source_soft_deleted`) / 0 failed**. 552 users, 926 identifiers, 552 credentials + hashes, 552 memberships, 552 profiles, 3,134 legacy refs. 0 collisions / missing identifiers / malformed / binding conflicts. |
| `import_profile_preferences` | 552 imported / 0 failed; 552 preferences, 2,485 option selections. `balanced: true`. |
| `import_sensitive_profile` | 552 processed / 0 failed. 14 `interest_in_nigerian_culture` mapped; every other sensitive field `absent` — **sanitizer-redacted, reconciliation deferred to a pristine run** (§0 gate 2). `balanced: true`. |
| `import_profile_readiness` (`publish_visible_onboarded`) | **ready 484 / intentionally_hidden 68 (50 seed + 11 legacy hidden + 7 suspended) / remediation_required 0 / failed 0**. `publications_applied: 484`, `publications_withdrawn: 0`. Matches the source discovery-eligible index exactly (534) minus 50 seed accounts. |

### Media preflight (bytes not touched)

| | Photos | Videos |
|---|---|---|
| Considered | 631 | 90 |
| Preflighted | **604** | **89** |
| `owner_not_imported` (deleted/seed owner) | 27 | 1 |
| missing blobs / checksum-size inconsistencies / unsupported types | **0 / 0 / 0** | **0 / 0 / 0** |
| media object + attachment refs created | 631 / 631 | 90 / 90 |
| `balanced` | true | true |

### Social graph & history

| Entity | Considered | Imported | Skipped (reason) |
|---|---|---|---|
| likes | 1,067 | 1,014 | 53 (30 seed-linked, 23 participant not migrated) |
| passes | 1,449 | 1,302 | 147 (participant not migrated — seed/deleted) |
| matches | 122 | 120 | 2 (participant not migrated) |
| conversations | 122 | 120 | 2 |
| messages | 1,590 | **1,588** | 2 (participant not migrated) |
| blocks | 4 | 3 | 1 |
| reports | 5 | **5** | 0 |
| verification assertions | 814 | **803** | 11 (owner not migrated) |
| message reactions | 22 | **22** | 0 |
| extended history (19 entities) | 48,069 | **45,658** | 2,411 (non-migrated owners) / 0 failed |
| lifecycle: identity tombstones | 32 | 32 | 0 — **no `User` resurrected** |
| lifecycle: moderation state | 7 | 7 | 0 |
| trust-XP independent check | — | — | **`trust_xp_delta = 0`** |

### Idempotency (every importer re-run)

All re-runs: **0 new rows, 0 failures**, every disposition `already_imported`.
No duplicate users / preferences / matches / conversations / messages / reports /
assertions / reactions / ledger rows / reference bindings.

### End-to-end proof on the rehearsed DB

- 484 profiles `active + visible`; a published viewer resolves **81 reciprocal
  candidates** through `Matching::EligibilityScope` (liquidity-first policy).
- Sample conversation: 3 messages, 2 distinct senders, chronological order intact.
- 22/22 media messages carry a reference and `media_bytes_transferred=false`.
- Reports: 5 total, **0 open**, 5 `dismissed` with Date9ja provenance.
- **Cross-brand profile leak for migrated users: 0.**
- 472 founding members preserved to private `users.metadata`; **0 runtime
  premium/entitlement grants**.
- 32 identity tombstones; **0 resurrected users**.

---

## 3. Security / integrity checks

| Check | Result |
|---|---|
| Sanitizer verifier (auth secrets, IP, push tokens, provider refs, idempotency keys) | 0 violations |
| Cross-brand exposure (DateZA / HookUs) | Full suite green except the one pre-existing unrelated failure; `date9ja`-scoped interaction gate does not touch other brands |
| Verification evidence exposure | `VerificationAssertion` is brand-scoped and private; no public serializer path |
| Sensitive-key leakage into history ledger | `PayloadSanitizer` strips auth/token/credential/email/phone keys; free-text body columns are not selected by the snapshot source |
| Soft-deleted members | Preserved as tombstone ledger rows only; no `User`, membership, or profile created |
| Entitlements | `founding_member` / subscription status / trust XP written to private metadata only — never a runtime access grant or revocation |
| Brakeman | 0 errors, 0 security warnings |

---

## 4. Post-migration backlog (explicitly NOT cutover blockers)

| Item | Why it is not a blocker |
|---|---|
| Message / selfie / verification-evidence **bytes** | Representation + references exist; deferred byte pass (ledger item 10). Messages carry `media_bytes_transferred=false`. History is complete; only pixels wait. |
| `explore_impressions` last-shown cache (19,970 rows imported) | Pure de-dup optimization cache. If it were absent, members would briefly re-see a few Explore candidates; self-heals. Imported anyway for completeness. |
| Historical `notifications` / `notification_deliveries` (13,699 rows imported) | Ephemeral; the runbook says not to replay them. Preserved as an inert ledger; nothing consumes them at runtime. |
| Extended-history import throughput | ~8 min for 48k rows at 552-user scale (per-row savepoint). At production scale, switch to bulk `insert_all` in the window — an ops task, not correctness. |
| `countries_unresolved: 22`, `age_ranges_unresolved: 446`, `relationship_intent` / `has_children` / `wants_children` unresolved | Legacy-optional under the liquidity-first policy; none is a publication gate. `country` count is partly a sanitized-snapshot artifact (rare countries collapsed to `OTHER`); the ISO-name backfill covers correctly-spelled values on pristine data. |
| `passes.participant_not_migrated: 147`, `likes: 23` | All involve seed or soft-deleted accounts that are intentionally not migrated. |
| Sensitive Nigerian identity / genotype value reconciliation | Gate 2 above — a pristine census run + DPIA/at-rest sign-off, not an engineering gap. |
| `Like.kind` `super_like` → `hook` alias not exact | Pre-existing (audit §4.1); semantics preserved, no data lost. |
| DateZA welcome-email `href` test failure | Pre-existing on `dev`; DateZA email template vs a stale test assertion. Unrelated to Date9ja. |
| Independent review | This report is builder self-verification. Independent review of the closure changeset is recommended but not a data-integrity gate. |

---

## 5. Rollback posture

Unchanged from `CUTOVER-RUNBOOK.md`: the legacy Date9ja database/backend stays
intact and read-only-capable throughout the stability period; all migration
writes are additive and reversible; the reference map makes the delta re-runnable.
Rollback triggers: account lockout, cross-brand exposure, any retained feature
unavailable, broken conversation access, message/reaction/view loss or order
corruption, duplicate identity/relationship creation, inaccessible media,
auth/security failure, unreconciled critical loss.

---

## Appendix — commands (reproducible)

```bash
# snapshot
createdb date9ja_rehearsal_pristine_20260910
pg_restore --no-owner --no-privileges -d date9ja_rehearsal_pristine_20260910 \
  backups_db_production_20260908030000.dump
psql -d date9ja_rehearsal_pristine_20260910 -f scripts/date9ja/schema_signature.sql   # v3 OK
createdb date9ja_migration_sanitized_20260910 -T date9ja_rehearsal_pristine_20260910
psql -v ON_ERROR_STOP=1 -v sanitize_ack=SANITIZE_THE_COPY \
  -d date9ja_migration_sanitized_20260910 -f scripts/date9ja/sanitize_snapshot.sql
psql -v ON_ERROR_STOP=1 -d date9ja_migration_sanitized_20260910 \
  -f scripts/date9ja/verify_sanitized_snapshot.sql                                    # 0 violations

# rehearsal
export RAILS_ENV=test
export DATABASE_URL=postgresql://localhost/d8n_date9ja_rehearsal_20260910
export DATE9JA_SNAPSHOT_DATABASE_URL=postgresql://localhost/date9ja_migration_sanitized_20260910
bin/rails db:schema:load
bin/rails runner 'Brands::Date9jaInstaller.call(hosts: ["date9ja.test"])'
bin/rails date9ja:import_identity
bin/rails date9ja:import_profile_preferences
bin/rails date9ja:import_sensitive_profile
bin/rails date9ja:preflight_photos
bin/rails date9ja:preflight_videos
DATE9JA_PUBLICATION_POLICY=publish_visible_onboarded bin/rails date9ja:import_profile_readiness
bin/rails date9ja:import_historical_graph
bin/rails date9ja:import_verification
bin/rails date9ja:import_extended_history
bin/rails date9ja:import_lifecycle
# re-run all of the above → 0 new rows, 0 failures

# cleanup
dropdb d8n_date9ja_rehearsal_20260910
dropdb date9ja_migration_sanitized_20260910
dropdb date9ja_rehearsal_pristine_20260910
```
