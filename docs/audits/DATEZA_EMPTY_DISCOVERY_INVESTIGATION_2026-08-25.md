# DateZA Empty Discovery Investigation

**Date:** 2026-08-25  
**Scope:** Read-only investigation of the affected DateZA staging viewer  
**Affected profile:** Profile `3196`, user `3235`, membership `3230`  
**Conclusion:** The zero result is caused by a persisted empty daily Discovery allocation, not by the current eligibility population, serialization, the frontend calling Find, or the 24-hour location-freshness rule alone.

## Executive conclusion

The affected viewer's 2026-08-25 DateZA Discovery allocation was created and finalized with zero candidates at `2026-08-24T23:55:35Z` (`2026-08-25 01:55:35` in Johannesburg).

At that time the viewer had no dating-location row. Because the viewer had a `500 km` distance preference, `Matching::EligibilityScope#without_viewer_location` returned `scope.none`. The daily allocator persisted a finalized allocation containing zero candidate rows.

The viewer's location was added later: the location row was created at `2026-08-25T03:03:49Z` and records `captured_at = 2026-08-25T02:35:01Z`. The location therefore did not exist until more than three hours after the daily allocation had been finalized.

With the viewer's current staging state, the repository's exact eligibility predicates produce **14 eligible candidates after interaction exclusions**, and DateZA's current ranking would select **10**. Nevertheless, `Matching::Discovery` returns zero because `Matching::StableDailySelection` finds the existing allocation and never regenerates or refills it.

This is not merely the previously identified 24-hour freshness issue:

- The viewer had **no location record at all** when the empty batch was created.
- Current staging already runs DateZA's persistent-location policy (`location_max_age = nil`).
- Current eligibility produces 14 candidates.
- The persisted allocation still has zero candidate rows.

## 1. Exact Discover endpoint used by the DateZA frontend

The DateZA application route `/discover` renders `DiscoveryPage`. On mount, that page calls `getDiscoveryProfiles()`, which sends:

```http
GET /api/v1/discovery
Accept: application/json
Cookie: d8n_session=... and/or Authorization: Bearer ...
```

No query string is supplied. In particular, the frontend supplies none of:

- `mode`
- `limit`
- `cursor`
- `vibe`
- `online`
- Find filters

The request uses the configured `VITE_D8N_API_URL`; in local Vite development it is sent through the same-origin `/api` proxy, whose upstream host is the configured DateZA API host.

Evidence:

- DateZA `DiscoveryPage`: `/Users/uchechinwaka/pro/dateza/src/features/discovery/DiscoveryPage.tsx`
- DateZA API function: `/Users/uchechinwaka/pro/dateza/src/lib/api/discovery.ts`
- DateZA API transport: `/Users/uchechinwaka/pro/dateza/src/lib/api/client.ts`
- Rails route: `config/routes.rb`

### Discovery versus Find

The Discover UI is not accidentally calling Find. `getDiscoveryProfiles()` calls only `/api/v1/discovery`. Find is a separate screen and endpoint at `GET /api/v1/find`.

## 2. Exact backend call chain

The runtime call chain is:

1. `GET /api/v1/discovery`
2. `Api::V1::DiscoveryController#index`
3. `ApplicationController#set_current_context`
4. `Brands::Resolver.call(request:)`
5. Host lookup through active `BrandDomain` and `Brand`
6. `Identity::SessionAuthenticator.call(brand:, token:)`
7. `Current.brand` and `Current.user` are established
8. DateZA platform contract and Discovery surface authorization
9. `Matching::StrategyRegistry.surface_for(brand:, mode: nil)`
10. DateZA's default `discovery.curated_daily` daily-batch surface
11. `Matching::Discovery.call(...)`
12. `Matching::StableDailySelection.call(...)`
13. Active DateZA membership lookup and row lock
14. `Matching::ProfileParticipant.discoverable!`
15. Existing daily allocation lookup
16. If absent: `Matching::EligibilityScope` → `Matching::ExclusionsScope` → `DatezaV1.rank_daily_selection` → persisted allocation
17. If present: reuse it without regeneration
18. Recheck only the candidates already stored in that allocation
19. `Profiles::StatusFields`, response decorations, and `Matching::CandidateSerializer`
20. JSON response with `profiles`, `next_cursor`, and `selection`

