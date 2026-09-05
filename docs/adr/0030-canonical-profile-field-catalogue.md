# ADR 0030: Canonical profile field catalogue

## Status

**ACCEPTED (2026-09-05).**

## Context

Before this feature, D8N's scalar profile fields had four scattered,
occasionally disagreeing sources of truth:

- `Profiles::Configuration` hard-coded field labels, input types, and
  owner/public split as private constants (`*_LABELS`, `FIELD_METADATA`).
- `Profiles::FieldPolicy` hard-coded a second, independent owner/public split
  (`OWNER_ONLY_PROFILE_FIELDS`, `PUBLIC_PROFILE_FIELDS`).
- `Brand::DEFAULT_PROFILE_REQUIREMENTS` and `Brand#profile_requirements_are_supported`
  validated against yet another surrogate list of "known" fields.
- `Profile`/`ProfilePreference` model validations (max length, numeric bounds,
  enums, format) were hand-written per attribute, with no canonical source for
  the constraint *values* themselves.
- `Profiles::Completion::SUPPORTED_IDENTITY_FIELDS` / `SUPPORTED_PROFILE_FIELDS`
  / `SUPPORTED_PREFERENCE_FIELDS` were a fifth registry of "which fields exist."

None of these disagreed destructively today, but nothing prevented drift, and
there was no single place a new brand (or Date9ja specifically) could consult
to learn what a profile field *is* — its type, sensitivity, storage, audience
ceiling, and validation — independent of which brand happens to use it. This
is the shared-platform blocker recorded in
[`MASTER-PLAN.md`](../migrations/date9ja-to-d8n/MASTER-PLAN.md) Phase 1 item 2,
"Before writable Date9ja profiles."

`Profiles::CapabilityCatalog` (ADR 0017) already solved the equivalent problem
for **controlled-vocabulary / option-group** capabilities (religion, intents,
vibes, etc.). It intentionally does not cover plain scalar/typed fields
(strings, dates, integers, bounded lists) — a different, simpler shape.

## Decision

**Introduce `Profiles::FieldCatalog` as the single canonical definition layer
for scalar/typed profile capabilities, alongside the existing
`Profiles::CapabilityCatalog` for controlled vocabularies. Do not build one
mega-framework that swallows both.**

### Two canonical definition layers, not one

| Layer | Owns |
|---|---|
| `Profiles::FieldCatalog` | Scalar/typed fields: strings, dates, integers, enums-as-scalars, bounded lists (`display_name`, `birthdate`, `height_cm`, `smoking`, `languages`, `interested_in`, …). |
| `Profiles::CapabilityCatalog` | Controlled vocabularies / option groups: multi-record, brand-installable, machine-coded option sets (`religion`, HookUs intents/vibes, …). |

A concept that is already a `CapabilityCatalog` option group (religion is the
proving example — see §"Religion and other deferred concepts") is **not**
duplicated as a `FieldCatalog` scalar merely because a legacy source stored it
as a plain column. One canonical home per concept.

### Responsibility boundaries

**`Profiles::FieldCatalog` owns canonical semantics**, immutable per field and
never brand-overridable:

- stable `key` and human `label`
- semantic `group` (`:identity` / `:profile` / `:preference`)
- `data_type` / `input_type` / `cardinality`
- `sensitivity` (`:standard` / `:owner_private` / `:sensitive_identity`)
- `storage` — which record/column owns the value, or `record: :pending` if
  none is approved yet
- `value_source` (plain scalar, an enum, a catalogue reference, …)
- canonical reusable validation **constraint values** (max length, numeric
  bounds, enum membership, format, list limits)
- `default_audience` — the audience **ceiling** a brand can never widen
- `completion_requirable` — whether the field is eligible to be required for
  profile completion at all

**The brand contract/catalogue** (e.g. `Profiles::Date9jaProfileCatalog`,
`Profiles::DatezaProfileCatalog`) owns:

- whether the brand supports/enables the capability at all
- whether it participates in that brand's completion requirements
- brand-specific selection within the safety limits FieldCatalog sets

**`Profiles::FieldPolicy`** owns:

- the effective enabled set per brand (`enabled_profile_fields`, etc.)
- the effective writable set, and fail-closed rejection of anything else
- the effective serialization permission (owner vs. public)

**`Profiles::Configuration`** owns:

- the client-facing representation of a brand's effective capability set
  (labels, input types, options, requiredness)

**Serializers** (`OwnerSerializer`, `PublicSerializer`, `DetailSerializer`)
own rendering only — they ask `FieldPolicy` what is permitted and render it;
they do not decide permission themselves.

**Models/domain services** (`Profile`, `ProfilePreference`,
`Profiles::Completion`) own persistence and explicit domain invariants that
are not reusable canonical constraints (see §"Validation ownership").

## The core invariant

This is the central architectural rule this feature enforces everywhere:

```
D8N KNOWS A CAPABILITY
  ≠ A BRAND USES IT
  ≠ IT IS WRITABLE
  ≠ IT IS PUBLIC
  ≠ IT IS COMPLETION-REQUIRABLE
  ≠ IT PARTICIPATES IN DISCOVERY
  ≠ IT PARTICIPATES IN MATCHING
```

Each of these is an independent, narrowing condition. `FieldCatalog` only
ever answers the first. Every subsequent condition is decided by a later,
more specific layer (`FieldPolicy`, `Brand` config, `Completion`, discovery/
matching code), and each layer may only narrow — never widen — what the
layer before it allowed. A brand can turn a known field off; it can never
turn a canonically-restricted field on.

## Known vs. enable-able

`FieldCatalog.keys_for_group(group)` is the canonical **known superset** —
every field D8N has ever defined for that group, including
`sensitive_identity` and `storage: :pending` fields. It is used deliberately
in exactly one place: the "known-but-rejected" write path, so that writing a
sensitive or brand-disabled field returns a deterministic `422
invalid_profile_fields` rather than being silently ignored.

`FieldCatalog.enableable_keys_for_group(group)` is the **safe subset** —
`keys_for_group` minus every `sensitive_identity` and `storage: :pending`
field. It is used everywhere a default, an advertisement, or a brand
validation ceiling is computed: `Brand#profile_requirements_are_supported`,
`Profiles::Configuration`, `D8n::Platform::BrandContract#snapshot_profile_fields`,
and `Profiles::FieldPolicy`'s own enable resolution.

Conflating these two was the one real defect caught during this feature's own
build (see the tribe/ethnicity example below): naming a sensitive field in
`keys_for_group` alone would have let a brand relying on the broad default
silently inherit it. `enableable_keys_for_group` exists specifically to make
that impossible by construction rather than by remembering to exclude it at
each call site.

`storage: :pending` means **"this canonical concept is defined, but D8N does
not yet provide an approved storage or enablement path for it."** It does
**not** mean "temporarily writable somewhere else," "writable through a
side channel," or "safe to relax later without an explicit storage decision."
A `:pending` field has no column, is `owner_only` by ceiling, and is never
`completion_requirable`.

## Validation ownership: Category A vs. Category B

A generic catalogue-driven validation DSL/concern (a `Profiles::CatalogValidation`
that would replace `validates` calls with metaprogrammed rules) was
considered and **explicitly rejected** — it would have hidden explicit,
debuggable Rails validations behind an extra layer of indirection for a
problem that does not require it.

Instead:

- **Category A — canonical constraint values.** Reusable *values* that
  belong to the field's identity, not to any one model: maximum length,
  numeric bounds, allowed enum values, canonical format, list-size limits.
  These live in `FieldCatalog` as data (`max_length`, `numericality`,
  `allowed_values`, `format_pattern`, `list_limits`) and are read by
  ordinary, explicit Rails `validates` calls in `Profile` and
  `ProfilePreference` — e.g. `validates :height_cm, numericality:
  Profiles::FieldCatalog.numericality("height_cm")`. The validation
  *structure* stays plain Rails; only the constraint *value* moved.
- **Category B — domain/model invariants.** Rules that are not simple
  reusable values: the dating minimum-age rule, min/max preference ordering,
  tenant/profile scope agreement, the structured-language taxonomy check,
  array-shape semantics, uniqueness, and normalization callbacks. These
  remain explicit, hand-written methods on the model. `FieldCatalog::Field`
  carries an optional `bespoke_invariant` name purely as documentation,
  pointing at the real private method that enforces it — it is not executed
  by the catalogue.

There is one semantic source of truth for a Category A constraint's *value*;
Rails validation declarations stay explicit and grep-able.

## Completion ownership

`completion_requirable` is now catalogue metadata on `FieldCatalog::Field`
(`completion_requirable?` is `false` whenever a field is
`sensitive_identity` or `storage: :pending`, regardless of the flag). The old
`Profiles::Completion::SUPPORTED_IDENTITY_FIELDS` /
`SUPPORTED_PROFILE_FIELDS` / `SUPPORTED_PREFERENCE_FIELDS` registries were
removed — they duplicated exactly this information with no additional
meaning. `Brand#profile_requirements_are_supported` now validates a brand's
required-field list against `FieldCatalog.completion_requirable_keys(group)`.

`Profiles::Completion::SUPPORTED_COLLECTIONS` (`photos`, `location`) is
**unchanged and stays where it is** — collections (photos, location) are not
scalar `FieldCatalog` capabilities; they have their own presence semantics
and do not belong in this catalogue.

## Sensitive capability example: tribe and ethnicity

`tribe` and `ethnicity` are defined in `FieldCatalog` as the proving example
of a canonical identity concept that exists **and is fully inert**:

- `sensitivity: :sensitive_identity`
- `storage: { record: :pending }`
- `default_audience: :owner_only`
- `completion_requirable: false`
- not enabled by any brand (HookUs, DateZA, or Date9ja)
- no database column added
- no Date9ja value migration performed

