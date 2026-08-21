# ADR 0017: Reusable profile capabilities (D8N capability catalogue)

## Status

Accepted on 2026-08-18. Builds on ADR 0003 (identity vs brand profiles) and
ADR 0008 (compose brand profile capabilities). HookUs is the first consumer; the
capabilities are platform-level and intended for reuse by DateZA, Date9ja and any
future brand.

## Context

HookUs profiles needed to become much richer — identity, lifestyle, connection
intent, interests, prompts, personality/vibe, family/religion, optional intimacy
preferences and safe location metadata — while keeping almost everything optional
and not increasing onboarding friction.

The trap was two-fold: (1) stuffing dozens of nullable columns onto `profiles`,
and (2) hardcoding the schema/taxonomies/rules around HookUs so a future brand
would have to fork profile infrastructure. Neither is acceptable. The requirement
is a **configurable profile platform brands compose, not rebuild**.

The codebase already had the right primitive: `profile_option_groups` /
`profile_options` / `profile_option_selections` — a brand-scoped, per-brand,
visibility-aware, single/multi-select controlled taxonomy with soft-delete,
immutable codes, positions and `max_selections`. It already backed the HookUs
`intents`/`vibes` groups, serialized under `options`, and drove completion.

## Decision

### Data placement: the right home for each kind of field

- **Scalar identity/free-text** → columns on `profiles`. Added (all nullable,
  default-safe, length-capped, stripped): `pronouns`, `job_title`, `company_name`,
  `school_or_institution`, `looking_for_text`, `children_count`, and structured
  `languages` (jsonb). No existing column changed; existing payloads are untouched.
- **Controlled vocabulary** (orientation, education, religion, diet, cannabis,
  lifestyle, relationship intent, meeting pace, personality/communication/planning
  style, family, intimacy preferences, …) → the existing **option-group taxonomy**,
  never new columns. This keeps `profiles` from becoming a 90-column table and
  makes each capability brand-configurable for free.
- **Many-to-many interests** → a single categorized option group (`interests`),
  enabled by a nullable `category` column added to `profile_options`, rather than
  one group per category or a parallel Interest/ProfileInterest schema.
- **Prompts** → dedicated `profile_prompts` (brand-configurable definitions) +
  `profile_prompt_answers` (free text). The answer belongs to a Profile (the
  authoritative owner of member + brand); `brand_id` is denormalised **only** to
  satisfy the tenant-safe composite foreign keys, and `user_id` is intentionally
  NOT denormalised.

### The capability catalogue (generic vs brand)

`Profiles::CapabilityCatalog` is the generic, brand-agnostic layer: DEFINITIONS of
capabilities (option-group templates, the interests taxonomy, prompt definitions)
plus idempotent installers. It holds no brand policy.

A brand catalogue (`Profiles::HookusProfileCatalog`) COMPOSES a subset, choosing per
capability: whether it is enabled, its label/copy, its public visibility, and which
allowed values to offer. A new brand is added by writing its own catalogue that
calls the same installers — **without editing the generic catalogue**.

```
CapabilityCatalog (generic: languages, interests, prompts, lifestyle, intent,
                   children, religion, personality, intimacy, …)
        │
   ┌────┴─────┬──────────┐
 HookUs     DateZA     Date9ja      ← each brand catalogue enables a subset,
 catalogue  catalogue  catalogue      relabels, sets visibility, picks values
```

### Stable codes, brand labels

Capability keys and option/prompt codes are **stable internal identifiers with
fixed cross-brand meaning** (e.g. `relationship_intent => short_term_fun`).
Marketing copy never leaks into a code; brands relabel. Example: the cannabis
`friendly` code is relabelled to "420 friendly" for HookUs.

### Visibility, including sensitive capabilities

`profile_option_groups.visibility` gains `matches_only` alongside `owner_only` and
`public_profile`, so a sensitive-but-shareable capability (intimacy preferences)
can exist without being locked into the public serializer. Sensitive capabilities
(orientation, religion, children, cannabis, intimacy) default to a **conservative,
non-public** visibility in the generic catalogue and are **never auto-installed** —
a brand opts in explicitly and sets visibility deliberately. Adding a capability to
D8N therefore never auto-exposes it on every brand.

`matches_only` fields are surfaced only via the profile-detail path, which already
enforces current reachability (brand isolation, active/visible lifecycle, blocks in
either direction — `Matching::VisibilityScope`); on top of that an **active** Match
must exist. A blocked/closed/ended relationship therefore hides them even though a
Match row once existed.

### Serialization split (backward compatible)

- `OwnerSerializer` — everything, unfiltered (the owner sees their own data).
- `PublicSerializer` — the lean viewer-facing base used by discovery, matches and
  conversations. It gains only cheap additive fields (`pronouns`, structured
  `languages`, a safe approximate `location` object) and continues to expose only
  `public_profile`-visibility groups. **No existing field is removed**, so the
  discovery/match/conversation contracts stay backward compatible.
- `DetailSerializer` — `PublicSerializer` plus the rich sections (grouped
  interests, prompts, `matches_only` groups when matched, education/religion/
  children per visibility) for `GET /profiles/:id` only, bulk-preloaded to keep the
  query count fixed. Richness lives on detail, not on every discovery card.

### Completion stays informational

Completion remains brand-configured (`profile_completion_requirements`) and gains an
informational `sections` breakdown. Enabling a capability adds NO onboarding
requirement; thin existing profiles remain valid and discoverable.

## Consequences

- Future brands compose profiles instead of rebuilding them; the generic catalogue
  is the single source of capability definitions.
- `languages` (structured) is the canonical model going forward. The legacy
  free-text `languages_spoken` is retained for backward compatibility and is
  **deprecated**: new clients should write `languages`. Migration/deprecation path:
  (1) clients dual-read, preferring `languages`; (2) backfill `languages` from
  `languages_spoken` where empty; (3) stop writing `languages_spoken`; (4) drop it
  in a later, separate migration once no client depends on it.

## Deferred

- Profile anthem/music (Spotify/Apple) — only a documented field seam, not built.
- Politics/ideology fields — intentionally not added.
- Per-field (as opposed to per-capability) visibility for scalar columns — the
  `matches_only`/`owner_only`/`public_profile` lever is at the option-group level;
  scalar columns use fixed serializer placement (e.g. `company_name` owner-only)
  for now.
