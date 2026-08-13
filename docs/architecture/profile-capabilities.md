# D8N Profile Capabilities

## Core Rule

Profile capabilities are shared, typed, and brand-scoped. A brand composes supported capabilities; it does not create arbitrary database fields or executable JSON rules.

`User` remains platform identity. `Profile`, profile details, options, preferences, media, and completion remain private to one brand membership.

## Typed Profile Details

The shared `profiles` table owns stable dating-presence details such as:

- Display name, bio, birthdate, and gender
- Country and city
- Occupation, height, and body type
- Languages and lifestyle answers
- Profile status and visibility

Owner serialization may return the private birthdate. Public serialization returns derived age and never returns birthdate, coordinates, user identity, credentials, or other private source data.

## Controlled Options

Controlled vocabularies use three brand-scoped records:

```text
ProfileOptionGroup
  has many ProfileOptions

Profile
  has many ProfileOptionSelections
```

Groups declare cardinality, maximum selections, visibility, status, and display order. Options have stable machine codes, editable labels, status, and display order.

Machine keys and codes are immutable. Retired options are omitted from configuration and cannot receive new selections, while historical selections remain readable. Required groups cannot be retired or deleted until the brand requirements are changed.

Composite foreign keys ensure that selections, options, groups, profiles, users, and brands agree even when application validations are bypassed.

## HookUs Catalog

`Profiles::HookusProfileCatalog` installs HookUs intents and vibes idempotently. Both are multi-select, public-profile option groups and both are required for HookUs completion.

The catalog also installs HookUs's initial required profile fields, preferences, and photo collection. It can be run through seeds after the HookUs brand exists.

## Completion

`Profiles::Completion` is the authoritative completion calculation. It evaluates:

- Required typed profile fields
- Required preference fields
- Required collections
- Required controlled option groups

The owner profile response derives its completion status from this service. Branded clients should not maintain a separate completion predicate.

## API Contract

Authenticated, brand-resolved routes:

- `GET /api/v1/profile/configuration` returns enabled fields, requiredness, groups, active options, cardinality, limits, and visibility.
- `PATCH /api/v1/profile` updates typed profile fields.
- `PATCH /api/v1/profile/options` replaces only the option groups supplied in the request.

Example option update:

```json
{
  "selections": {
    "intents": ["hookups", "casual"],
    "vibes": ["nightlife", "music"]
  }
}
```

Omitted groups remain unchanged. Sending an empty array clears that group. Unknown groups, unknown or retired options, malformed values, and selection-limit violations are rejected.

## Scope Boundary

Hook Tonight, interaction allowances, presence, verification, trust, billing, matching, and messaging do not belong to profile options. They remain dedicated domains even when a profile response eventually includes derived state from them.