They are deliberately **known** (`FieldCatalog.defined?` is true, they appear
in `keys_for_group`) so that a write attempt is rejected deterministically
(`422 invalid_profile_fields`) rather than silently dropped, while being
excluded from `enableable_keys_for_group` so no brand — including one that
relies on the broad default — can enable, serialize, or require them.

**This ADR does not approve tribe or ethnicity as Date9ja product fields.**
Whether, how, and to whom they are ever collected, stored, or exposed remains
an open product decision (see `DECISIONS.md`), unaffected by their existing
as inert canonical definitions.

## Religion and other deferred concepts

- **Religion** already exists as a `Profiles::CapabilityCatalog` controlled
  vocabulary (`OPTION_CAPABILITIES.key?("religion")`) and is **not**
  duplicated as a `FieldCatalog` scalar merely because Date9ja's legacy
  schema stored it as a plain column. Legacy source representation does not
  determine canonical D8N architecture (see the new-brand workflow below).
- **Denomination** is deferred pending a hierarchy/representation decision
  (is it a flat vocabulary, or nested under a selected religion?).
- **Genotype** is deferred pending a product and security/modelling decision
  (health-adjacent data; see `DECISIONS.md` "Retain genotype").
- **State of origin** is deferred pending an origin-place capability
  decision — it is not simply a country/city pair.
- **Preferred tribes / preferred religion** are preference/matching concepts,
  not ordinary profile identity scalars, and are deferred alongside the
  matching-use product decision.

None of these product decisions are made or implied by this ADR.

## New-brand profile workflow

When a new brand or product needs profile data:

1. List the product's required profile capabilities.
2. Check whether `Profiles::FieldCatalog` (scalar) or
   `Profiles::CapabilityCatalog` (controlled vocabulary) already defines the
   matching canonical concept.
3. Reuse the existing canonical capability whenever the semantics match —
   legacy source representation does not determine canonical D8N
   architecture; a field stored as a plain column in one legacy app can
   still be the same canonical concept as a controlled vocabulary elsewhere.
4. If the capability is genuinely new and reusable, define it **once**, in
   the appropriate catalogue, with its full safety metadata (sensitivity,
   storage, audience ceiling, validation).
5. Add approved storage/domain support where the definition requires it
   (only when the capability is meant to become enable-able).
6. Explicitly select the capability in the brand's own profile
   catalogue/contract (`enabled_profile_fields`, etc.).
7. Configure required/onboarding/audience/presentation behavior for that
   brand, within the canonical safety ceiling — a brand may narrow (e.g.
   restrict audience, decline to require it) but never widen what the
   catalogue defines.
8. The shared `FieldPolicy` / `Configuration` / models / serializers enforce
   the resulting contract automatically. No brand rebuilds the field.

### Worked example — reusing an existing field

DateZA needs a "languages" field on its profile. `languages` already exists
in `FieldCatalog` (`value_source: :languages_catalog`, multi-select,
public). DateZA enables it in `Profiles::DatezaProfileCatalog::REQUIREMENTS`.
No new column, controller, or serializer path is written — `FieldPolicy`,
`Configuration`, `Profile`, and the serializers already know how to enable,
write, validate, and render it because they consume `FieldCatalog`, not a
per-brand implementation.

### Worked example — adding a genuinely new field

Suppose a future product needs a canonical, reusable "preferred pronouns"
scalar that does not yet exist:

1. Confirm no existing `FieldCatalog` or `CapabilityCatalog` entry matches.
2. Define it once in `FieldCatalog` with its type, sensitivity (`:standard`),
   storage (a real column, once approved), validation, and audience default.
3. Add the approved storage column via a normal migration.
4. Product A enables it in its own brand catalogue.
5. Product B can later enable the *same* capability with its own policy
   (different requiredness, different audience narrowing) — but cannot
   redefine its canonical type, sensitivity, or storage. Product B does not
   get to invent a second "pronouns" concept with different semantics.

## Consequences

- One authoritative place answers "what is this scalar profile field,"
  independent of which brand uses it.
- A brand cannot casually redefine a canonical field's type, sensitivity, or
  storage — only whether/how it participates.
- Sensitive and not-yet-approved concepts can be named and reasoned about
  (tests, documentation, deterministic rejection) without being enable-able
  by construction.
- Adding Date9ja as a full, explicit, safe consumer of this architecture
  required **zero new production code** (see the Date9ja proving-ground
  evidence, `STATUS.md`) — validating that the foundation generalizes to a
  real second/third brand without brand-slug branching.
- HookUs still relies on the broad `enableable_keys_for_group` default
  rather than an explicit `enabled_profile_fields` list. This remains safe
  (the default excludes every sensitive/pending field) and is recorded as a
  non-blocking follow-up observation, not addressed by this ADR — HookUs's
  field selection was not in scope.
