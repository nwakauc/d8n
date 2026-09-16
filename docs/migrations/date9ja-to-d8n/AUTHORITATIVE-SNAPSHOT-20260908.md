# Date9ja authoritative rehearsal snapshot — 2026-09-08

Status: **SELF_VERIFIED AUTHORITATIVE DEVELOPMENT/REHEARSAL EVIDENCE.** This is
not an independent verification, a cutover snapshot, or permission to publish.

## Evidence boundaries

Keep these four references separate:

1. **Historical evidence:** the 2026-09-02 engineering snapshot and its prior
   rehearsals (288 users, 279 photos).
2. **Authoritative rehearsal data:**
   `backups_db_production_20260908030000.dump`, timestamp 2026-09-08 03:00,
   1,425,219 bytes, SHA-256
   `e1770ef340082bffc9f3a7f5975cbf23c9d6958b45b5c0c8080d352fe3f03f72`.
3. **Current source contract:** frozen Date9ja `v2` HEAD
   `8b2072c85004946db9254e2f5ef5513127afe3d0`.
4. **Future cutover snapshot:** not yet taken.

The raw dump is outside the repository and was restored only into a disposable
local PostgreSQL 17.11 cluster. It was never modified. Sanitization ran against
a database cloned from the raw restore.

## Three-way schema contract

| Reference | Tables | Columns | Canonical v2/v3 digest |
|---|---:|---:|---|
| Old 2026-09-02 migration contract | 51 | 574 | `41a653a8d4c25621071fb76e6e59fbc0` |
| Authoritative 2026-09-08 production snapshot | 52 | 592 | `0b0e2e2b4b6df617558834f859c44750` |
| Frozen Date9ja HEAD | 52 | 597 | `6b8b90cc7bcc1029a36f7b390b333394` |

### Every production-snapshot delta from the old contract

| Source object | Old | Production snapshot | Current HEAD | Semantics | Migration significance | Sanitization | Census |
|---|---|---|---|---|---|---|---|
| `users.discovery_restricted_at` | absent | nullable timestamp | present | Moderator-owned hard discovery restriction | P0 safety state; importer does not yet preserve it | Preserve | Count and lifecycle cross-tab |
| `users.discovery_restriction_reason` | absent | nullable varchar | present | Controlled moderation taxonomy | P1 audit/context state | Preserve allowlist; unknown → explicit `OTHER` quarantine | Allowlisted buckets + OTHER |
| `users.discovery_restriction_note` | absent | nullable text | present | Moderator free text | Never migrate/commit raw text | Redact, preserving null/present shape | Presence only |
| `users.discovery_restricted_by_id` | absent | nullable user FK | present | Admin/moderator ownership | P1 audit ownership; policy required before import | Preserve FK | Referential anomalies only |
| discovery restriction indexes | absent | timestamp, actor, and partial gender/looking-for indexes | present | Supports source discovery/admin queries | No row-migration effect; documents source semantics | n/a | n/a |
| `users.deletion_reason_code` | absent | nullable varchar | present | Controlled churn taxonomy | Deleted users remain excluded; aggregate evidence retained | Preserve allowlist; unknown → explicit `OTHER` quarantine | Allowlisted buckets + OTHER |
| `users.deletion_comment` | absent | nullable text | present | Member-authored deletion feedback | Never migrate/commit raw text | Redact, preserving null/present shape | Presence only |
| deletion-reason partial index | absent | present for deleted users | present | Churn reporting | No importer effect | n/a | n/a |
| `exit_attempts` table | absent | present, 12 columns | present | Member exit/retention workflow | No current D8N canonical destination; retain aggregate evidence | See rows below | Aggregate only |
| `exit_attempts.id` | absent | bigint PK | present | Row identity | Structural/reference integrity | Preserve | Row count |
| `exit_attempts.user_id` | absent | non-null user FK | present | Attempt owner | Relationship integrity | Preserve | Orphan check only |
| `reason_code` | absent | nullable varchar | present | Same bounded deletion taxonomy | Product analytics; no current importer | Preserve allowlist/OTHER | Bucket counts |
| `intervention` | absent | nullable varchar | present | Server-chosen bounded offer key | Product analytics; no current importer | Preserve allowlist/OTHER | Bucket counts |
| `outcome` | absent | non-null varchar | present | pending/stayed/paused/deleted | Lifecycle evidence | Preserve allowlist/OTHER | Bucket counts |
| `retention_action` | absent | non-null varchar | present | Bounded action result | Lifecycle evidence | Preserve allowlist/OTHER | Bucket counts |
| `comment`, `final_comment` | absent | nullable text | present | Member-authored free text | Never migrate/commit raw text | Redact | Presence counts only |
| `context` | absent | non-null JSONB | present | Arbitrary point-in-time product state | Unsafe/duplicative for this rehearsal | Replace with `{}` | Nonempty count before sanitize |
| `resolved_at`, timestamps | absent | timestamps | present | Workflow timing/state | Preserve structural lifecycle evidence | Preserve | Outcome counts |
| exit-attempt indexes + user FK | absent | present | present | Query and RI support | Structural only | Preserve | FK validation |