The staging DateZA host mapping is active and correct:

```text
dateza-staging-api.d8n.tech -> brand 2, slug dateza
```

Authentication is brand-scoped. The affected user has an active DateZA session, membership, user, and profile. There is no evidence of wrong-brand or wrong-viewer resolution.

Key implementation files:

- `app/controllers/application_controller.rb`
- `domains/brands/resolver.rb`
- `domains/identity/session_authenticator.rb`
- `app/controllers/api/v1/discovery_controller.rb`
- `domains/matching/discovery.rb`
- `domains/matching/stable_daily_selection.rb`
- `domains/d8n/platform/brands/dateza.rb`

## 3. Affected viewer state

Only eligibility-relevant, non-contact data is included.

| Field | Staging value |
|---|---:|
| User ID | `3235` |
| Profile ID | `3196` |
| Brand membership ID | `3230` |
| Brand | DateZA, brand `2`, slug `dateza` |
| User status | Active |
| Membership status | Active |
| Profile status | Active/published |
| Profile visibility | Visible |
| Gender | `man` |
| Age | 54 |
| Interested in | `woman` |
| Preferred age range | 18–120 |
| Maximum distance | 500 km |
| Dating location now present | Yes |
| Location captured at | `2026-08-25T02:35:01Z` |
| Location row created at | `2026-08-25T03:03:49Z` |
| Contact identifier verified | Yes |
| RealMe/identity verification | Not implemented as a Discovery predicate |
| Last DateZA session use observed | `2026-08-25T13:58:56Z` |
| Discover query filters | None |
| Persisted Discover facets | None |

Contact verification is presentation state and an interaction gate for DateZA; it is not a shared Discovery eligibility predicate.

## 4. Eligibility funnel

The following counts were calculated on staging for profile `3196` by applying the repository predicates in their actual order.

| Stage | Before | After | Removed | Exact predicate |
|---|---:|---:|---:|---|
| All DateZA profile records | — | 114 | — | `brand.profiles` |
| Kept records | 114 | 114 | 0 | `profiles.deleted_at IS NULL` |
| Active and visible/published | 114 | 80 | 34 | `Profile.kept.active.visible` |
| Exclude viewer | 80 | 79 | 1 | `profiles.id != viewer.id` |
| Required joined records | 79 | 79 | 0 | User, membership, and kept preference exist |
| Active user | 79 | 79 | 0 | `User.kept.active` |
| Active membership | 79 | 79 | 0 | `BrandMembership.kept.active` |
| Birthdate and adult gate | 79 | 79 | 0 | Birthdate present and age at least 18 |
| Block exclusion | 79 | 79 | 0 | No block in either direction |
| Viewer wants candidate gender | 79 | 54 | 25 | Candidate gender is in `['woman']` |
| Reciprocal gender preference | 54 | 51 | 3 | Candidate `interested_in` contains `man` |
| Candidate fits viewer age range | 51 | 51 | 0 | Candidate is 18–120 |
| Viewer fits candidate age range | 51 | 50 | 1 | Candidate min/max age contains viewer age 54 |
| Candidate location join | 50 | 50 | 0 | Left join before distance enforcement |
| Candidate has location and is within viewer's 500 km | 50 | 22 | 28 | Candidate location required; Haversine distance `<= 500` |
| Within candidate's distance limit | 22 | 22 | 0 | Distance also within candidate maximum, when set |
| Exclude prior likes | 22 | 20 | 2 | Outgoing kept Like exists |
| Exclude prior passes | 20 | 14 | 6 | Outgoing kept ProfilePass exists |
| Exclude active matches | 14 | 14 | 0 | No active match in either canonical position |
| Current eligible population | 14 | 14 | 0 | Final shared eligibility/exclusion scope |
| DateZA daily ranking limit | 14 | 10 | 4 | `DatezaV1.rank_daily_selection(limit: 10)` |
| Candidates stored in today's allocation | 10 possible now | 0 | 10 | Existing allocation was finalized earlier and is reused |
| Profiles returned by `Matching::Discovery` | 0 | 0 | 0 | Delivery can only filter stored allocation candidates |

