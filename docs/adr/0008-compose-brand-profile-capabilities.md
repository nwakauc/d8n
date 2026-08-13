# ADR 0008: Compose Brand Profile Capabilities

## Status

Proposed. Implementation requires founder/CTO approval of this ADR and the accompanying field matrix.

## Context

D8N must support dating brands with materially different intentions and onboarding requirements without creating a backend fork per brand.

HookUs and the live Date9ja product provide two concrete inputs. Date9ja has existing users and must be treated as a production migration, not a clean brand configuration:

- HookUs emphasizes intent, vibe, proximity, and temporary availability.
- Date9ja emphasizes culture, faith, relationship goals, relocation, family expectations, and compatibility questions.

The current D8N completion configuration selects required fields from a fixed allow-list. That is useful for simple differences, but it cannot express Date9ja's simultaneous conditional rules:

- Nigerian members require state of origin and tribe; other members require nationality.
- Members willing to relocate require one or more relocation destinations.

An unrestricted dynamic schema or generic entity-attribute-value model would make validation, authorization, filtering, indexing, serialization, and migration harder to reason about. Adding every reference application field directly to `Profile` would instead mix dating profile data with temporary availability, entitlements, trust, billing, and other domains.

The evidence and proposed ownership of existing fields are recorded in `docs/architecture/profile-field-matrix.md`.

## Decision

### Preserve Identity And Tenant Boundaries

`User` remains the platform identity. `BrandMembership`, `Profile`, `ProfilePreference`, and all dating activity remain brand-owned.

A profile capability never makes a user visible in another brand. Profile import, photo reuse, and cross-brand disclosure remain explicit opt-in operations.

### Use A Code-Owned Capability Catalog

D8N will expose a controlled catalog of profile and preference capabilities. Each capability has a stable machine key and declares:

- Owning domain and storage type
- Scalar, single-select, multi-select, collection, or questionnaire cardinality
- Validation and size limits
- Public, private, or derived visibility
- Whether it may participate in completion, discovery, filtering, or matching
- Supported option source where applicable

Brands configure which supported capabilities are enabled, required, optional, hidden, or used by a brand policy. Brands cannot define arbitrary executable rules or arbitrary public JSON fields.

### Choose Storage By Semantics

Platform-stable scalar concepts with distinct behavior use explicit typed attributes or focused typed records. Examples include birthdate, location, age range, distance, visibility, and booleans used by conditional rules.

Closed single-select concepts with stable semantics, such as relationship intention or wants-children preference, remain named capabilities. A brand may configure the allowed option subset and labels, but the value does not become anonymous metadata.

Evolving multi-select vocabularies, such as HookUs vibes and Date9ja relationship values, use controlled option groups and selections when they need filtering, matching, administration, or retirement. Single-select option groups must declare a maximum selection of one; multi-select groups must declare an explicit maximum.

Free text remains typed and bounded. It is not silently converted into a taxonomy merely because a frontend presents suggestions.

Compatibility questions and answers that affect matching use a dedicated, version-aware questionnaire capability. They do not live indefinitely in unversioned profile metadata.

`metadata` is reserved for bounded, non-critical extension data that is not used for authorization, completion, filtering, matching, billing, moderation decisions, or public serialization without an explicit contract.

### Compose Completion Rules

Simple requiredness remains configuration over supported capability keys.

Conditional completion uses code-owned, composable policy rules. A brand policy may activate multiple rules at the same time. Each rule returns structured missing items and does not mutate the profile.

The first Date9ja proof must evaluate both conditional axes together:

- `is_nigerian == true` requires `state_of_origin` and `tribe`.
- `is_nigerian == false` requires `nationality`.
- `willing_to_relocate == true` requires `relocation_preferences`.
- `willing_to_relocate == false` does not require relocation destinations.

Policies are selected through an explicit brand strategy/configuration boundary. Scattered checks such as `if brand.hookus?` are not allowed.

### Publish A Server-Owned Profile Contract

D8N will eventually expose a brand-scoped profile/onboarding contract containing enabled sections, field keys, cardinality, requiredness hints, allowed options, limits, and presentation-safe labels.

The contract helps branded clients render consistent choices, but it does not replace backend validation or authorize access. Public profile serializers remain explicit allow-lists and may expose derived values, such as age, instead of private source values, such as birthdate or coordinates.

### Preserve Option History

Option machine codes are stable and are not silently renamed or reused.

- Labels may change and may be localized.
- Retired options are unavailable for new selections.
- Existing selections remain readable after retirement.
- Replacements require an explicit data migration or mapping decision.
- Deleting an option must not silently delete member selections.

Full schema publication/version negotiation is deferred. Minimum option lifecycle behavior is required before Date9ja production data is migrated.

### Keep Domain Workflows Out Of Profile Configuration

This ADR governs profiles, preferences, onboarding completion, controlled profile vocabularies, compatibility questions, and profile serialization only.

It does not redesign:

- Hook Tonight availability
- Hook, rewind, or other interaction allowances
- Presence and last-active tracking
- Verification and trust state
- Subscription and billing state
- Matching, messaging, notifications, moderation, or admin authorization

Those remain focused domain capabilities even when their derived state appears in a profile response.

## Approval And Implementation Gate

No migration or production implementation based on this ADR may begin until:

1. The founder/CTO reviews this ADR.
2. The HookUs and Date9ja field matrix is reviewed against product intent and migration reality.
3. Unresolved field classifications are decided.
4. Date9ja production data characteristics and migration mappings are confirmed.

After approval, implementation should be additive and proceed in small migrations with tenant-isolation, completion, serialization, option-lifecycle, and migration tests.

## Consequences

- New brands can compose supported profile capabilities without backend forks.
- New labels and controlled options usually require configuration rather than migrations.
- Genuinely new data semantics may still require a focused capability and migration.
- Conditional onboarding remains testable Ruby policy code instead of a general-purpose rules language stored in JSON.
- Query-critical data remains validatable and indexable.
- A capability catalog and option lifecycle introduce more structure than the current flat allow-list.
- D8N must maintain stable capability and option keys once production data depends on them.

## Alternatives Considered

- One `User` and profile schema per brand.
- Separate backend repositories per brand.
- Store all brand fields in `profiles.metadata`.
- A generic entity-attribute-value table for every profile value.
- Add every HookUs and Date9ja field directly to the base `profiles` table.
- Store arbitrary conditional expressions in brand JSON configuration.