### HEAD-only changes absent from the production snapshot

These must not be pretended into the rehearsal data contract:

| HEAD object | Production snapshot | Meaning | Migration treatment now |
|---|---|---|---|
| `users.app_launch_notice_at` | absent | Live-member app-launch consent timestamp | No snapshot values; future cutover schema must reclassify |
| `users.app_launch_notice_source` | absent | Consent provenance | No snapshot values |
| `users.identity_confirmation_pending` | absent | Member must confirm admin-corrected gender/looking-for | No snapshot values; next lifecycle/import policy must address future cutover |
| `users.admin_identity_corrected_at` | absent | Last admin identity correction | No snapshot values |
| `users.admin_identity_confirmed_at` | absent | Member confirmation timestamp | No snapshot values |

The authoritative snapshot contains Date9ja migrations through
`20260907180000`; frozen HEAD additionally contains `20260907200000`,
`20260908090000`, and `20260908093000`.

## Current aggregate population

| Measure | Count |
|---|---:|
| Users total | 584 |
| Identity-import eligible (not deleted, not banned) | 552 |
| Excluded | 32 |
| Deleted | 32 |
| Banned | 0 |
| Seed accounts | 50 |
| Admin accounts | 2 |
| Confirmed email | 406 |
| Phone present | 399 |
| Phone verified | 13 |

The exclusion partition is deleted 32, banned 0, both 0. Seed/admin counts are
reported independently; the current identity importer does not exclude them.

## Safety and lifecycle

| State | Count |
|---|---:|
| Member hidden/paused | 12 |
| Moderator discovery restricted | 0 |
| Suspended | 7 |
| Banned | 0 |
| Deleted | 32 |
| Flagged for moderation | 0 |
| Discovery-state referential anomalies | 0 |
| Exit attempts | 17 |

Visibility cross-tab: 534 live/unhidden/unrestricted/unsuspended/unbanned; 31
deleted only; 7 suspended only; 11 hidden only; 1 hidden and deleted. Discovery
restriction is independent of `profile_hidden`, suspension, ban and deletion.
Restoring the moderator restriction clears only the restriction fields.

Identity correction/confirmation fields are **absent from this production
snapshot**, not present with zero values. Frozen HEAD sets the pending flag after
an admin changes gender/looking-for and clears it with a member identity update,
recording correction and confirmation timestamps.

## Dating marketplace and readiness

### Gender and looking-for

All 584 rows use the authoritative integer enum domains (`man=0`, `woman=1`);
no unknown/null codes were observed.

| Eligible pool | Count | % of 552 eligible |
|---|---:|---:|
| man → man | 337 | 61.05% |
| man → woman | 102 | 18.48% |
| woman → man | 109 | 19.75% |
| woman → woman | 4 | 0.72% |

Overall gender: man 471 (80.65%), woman 113 (19.35%). Overall looking-for:
man 473 (80.99%), woman 111 (19.01%). No multi/open source value exists.

### Liquidity-first impact

The hard source safety/orientation cohort is 534. Age, location, distance,
completion and photo quality are measurements below, not Date9ja discovery
failures.

| Measure | Count |
|---|---:|
| Complete valid age pair | 111 |
| Both age bounds null | 472 |
| Partial age pair | 1 |
| Invalid age pair | 0 |
| Safety-eligible members excluded by a complete-age hard gate | 434 |
| Country present | 584 |
| City present | 417 |
| Safety-eligible missing city or country | 160 |
| Coordinate pair present | 0 |
| Preferred distance present | 0 |
| Preferred countries nonempty | 84 |
| Any photo | 377 |
| Non-rejected/approved photo | 348 |
| Safety-eligible without a non-rejected photo | 208 |
| Safety-eligible satisfying all current D8N source-data completion inputs | 49 |
| Safety-eligible excluded by the combined current D8N source-data gates | 485 |

D8N HEAD already configures Date9ja with no required `ProfileLocation` and no
distance filtering. It still requires age bounds for `ProfileParticipant` and
requires substantial profile/option completion before publication. The current
importer cannot preserve all inputs used in the 49-row source-data estimate, so
no publication conclusion may be drawn from that figure.

### Profile aggregates

- DOB: 584 present; all adult at snapshot time; 0 future or implausible >120.
- Names: 539 exactly two tokens; 25 one token; 20 three-plus tokens.
- Bio: 448 present with length 10–1,000; 136 missing; no >1,000 values.
- Ideal-partner text: 374 length 1–600; 2 length 601–5,000; 208 missing.
- Occupation: 92 present.
- Height: 367 present; 349 in plausible 100–250 cm range; 18 outside; range 1–588.
- Body type: 409 present; 64 distinct nonblank values, confirming free-text drift.
- Source onboarding-completed signal: 324; live/onboarded/not-hidden candidate
  cohort 293. This is not D8N publication eligibility.

## Preference/lifestyle aggregates

No unknown bounded enum codes were observed.