### Historical zero transition

The historical allocation-time pool cannot be reconstructed perfectly from mutable current records, but its zero transition is deterministic from preserved timestamps and code:

1. Allocation `4` was finalized at `2026-08-24T23:55:35Z`.
2. No viewer location existed then; the location row was created at `2026-08-25T03:03:49Z`.
3. The viewer's stored preference required a maximum distance of 500 km.
4. `Matching::EligibilityScope#without_viewer_location` returns `scope.none` whenever the viewer has a distance limit and no usable viewer location.
5. `Matching::StableDailySelection` then persisted a finalized allocation with zero candidate rows.

## 5. Representative candidate outcomes

Names, contact details, precise coordinates, and public UUIDs are intentionally omitted.

| Candidate profile | Outcome now | Evidence |
|---|---|---|
| `3148` | Qualifies; would rank #1 in a fresh allocation | Published DateZA demo profile; reciprocal gender/age; valid location and bilateral distance; no like, pass, match, or block. Current compatibility score 82. |
| `3147` | Qualifies; would rank #7 | Published DateZA demo profile; age 28; reciprocal preferences; about 44.9 km away; candidate maximum 100 km; no interaction exclusion. |
| `3175` | Excluded by prior pass | Otherwise eligible published demo profile, age 26, about 45.4 km away, but the affected viewer passed it. Exact exclusion: `ProfilePass.kept` subquery. |
| `3146` | Excluded by distance | Published demo profile with reciprocal preferences and a location, but approximately 1,274 km away. This exceeds both the viewer's 500 km maximum and the candidate's 100 km maximum. |
| `3179` | Excluded by reciprocal age | Published woman interested in men, age 30, but her preferred maximum age is 40; the viewer is 54. This profile is removed before location evaluation. |

Other material candidate-data observations:

- Three published women were excluded because they were interested only in women.
- Several non-demo published profiles had no dating-location row and were excluded when distance was required.
- Many demo profiles were geographically more than 500 km from this viewer.
- These data-quality and preference facts narrow the pool but do not explain the final zero: 14 candidates still qualify now.

## 6. Daily Discovery batch and quota state

The affected member has these persisted Discover allocations:

| Allocation | Johannesburg date | Finalized UTC | Candidate rows |
|---|---|---|---:|
| `3` | 2026-08-24 | `2026-08-24T16:56:16Z` | 0 |
| `4` | 2026-08-25 | `2026-08-24T23:55:35Z` | 0 |

Today's allocation state is:

- Correct brand: DateZA brand `2`
- Correct membership: `3230`
- Correct viewer profile: `3196`
- Correct surface: `discovery.curated_daily`
- Correct strategy: `dateza_v1`
- Correct policy key: `stable_daily_v1`
- Correct allocation date: 2026-08-25 in `Africa/Johannesburg`
- Daily limit: 10
- Candidate rows: 0
- Finalized: yes
- Deleted: no
- Returned selection count: 0
- Refresh boundary: 2026-08-26 00:00 Johannesburg time

This is **not** “already served 10.” Discover has no per-card consumption counter, and its allocation contains zero candidates.

The viewer does have 10 Find exposures for 2026-08-25. Those are stored in the separate Find ledger and do not consume or alter Discover. The viewer's two likes and six passes were recorded after the empty allocation and reduce the current eligible population from 22 to 14; they did not cause the allocation to be created empty.

The direct comparison is conclusive:

```text
Persisted Discover allocation candidate rows: 0
Current eligible candidates after exclusions: 14
Fresh DateZA ranking result: 10
Matching::Discovery returned profiles: 0
```

