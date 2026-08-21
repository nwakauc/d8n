# DateZA Find Backend Contract

**Status:** Implemented  
**Endpoint:** `GET /api/v1/find`  
**Brand:** DateZA (`dateza`)

## Product invariant

A free DateZA membership may be surfaced at most 10 unique eligible candidate
profiles during one Africa/Johannesburg calendar day. The accounting identity is:

```txt
(brand, DateZA membership, candidate profile, Johannesburg exposure date)
```

The first returned Find card creates the exposure. Returning that candidate
again, opening profile detail, Like, Pass, reload, retry, cursor replay, or a
second client creates no additional exposure.

## Request

Supported query parameters:

- `limit`: 1–10, default 10.
- `cursor`: opaque cursor returned by the previous response.
- `min_age` and `max_age`: optional additional narrowing within 18–120.
- `max_distance_km`: optional additional narrowing within 1–500 km.
- `relationship_intent`: an active DateZA relationship-intent option code.

Filters can only narrow the shared bilateral eligibility scope. They cannot
broaden the member's stored age, reciprocal gender, or distance eligibility.
Owner-only profile answers are not Find filters.

The signed cursor is bound to the resolved brand, membership, DateZA Find policy
version, and exact filters. Changing any of those produces `invalid_cursor`.

## Response

```json
{
  "profiles": [],
  "next_cursor": null,
  "allowance": {
    "limit": 10,
    "used": 10,
    "remaining": 0,
    "exhausted": true,
    "resets_at": "2026-08-22T00:00:00+02:00"
  }
}
```

Profiles use the approved public serializer plus generic, viewer-relative
activity/distance status and nullable pair-specific `dateza_v1` compatibility.
Compatibility is calculated after the exposure allocation and never adds an
exposure; null means the comparable-data threshold was not met. Exact
coordinates, owner-only option groups, internal
trust/moderation state, raw storage identifiers, HookUs Hook/Hook Tonight state,
and cross-brand data are absent.

An exhausted response is deterministic: it can return still-eligible profiles
already exposed through the requested page/filter, but never a new 11th profile.
If fewer than 10 eligible candidates exist, Find returns only those candidates
and leaves the unused allowance available.

## Eligibility and exclusions

Find composes existing D8N scopes in this order:

1. Fundamental visibility: same brand, not self, active/visible adult profile,
   active identity/membership, and no block in either direction.
2. Bilateral eligibility: reciprocal `interested_in`, reciprocal age ranges, and
   reciprocal distance limits using fresh private locations.
3. Interaction exclusions: prior Like, Pass, active Match, or live Hook pair.
4. Optional Find filters.
5. Deterministic newest-first ordering and member-bound keyset cursor.

## Concurrency and storage

Allocation locks the current `BrandMembership` row and performs candidate
selection, allowance calculation, and exposure insertion in one transaction.
All devices and sessions for that membership therefore serialize on the same
lock. The database unique index on
`(brand_id, brand_membership_id, candidate_profile_id, exposure_date)` provides
the independent final guard against duplicate charging.

Exposure rows are durable accounting records. They are not HTTP rate-limit
counters and are not soft-deleted. The generic Find request throttle is only an
anti-automation ceiling.

## Separate from Discovery

DateZA Discovery remains unimplemented and returns `matching_not_configured`.
It will require stable curated daily batches and may reuse compatibility semantics, not the
Find exposure ledger or Find cursor.

## Deferred

- DateZA Discovery 10.
- Paid/DateZA+ allowance policy and subscriptions.
- RealMe, public Trust standing, AI Matchmaker, analytics ingestion, and frontend.

No analytics events are emitted yet because D8N has no domain-event/analytics
mechanism to reuse; this ticket does not invent one.
