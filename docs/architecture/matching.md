# D8N Matching Architecture

## Purpose

This document turns ADR 0009 into a reviewable Phase 4 sequence. It is an implementation gate, not permission to begin all matching features at once.

## Reference Findings

The HookUs and Date9ja repositories agree on the shared mechanics but not the ranking philosophy.

| Concern | HookUs reference | Date9ja reference | D8N direction |
|---|---|---|---|
| Actor | Legacy `User` | Legacy `User` | Brand `Profile` |
| Shared eligibility | visibility, status, reciprocal orientation, age, distance, exclusions | same plus bilateral cultural preferences | Shared tenant-safe eligibility pipeline |
| Ranking | intent, vibe, age, distance, verification | faith, culture, relocation, relationship, family and questionnaire inputs | Explicit strategy per brand |
| Location | private coordinates on user | private coordinates on user | Dedicated private profile location |
| Feed generation | SQL filters plus application sorting/daily materialization | SQL filters plus application scoring | Bounded keyset feed; no whole-population Ruby sort |
| Match creation | reverse-like check then canonical pair | same | Atomic command plus database uniqueness |

Date9ja remains a behavioral and migration reference. Its `User`-centric schema is not a D8N architecture source of truth.

## Implementation Sequence

Current status: Slices 1 through 5 and the subsequent Trust block-policy integration are implemented. Date9ja production matching remains blocked on its migration and privacy decisions.

### Slice 1: Profile Addressability And Location

- Add stable, unguessable public IDs to profiles and backfill them safely.
- Add tenant-constrained private profile locations.
- Add an authenticated owner location update/delete endpoint.
- Ensure logs, owner/public serializers, errors, and tests never disclose coordinates unintentionally.
- Add location freshness and bilateral-distance policy tests.

Gate: migration rollback/reapply, tenant FK tests, serializer tests, and parameter-filtering tests pass.

### Slice 2: Eligibility And Discovery

- Add a shared `Matching::EligibilityScope` rooted in `Current.brand.profiles`.
- Require an authenticated active membership and profile before discovery.
- Apply profile lifecycle, visibility, age, reciprocal preference, distance, and interaction exclusions.
- Add strategy selection through an explicit registry.
- Return explicit public profile serialization through an opaque keyset cursor.
- Prove bounded query count and deterministic ordering.

Gate: cross-brand profiles remain invisible even when IDs, option codes, or preferences overlap.

### Slice 3: Decisions And Match Creation

- Add tenant-constrained likes, passes, and canonical matches with soft deletion.
- Put transitions in focused commands called by thin controllers.
- Recheck target eligibility at write time.
- Make repeated likes/passes idempotent.
- Create one match for mutual positive decisions under concurrent requests.
- Return the same not-found response for unavailable and cross-brand targets.

Gate: database constraints, command tests, request tests, and a concurrency test prove no self, cross-brand, or duplicate match state.

### Slice 4: HookUs Strategy

- Rank eligible profiles using declared HookUs capabilities only.
- Start with intent, vibe, age, and distance inputs.
- Define behavior when an input is unavailable and report bounded score confidence.
- Keep temporary availability, verification, paid boosts, and allowances out until their domains own them.

Gate: fixed fixtures produce deterministic ranking and no owner-only profile option enters a public explanation.

Implemented policy:

- Intent, vibe, age, and distance carry weights of 40, 25, 15, and 10 respectively.
- A dimension unavailable on either profile is removed from the possible total; the earned score is rescaled to `0..100`.
- Confidence is the fraction of those four dimensions that were comparable, rounded to two decimal places.
- Distance contributes only when either profile explicitly configured a distance preference and both locations are fresh.
- Public reasons are bounded machine codes: `shared_intent`, `similar_vibe`, and `mutual_age_fit`. No distance-derived reason, option label, coordinate, or owner-only selection is returned.
- Ranking runs over the full eligible PostgreSQL relation and uses score, creation time, and public profile ID as its keyset boundary.

### Slice 5: Date9ja Contract Proof

- Instantiate the same strategy interface with a non-production placeholder.
- Add contract tests showing that a second brand can select another strategy without changing shared eligibility code.
- Do not invent Date9ja mappings or expose sensitive fields to satisfy the contract.

Gate: Date9ja production behavior remains blocked on ADR 0008 migration and privacy decisions.

Implemented contract proof:

- HookUs and Date9ja implement the same ranking, cursor, compatibility-presentation, location-policy, and readiness interface.
- `date9ja` remains absent from the production strategy registry and its discovery endpoint returns `matching_not_configured`.
- The separate Date9ja contract registry is available only for architecture tests and explicitly reports `production_ready? == false`.
- Its neutral score and 24-hour location-freshness value are interface fixtures, not approved Date9ja product behavior.
- Shared eligibility excludes another brand before the Date9ja contract ranks or paginates candidates.

## Required API Surface

The initial contract should remain small:

```txt
GET    /api/v1/discovery
PUT    /api/v1/profile/location
DELETE /api/v1/profile/location
POST   /api/v1/profiles/:public_id/likes
POST   /api/v1/profiles/:public_id/pass
GET    /api/v1/matches
```

Exact response shapes are defined with request tests before controllers are implemented. Clients never supply `brand_id`, user IDs, match participants, or exact ranking internals.

## Success Criteria

Phase 4's first slice is successful when:

- HookUs can request a deterministic, cursor-paginated feed of eligible HookUs profiles.
- A Date9ja profile can never enter that feed or receive a HookUs interaction.
- Hidden, suspended, deleted, underage, self, and incompatible profiles are excluded.
- Precise coordinates never appear in public JSON or application logs.
- Bilateral distance rules behave explicitly when location is absent or stale.
- Like and pass retries are idempotent.
- Two concurrent reciprocal likes create one canonical match.
- Public profile payloads expose age and public option groups without private source fields; approved photos join discovery only after Phase 6 provides secure media delivery.
- Matching strategies can differ without forking controllers, records, or tenant rules.
- Relevant tests, RuboCop, Zeitwerk, and Brakeman pass.

## Explicit Non-Goals

The original five-slice sequence did not implement messaging, reports, blocks, notifications, entitlements, daily picks, boosts, presence, or full Date9ja migration. Match-gated conversation metadata and directional Trust blocks have since integrated through their reviewed boundaries. Reports, notifications, entitlements, daily picks, boosts, presence, message content, and full Date9ja migration remain outside this sequence.