## 7. Layer where profiles disappear

The zero result occurs in **daily batch/allocation logic**.

More precisely:

- At original allocation time, shared matching eligibility produced zero because the viewer had no location while using a distance limit.
- The daily allocator persisted that zero as a finalized allocation.
- On later requests, the allocator reuses that allocation even though shared eligibility now produces candidates.

It does not occur in:

- Controller policy/capability authorization
- Brand resolution
- Session/current viewer resolution
- DateZA compatibility ranking under current state
- Candidate serialization
- Pagination
- Frontend response parsing
- The UI calling Find by mistake

`Matching::Discovery` itself returns an empty `profiles` array before controller serialization. The controller merely maps that empty array, and the frontend correctly displays its empty state.

## 8. Staging versus current local working tree

### Current staging backend

At inspection time, staging was running image:

```text
ghcr.io/nwakauc/d8n:2132f08bc93d46de2a38b80e2c05a2101a2e9823
```

This is the same commit as local `HEAD` (`2132f08`). It includes DateZA's persistent-location eligibility policy from commit `f146de7`; DateZA no longer applies a 24-hour freshness cutoff.

Staging nevertheless returns zero for the affected viewer because allocation `4` predates the viewer's location and survives the code/data change.

### Current local backend

Local `HEAD` is the same backend commit as staging. The working tree's existing uncommitted backend changes are confined to the South Africa place catalog and its tests; they do not change Discovery, matching, allocation, or serialization.

Local data is different:

- 52 DateZA profiles, all demo profiles
- Two existing allocations for local viewer profile `73`
- Both allocations contain 10 candidates
- That viewer currently has 21 eligible candidates

Thus local data returns a populated batch, while staging profile `3196` returns its persisted empty batch. The behavioral difference is data history, not a current backend code difference.

### DateZA frontend working tree and deployment caveat

The current DateZA source calls `GET /api/v1/discovery` correctly. Its uncommitted `RequireLocation` guard can ask a member to supply location before rendering Discover, but it cannot repair a daily allocation already finalized empty; after location is stored, the backend still returns the persisted zero-candidate allocation.

The canonical public Vercel URL checked during this investigation was not a reliable deployment of the current product app: `/discover` returned a Vercel-level 404, and the root served an older landing-page bundle last modified on 2026-08-22. The affected Discover result therefore appears to have been reproduced from the current local/preview client against staging rather than from that canonical public deployment. This does not change the staging backend finding.

## 9. Root causes ranked by certainty

### 1. Persisted empty daily allocation is reused after viewer eligibility changes — certain

`StableDailySelection#find_or_create_allocation!` returns an existing allocation based only on brand, membership, surface, and allocation date. It does not regenerate it when the viewer later gains a required location. Delivery only rechecks stored candidate IDs; an empty allocation has no IDs to recheck.

This is the immediate reason the current 14 eligible candidates become zero returned profiles.

### 2. A viewer with no usable location was allowed to finalize a DateZA allocation — certain

`ProfileParticipant.discoverable!` validates lifecycle, age, gender, and preferences but not DateZA's required dating-location collection. The affected active/visible legacy profile could therefore call Discovery. Its 500 km preference then caused the candidate scope to become `none`, which was persisted as an honest but premature empty batch.

### 3. Existing allocations are not invalidated/versioned across eligibility-policy changes — certain

The current allocation lookup ignores stored `strategy_key` and `policy_key`, and there is no eligibility-policy version in the allocation identity. The persistent-location release and later location capture could not affect the already-finalized allocation.

### 4. Candidate incompleteness and prior actions reduce the pool but are not the zero cause — certain

Missing locations, long distances, non-reciprocal preferences, two likes, and six passes reduce the current population to 14. They do not reduce it to zero.

### Explicitly ruled out

