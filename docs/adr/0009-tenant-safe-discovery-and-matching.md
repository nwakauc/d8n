# ADR 0009: Use Tenant-Safe Profile Matching

## Status

Proposed for Phase 4. Founder/CTO review is required before matching or precise-location migrations begin.

## Context

D8N must power dating brands with different dating intentions and matching philosophies without allowing cross-brand disclosure or creating a backend fork per brand.

HookUs and the live Date9ja application provide two concrete inputs:

- Both need age, reciprocal preference, distance, visibility, interaction, match, and block exclusions.
- HookUs ranks intent and vibe overlap heavily.
- Date9ja applies bilateral cultural, faith, relocation, family, and relationship preferences and has a materially different compatibility score.
- Both legacy applications attach likes and matches directly to `User`. D8N cannot copy that model because `User` is network identity while `Profile` is the brand-specific dating actor.
- Both legacy applications keep precise coordinates private, but store them with the broad user record. D8N needs a narrower privacy boundary.

Discovery, interaction writes, and location all touch tenant isolation and sensitive personal data. Their rules must be explicit before schema work begins.

## Decision

### Match Profiles, Not Network Identities

Discovery candidates, likes, passes, and matches identify brand profiles. They do not use a platform `User` as the dating actor.

Every matching record is brand-owned and must prove that every referenced profile belongs to that same brand. Migrations must use database checks, composite foreign keys, and partial unique indexes where practical; Rails validations alone are insufficient.

No matching query or write may infer brand from a client-supplied profile. The current request brand and authenticated user's active profile establish the tenant context.

### Separate Eligibility, Ranking, And Product Policy

Discovery has three boundaries:

1. Shared eligibility determines who may legally and safely appear.
2. A brand matching strategy filters and ranks eligible candidates.
3. Product policy applies allowances such as daily limits, premium actions, or curated introductions.

Shared eligibility must include current-brand ownership, active membership and identity state, kept and visible profile state, minimum-age enforcement, no self-profile, reciprocal gender/preference compatibility, and matching-domain exclusions. Trust blocks and network enforcement will plug into this boundary through explicit interfaces as those domains are implemented.

Eligibility must be checked again when a like or pass is written. A discovery response is not authorization to interact later.

Brand strategy selection uses an explicit registry or policy boundary. Scattered checks such as `if brand.hookus?` are not allowed. A strategy may use only declared profile capabilities and must return a deterministic score/order with bounded, presentation-safe reasons.

The first HookUs strategy may use intent overlap, vibe overlap, age fit, and distance fit. Verification, presence, paid boosts, and temporary availability are omitted until their owning domains provide explicit inputs.

The initial Date9ja strategy is an interface and test placeholder only. Production Date9ja ranking cannot be implemented until its migration mappings and sensitive-attribute decisions pass the ADR 0008 gate.

### Store Precise Location Separately

Precise coordinates belong in a dedicated, brand-owned profile-location record, not `User`, `Profile#metadata`, or a public profile payload.

The location record must:

- reference one profile, user, and brand through tenant-consistent database constraints;
- record update time and enough source/accuracy information to reason about stale or low-quality data;
- support explicit replacement and deletion;
- never be copied to another brand automatically;
- be excluded from public serializers, logs, analytics payloads, audit metadata, and matching explanations.

City and country remain coarse profile attributes. Public discovery may return a rounded distance or coarse distance band only when product requirements justify it. It must never return latitude, longitude, a precise address, or enough precision to reconstruct a member's location.

Initial distance filtering will use a PostgreSQL bounding box followed by a parameterized Haversine calculation. PostGIS is deferred until measured query volume or geographic features justify the dependency.

Distance preference is bilateral: when both profiles have usable coordinates and distance limits, each profile must be within the other's limit. Missing or stale coordinates follow an explicit brand policy; they must not silently become zero distance.

### Use Stable Public Profile Identifiers

Discovery and interaction APIs address profiles through an unguessable, stable public identifier. Internal database IDs and platform user IDs are not public profile identifiers.

Public profile responses use an explicit serializer. They expose derived age rather than birthdate, public option groups only, approved visible photos only, and no owner-only or precise-location data.

### Make Interactions Idempotent And Concurrently Safe

Likes and passes are soft-deletable operational records scoped to one brand and one directed profile pair. Positive interaction kinds are controlled matching-domain values; HookUs's stronger `hook` action is not represented as arbitrary metadata.

Commands, not controllers or model callbacks, own interaction transitions. A command must lock participant profile rows in deterministic order, or use an equivalent database serialization mechanism, recheck eligibility, and produce an idempotent result.

A mutual positive interaction creates exactly one match. Match participants are stored in deterministic profile-ID order, constrained to the same brand, and protected by a unique active-pair index. Concurrent opposite-direction likes must not create duplicate matches or duplicate downstream events.

Notification delivery and messaging creation do not occur inside the matching transaction. A newly-created match may enqueue an after-commit notification handoff when the Notifications domain is ready.

### Paginate With Opaque Cursors

Discovery uses bounded keyset/cursor pagination, not unbounded Ruby sorting or offset pagination. The cursor is opaque to clients and includes the deterministic ranking boundary needed by the selected strategy.

Strategies must avoid N+1 queries and loading an entire brand population into memory. Any initial bounded candidate-pool compromise must have an explicit maximum and query tests before beta traffic.

## Initial Data Shape

The first migrations are expected to introduce:

- a public identifier on profiles;
- one private profile-location record per active profile;
- directed, brand-scoped likes;
- directed, brand-scoped passes;
- canonical, brand-scoped matches.

Exact column names and indexes remain an implementation-plan concern, but the migrations must preserve profile ownership, brand consistency, no-self rules, canonical match ordering, idempotency, and soft deletion at the database layer.

## Deferred From The First Slice

- Daily introductions or picks.
- Hook allowances, rewind allowances, boosts, and paid ranking.
- Presence and online-now ranking.
- Blocks, reports, and network enforcement implementation.
- Match notifications and messaging.
- Date9ja production scoring and migration.
- PostGIS, geocoding, location history, and background location tracking.
- Machine-learning recommendations.

The matching interfaces must permit these capabilities later without pretending they already exist.

## Consequences

- One person can participate independently in multiple brands without cross-brand likes or matches.
- Shared safety and eligibility rules are reusable while ranking remains brand-specific.
- Matching records carry more explicit ownership than the legacy applications.
- Location privacy has a narrow storage and serialization boundary.
- Database constraints and command-level locking add implementation work but prevent high-impact tenant and concurrency failures.
- Brands cannot invent executable matching rules through arbitrary JSON configuration.

## Alternatives Considered

- Attach likes and matches directly to platform users.
- Keep coordinates on `User` or in profile metadata.
- Copy HookUs or Date9ja discovery controllers into D8N.
- Put all eligibility and scoring in one brand-specific service.
- Use offset pagination and rank every candidate in Ruby.
- Build a generic rules engine or machine-learning recommender before two production strategies exist.

## Approval Gate

Before Phase 4 migrations begin, review and approve:

1. Profile-level matching ownership and tenant constraints.
2. The shared eligibility versus brand-ranking boundary.
3. Precise-location collection, retention, and public-distance policy for HookUs beta.
4. HookUs behavior for incomplete, hidden, or stale-location profiles.
5. The first-slice deferrals above.