| Field | Non-null | Important distribution / gap |
|---|---:|---|
| Relationship intention | 429 | `0:145 1:84 2:184 3:11 4:3 5:2`; 155 null |
| Commitment timeline | 425 | `0:29 1:80 2:13 3:12 4:291`; 159 null |
| Smoking | 109 | 475 null |
| Drinking | 389 | 195 null |
| Fitness | 112 | 472 null |
| Wants children | 424 | `0:302 1:32 2:90`; 160 null |
| Children count | 366 | `0:357 1:7 2:2`; 218 null |
| Marital status | 122 | 462 null |
| Education | 100 | 484 null |
| Family involvement | 418 | `0:103 1:274 2:41`; 166 null |
| Willing to relocate | 419 | true 335, false 84, null 165 |

Array validation found zero null elements. Nonempty rows: languages 101,
interests 103, relationship values 57, dealbreakers 64, preferred countries 84,
relocation preferences 355. Census output contains counts/shape/length only for
uncontrolled strings.

## Preservation gaps

| Source data | Current D8N support | Current import support | Classification | Priority | Policy |
|---|---|---|---|---|---|
| Occupation | Scalar supported | Not read/imported | SUPPORTED BUT NOT MIGRATED | P1 | Import exact safe scalar after length review |
| Height | `height_cm` supported | Not imported | UNKNOWN / REQUIRES DECISION | P1 | Quarantine 18 anomalies; confirm units |
| Body type | Scalar supported | Not imported | SUPPORTED BUT NOT MIGRATED | P1 | Preserve normalized free text; never enum-coerce |
| Relationship intention | Option supported | 3/6 meanings mapped | PARTIALLY/LOSSILY MIGRATED | P1 | Approve explicit six-code mapping |
| Commitment timeline | No canonical destination | None | NO CANONICAL DESTINATION | P1 | Add approved capability or explicitly defer |
| Smoking/drinking/fitness | Scalars supported | None | SUPPORTED BUT NOT MIGRATED | P1 | Exact enum mapping |
| Wants children | Option supported | yes/no only | PARTIALLY/LOSSILY MIGRATED | P1 | Add explicit `open` representation |
| Children count | Option support is coarse | Reduced to has-children | PARTIALLY/LOSSILY MIGRATED | P1 | Preserve exact count separately |
| Marital status | No HEAD capability | None | NO CANONICAL DESTINATION | P1 | Product/privacy decision |
| Education | Option supported | None | SUPPORTED BUT NOT MIGRATED | P1 | Explicit five-code mapping |
| Family involvement | Option supported at D8N HEAD | None | SUPPORTED BUT NOT MIGRATED | P1 | Explicit three-code mapping |
| Languages | Structured scalar supported | None | SUPPORTED BUT NOT MIGRATED | P1 | Normalize/quarantine unknown strings |
| Interests | Curated `interests` group | InterestMapping (explicit, quarantines free text) | MIGRATED (element values pending sanitizer review) | — | Done — controlled subset mapped, unknown quarantined |
| Relationship values | New `relationship_values` capability (2026-09-09) | RelationshipValueMapping (explicit, fail-closed) | MIGRATED (element values pending sanitizer review) | — | Done — reusable owner-only multi-select |
| Dealbreakers | New `dealbreakers` capability (2026-09-09) | DealbreakerMapping (explicit, lossless per element) | MIGRATED (element values pending sanitizer review) | — | Done — every value a distinct option, never collapsed |
| Preferred countries | `profile_preferences.preferred_country_codes` (added 2026-09-09) | Imported via CountryMapping allowlist | MIGRATED (element values pending sanitizer review) | — | Done — closed multi-country ISO store, never a gate |
| Relocation willingness/preferences | Boolean + `profiles.relocation_preferences` array | Boolean + array both imported (2026-09-09) | MIGRATED (array element values pending sanitizer review) | — | Done — boolean tri-state + normalized free-text array |
| Discovery restriction | Platform safety concepts exist | Not imported | SUPPORTED BUT NOT MIGRATED | P0 | Fail closed until explicit state mapping exists |
| Identity correction state | No equivalent workflow proven | Snapshot columns absent | UNKNOWN / REQUIRES DECISION | P0 for cutover | Re-evaluate against final cutover snapshot |
| Verification/trust | Domains exist | Contact verification only in identity importer | PARTIALLY/LOSSILY MIGRATED | P0 | Complete no-downgrade migration/reconciliation |
| Exit/retention history | No migration destination | None | DEFERRED BY POLICY | P2 | Retain aggregate evidence; decide history retention |

## Verification evidence

- Exact v3 schema passed: 52 tables, 592 columns, digest `0b0e2e…`.
- Missing-column, extra-column and type-drift scratch variants all failed.
- Sanitizer completed twice against the same copied database.
- Verifier passed after both sanitizer runs with zero violations.
- Synthetic email leakage in `users.about_me` was rejected.
- Synthetic uncontrolled text in `exit_attempts.final_comment` was rejected.
- Raw dump SHA-256 remained unchanged after restore/sanitize/census work.
- Pristine and sanitized census outputs live only under `/private/tmp`; neither
  raw data nor generated database artifacts are committed.