- Current 24-hour DateZA location freshness
- Wrong brand or session
- Wrong viewer or membership
- Verification gating
- Discover quota already consumed
- Find consuming Discover capacity
- Controller filtering
- Serializer failure
- Pagination/cursor handling
- Frontend calling Find
- Frontend dropping valid profiles

## 10. Minimal recommended fix

No fix was implemented in this investigation.

The smallest safe fix has two parts:

1. **Do not create/finalize a DateZA daily allocation while the viewer is missing a required dating location.** Add a server-side DateZA/surface-specific viewer prerequisite before allocation creation. Return a stable 403 error and persist no allocation, allowing the first request after location capture to create the real daily batch. Do not rely on the frontend location guard.

2. **Provide narrowly defined recovery for empty allocations created before that prerequisite was satisfied.** Under the existing membership lock, permit regeneration only when all of these are true:
   - the allocation has zero candidate rows;
   - the viewer lacked the required location when it was finalized;
   - the viewer now has that location;
   - no non-empty allocation or candidate consumption is being rewritten.

Do not broadly refill allocations after likes, passes, blocks, unpublishing, or ranking changes; that would violate the accepted stable daily-batch behavior.

For policy/strategy deployments, separately consider versioning allocation identity so an allocation created under an incompatible eligibility policy cannot silently survive. That is useful hardening but is broader than the immediate regression fix.

No staging data should be deleted manually merely to make the screen look populated. A targeted recovery mechanism or explicitly approved operational repair should preserve auditability.

## 11. Tests to add for the proven regression

Add request/domain regression tests covering:

1. A DateZA viewer with a distance limit but no required location receives a stable error and no `DiscoveryAllocation` is created.
2. After that viewer stores a location, the same day's first successful `GET /api/v1/discovery` creates and returns the eligible batch.
3. A legacy zero-row allocation created before location capture is regenerated exactly once after the required location appears, if the targeted recovery rule is approved.
4. A genuinely empty allocation for a fully eligible viewer remains stable and is not repeatedly regenerated.
5. Non-empty allocations are never refilled after likes, passes, blocks, matches, unpublishing, or later higher-ranked candidates.
6. HookUs behavior remains unchanged; its 24-hour live-location policy must not inherit DateZA's prerequisite/recovery behavior accidentally.
7. Allocation behavior across an eligibility-policy version change is explicit if allocation versioning is adopted.
8. The controller contract continues to return the documented DateZA `selection` shape and the chosen stable error code is added to OpenAPI.

Existing tests already prove persistent DateZA locations, bilateral distance rules, stable non-refilling batches, DateZA/Find separation, serialization shape, and the OpenAPI contract. The missing regression is specifically “empty batch finalized before a newly required viewer prerequisite is later supplied.”

## 12. Changes and verification

### Files changed by this investigation

- `docs/audits/DATEZA_EMPTY_DISCOVERY_INVESTIGATION_2026-08-25.md` only

No application code, tests, database records, allocations, sessions, interactions, or staging data were changed. No commit, push, or deployment was performed.

Pre-existing uncommitted changes in both repositories were preserved and not modified.

### Commands/checks

Passed:

```text
Focused Rails tests:
21 runs, 955 assertions, 0 failures, 0 errors, 0 skips

RuboCop:
543 files inspected, no offenses detected

Brakeman:
79 checks, 0 security warnings

git diff --check:
passed
```

The full Rails suite was also attempted:

```text
976 runs, 5765 assertions, 7 failures, 6 errors, 0 skips
```

Those failures were outside Discovery and were caused by the test environment not supplying expected CORS origins and by email-delivery tests observing no delivered mail. All focused Discovery, DateZA location-policy, allocation-model, and OpenAPI tests passed.

## Final answer

The affected DateZA viewer receives zero Discovery profiles because the backend finalized an empty daily allocation before the viewer had a dating location, then continued reusing that persisted allocation after location became available. Current matching eligibility is not empty: it produces 14 candidates and a fresh DateZA allocation would contain 10. The zero therefore occurs in stable daily batch persistence/reuse, before serialization and frontend rendering.
