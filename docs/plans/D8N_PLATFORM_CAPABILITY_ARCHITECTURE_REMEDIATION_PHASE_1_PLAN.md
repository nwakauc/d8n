# D8N Platform Capability Architecture Remediation — Phase 1 Plan

**Status:** Proposed implementation plan  
**Repository:** D8N Rails backend  
**Prepared:** 2026-08-24  
**Implementation status:** Not started  
**Scope:** Platform architecture remediation only

## 1. Purpose

D8N owns reusable platform capabilities. Brands consume and compose those capabilities through explicit enablement, policies, strategies, and configured surfaces.

The governing rule is:

> Capabilities belong to D8N. Brands consume capabilities.

“Discover,” “Find,” “Explore,” “For You,” and “People” may be frontend names for differently configured D8N Discovery surfaces. Product naming and frontend navigation do not define backend architecture.

Hook Tonight illustrates the intended design. It is a HookUs-specific product capability, but it composes shared D8N identity, profiles, eligibility, Discovery, matching, messaging, trust, and media infrastructure. Product-specific semantics do not require product-specific infrastructure.

Phase 1 will tighten existing seams without rewriting the healthy platform core.

## 2. Architectural outcome

After Phase 1, the runtime model should be:

```text
Brand
  -> authoritative capability contract
      -> capability enabled?
      -> surface enabled?
      -> policy
      -> strategy
      -> facets
      -> exclusion contributors
      -> response decorators
  -> shared D8N capability engine
  -> brand frontend chooses product name and presentation
```

The primary engineering question should become easy to answer from one location:

> What D8N capabilities and surfaces does this brand consume?

This ticket does not build a dynamic plugin framework, rules language, separate backend per brand, or broad platform rewrite.

## 3. Platform vocabulary

The internal capability model should explicitly include D8N Profile and D8N Discovery alongside the public platform pillars:

```text
D8N Platform
├── D8N ID
├── D8N Profile
├── D8N Discovery
├── D8N Verify
├── D8N Match
├── D8N Chat
├── D8N Trust
├── D8N Pay
├── D8N AI
├── D8N Insights
└── D8N Admin
```

D8N Profile owns onboarding, profile configuration, preferences, options, interests, prompts, location, photos, completion, and publication.

D8N Discovery owns candidate retrieval, viewer eligibility, pair eligibility, filtering/facets, ranking, exposure/allocation, pagination, and configured surfaces.

These internal domains do not dictate the labels a brand shows in its frontend.

### 3.1 Namespacing is an architectural contract

Phase 1 must make four different kinds of names explicit. They must not be used interchangeably:

1. **D8N platform namespace** — the stable owner of a capability, such as D8N ID or D8N Trust.
2. **Implementation domain** — the current Ruby module that performs the work, such as `Identity` or `Matching`.
3. **Capability key** — the stable machine-readable feature name used by contracts and gates, such as `id.session` or `trust.report`.
4. **Brand surface and label** — the configured product entry point and the frontend words shown to a user, such as DateZA “Find” or HookUs “Discover.”

The same implementation domain may currently serve more than one platform namespace. That is acceptable during modular-monolith evolution when ownership is explicit. It is not acceptable for a frontend label or brand name to become the owner of a reusable engine.

### 3.2 Canonical D8N composition namespace

The new composition and capability metadata introduced by this ticket should live under the existing Rails application namespace:

```ruby
D8n::Platform
```

Ruby uses `D8n`, matching `config/application.rb` and Zeitwerk conventions. Product copy may continue to render the company name as `D8N`.

The intended small namespace is:

```text
D8n::Platform
├── Catalog                 # aggregate index; not the owner of every definition
├── CapabilityKey           # validated stable key/value object
├── BrandContract           # immutable composition for one brand
├── BrandRegistry           # resolves a contract from a Brand
├── CapabilityAccess        # deny-by-default gate
├── DiscoverySurface        # configured candidate-delivery surface
├── Capabilities
│   ├── Id                  # registration, credentials, sessions, lifecycle
│   ├── Profile             # onboarding and dating presence
│   ├── Discovery           # candidate-delivery features and surface types
│   ├── Verify              # contact and identity-verification levels
│   ├── Match               # eligibility, compatibility and interactions
│   ├── Chat                # conversations and communication modes
│   ├── Trust               # safety, enforcement and reputation
│   ├── Media               # upload, processing and delivery
│   ├── Notify              # events and delivery channels
│   ├── Pay                 # plans, entitlements and transactions
│   ├── Ai                  # matchmaker and assistants
│   ├── Insights            # analytics products
│   └── Admin               # operator and platform operations
└── Brands
    ├── Hookus              # HookUs composition only
    └── Dateza              # DateZA composition only
```

Each module under `D8n::Platform::Capabilities` owns definitions for its feature family, including stable keys, implementation state, dependencies, and implementation references. `Catalog` aggregates those definitions so it remains an index rather than a god object.

This namespace owns capability definitions and composition metadata. It does **not** become a facade around all business logic and does not replace the existing `Identity`, `Profiles`, `Matching`, `Messaging`, `Trust`, `Media`, `Notifications`, or `Admin` engines.

Phase 1 must not mechanically move every class under `D8n::*`. Such a move would create large autoload and constant churn without fixing capability ownership. Future domain moves require a separate ADR and evidence that the move improves a real boundary.

### 3.3 Platform namespaces and current implementation owners

| D8N namespace | Responsibility | Current implementation owner | Phase 1 treatment |
|---|---|---|---|
| D8N ID | identity, credentials, registration, sessions, recovery, membership/account lifecycle | `Identity`, `Accounts`, `Brands` | register existing features; preserve engine |
| D8N Profile | onboarding, dating presence, preferences, options, prompts, location, publication | `Profiles` and profile models | make configuration authoritative |
| D8N Discovery | candidate delivery, surfaces, facets, exclusions, exposure/allocation, cursors | principally `Matching::Discovery` and `Matching::Find` | make surfaces first-class; do not rename engine yet |
| D8N Verify | contact ownership and future real-person verification levels | contact verification currently in `Identity`; `Verification` is otherwise empty | register actual contact verification only; leave future levels unavailable |
| D8N Match | reciprocal eligibility, compatibility, recommendations, Like, Pass, Match | `Matching` | preserve shared engine; expose strategies through contracts |
| D8N Chat | conversations, messages and future realtime/voice/video | `Messaging` | register text capability only |
| D8N Trust | blocking, reporting, safety enforcement, future reputation/fraud | `Trust`, `AbuseProtection`; some enforcement workflows currently in `Admin` | expose current safety features; record ownership seam |
| D8N Media | private upload, processing, moderation state and signed delivery | `Media`, `Profiles` photo workflows | supporting platform namespace; reference brand policy/readiness |
| D8N Notify | event materialization, inbox, email, SMS and push | `Notifications` | supporting platform namespace; reference brand event/provider policy |
| D8N Pay | plans, entitlements, subscriptions, payments and marketplace | `Billing` placeholder only | catalogued as unavailable; not enabled by a brand |
| D8N AI | matchmaker and smart assistants | no implementation domain | catalogued as unavailable; do not scaffold an engine |
| D8N Insights | analytics and marketplace intelligence | `Analytics` placeholder only | catalogued as unavailable; operational records are not an Insights product |
| D8N Admin | operator authorization, moderation tools and platform operations | `Admin` (currently mainly trust enforcement) | catalog current moderation subset accurately |

D8N Profile, D8N Discovery, D8N Media, and D8N Notify are explicit engineering namespaces even if the marketing homepage chooses to emphasize only the nine headline pillars. They are too important to remain implicit or be forced into an unrelated namespace.

### 3.4 Stable capability-key grammar

Capability keys should use lowercase dotted names:

```text
<namespace>.<feature>[.<subfeature>]
```

Examples:

```text
id.registration
id.authentication.email_password
id.authentication.phone_password
id.session
id.password_recovery
verify.contact.email
verify.contact.phone
profile.onboarding
profile.publication
discovery.surface
match.interaction.like
match.interaction.pass
match.relationship
chat.message.text
trust.block
trust.report
media.profile_photo
notify.inbox
```

Keys describe D8N semantics, not frontend navigation. They must not contain a brand slug. Brand-specific strategies, policies, facets, pools, and decorators are contract values, not new universal keys. A planned capability may exist in the catalog but cannot be enabled until an executable implementation and contract tests exist. Public error codes remain stable even if an internal key is normalized.

### 3.5 Feature catalogue inside each namespace

The platform catalog should record each feature's owner, implementation status, implementation reference, dependencies, and whether it is brand-configurable. The initial catalogue must reflect code, not marketing intent.

#### D8N ID

```text
id.registration
id.authentication.email_password
id.authentication.phone_password
id.session.create
id.session.destroy
id.session.current
id.password_recovery
id.password_reset
id.contact_change.email
id.membership
id.account.close_brand_membership
```

These map to the shared `Identity`, `Brands`, and `Accounts` code. OAuth, cross-brand join/rejoin, device management as a product capability, and legal network erasure remain outside the enabled catalogue unless runtime code proves otherwise.

#### D8N Profile

```text
profile.onboarding
profile.scalar_fields
profile.options
profile.preferences
profile.prompts
profile.interests
profile.languages
profile.location
profile.photos
profile.completion
profile.publication
profile.visibility
```

Brands configure field catalogues, required fields, option groups, prompts, completion, publication, and media policy. They do not get separate profile controllers or tables.

#### D8N Discovery

```text
discovery.surface.feed
discovery.surface.browse
discovery.surface.restricted_pool
discovery.surface.daily_batch       # planned after Phase 1
discovery.facet.activity
discovery.facet.option_group
discovery.exposure
discovery.cursor
discovery.decoration
```

Discovery owns delivery of candidates. It consumes reusable eligibility and compatibility from D8N Match, profile data from D8N Profile, and optional exclusion/decorator contributions from enabled capabilities.

#### D8N Verify

```text
verify.contact.email
verify.contact.phone
verify.identity.selfie              # unavailable
verify.identity.liveness            # unavailable
verify.identity.face_match          # unavailable
verify.identity.document            # unavailable
verify.level                        # unavailable
```

Contact ownership is implemented today even though its current code lives under `Identity`. Phase 1 records that ownership relationship; it does not move security-sensitive authentication code. Multi-level real-person verification is not to be advertised by the runtime catalog as available.

#### D8N Match

```text
match.eligibility
match.compatibility
match.ranking
match.interaction.like
match.interaction.pass
match.relationship.create
match.relationship.list
match.relationship.unmatch
match.hook                           # optional HookUs product capability
match.hook_tonight                   # optional HookUs product capability
```

Like, Pass, Match, eligibility, and deterministic compatibility are shared. Hook and Hook Tonight remain optional product concepts composed from shared engines. AI matchmaking does not belong here merely because deterministic compatibility exists.

#### D8N Chat

```text
chat.conversation
chat.message.text
chat.message.media                   # unavailable until a proven API exists
chat.read_state                      # unavailable/partial as code proves
chat.realtime                        # unavailable
chat.voice                           # unavailable
chat.video                           # unavailable
```

Only proven messaging features may be enabled. Future voice/video/realtime labels must not resolve successfully because the Rails application has Action Cable infrastructure available.

#### D8N Trust

```text
trust.block
trust.report
trust.report_evidence
trust.moderation_queue
trust.profile_suspension
trust.enforcement_audit
trust.reputation                     # unavailable
trust.fraud_detection                # unavailable
trust.trust_score                    # unavailable
```

Trust owns safety decisions and enforcement semantics. D8N Admin owns operator access and operational presentation. Current workflows that mix those responsibilities should be recorded as an extraction seam, not moved casually during Phase 1.

#### D8N Media and D8N Notify

```text
media.profile_photo.upload
media.profile_photo.attach
media.profile_photo.process
media.profile_photo.deliver
media.profile_photo.delete

notify.event
notify.inbox
notify.email
notify.sms
notify.push
```

These are shared supporting capabilities consumed by Profile, Chat, Verify, Trust, Match, and future products. Provider readiness is distinct from feature enablement.

#### D8N Pay

```text
pay.plan
pay.entitlement
pay.subscription
pay.payment
pay.marketplace
```

All remain unavailable in Phase 1. Hard-coded product allowances must be referenced through policy seams so future entitlements can replace or decorate them without rewriting engines.

#### D8N AI

```text
ai.matchmaker
ai.profile_assistant
ai.dating_assistant
ai.safety_assistant
ai.moderation_assistant
```

All remain unavailable. Deterministic compatibility and sorting must never be reported as AI.

#### D8N Insights

```text
insights.acquisition
insights.activation
insights.engagement
insights.marketplace_health
insights.retention
insights.safety
insights.revenue
```

All remain unavailable as platform products. Existing database records and operational logs may later be inputs, but do not constitute the reusable Insights capability.

#### D8N Admin

```text
admin.operator_authorization
admin.report_review
admin.enforcement
admin.verification_review            # unavailable
admin.user_operations                # unavailable/partial as code proves
admin.brand_operations               # unavailable
admin.billing_operations             # unavailable
admin.analytics                      # unavailable
```

The catalog must distinguish the current moderation subset from the future D8N Command Center.

### 3.6 Capability status is separate from brand enablement

Every catalogue entry must have an implementation state: `available`, `partial`, or `planned`. A brand contract may enable only `available` or explicitly accepted `partial` capabilities. It cannot turn `planned` into working functionality. Infrastructure readiness such as configured R2, Resend, Twilio, or push credentials is evaluated separately at deployment time.

### 3.7 D8N Discovery, Find, Discover, Explore, and Hook Tonight

There is one D8N Discovery capability namespace. “Find,” “Discover,” “Explore,” “For You,” and “People” are not separate engines by default. They are brand-facing labels or surface identifiers backed by a configured delivery type.

| Delivery type | Current engine | Meaning |
|---|---|---|
| `feed` | `Matching::Discovery` | ranked/paginated candidate feed |
| `browse` | `Matching::Find::Search` | filtered browse with exposure accounting |
| `restricted_pool` | Hook Tonight composition over shared Discovery | candidates from an explicitly enrolled/eligible pool |
| `daily_batch` | not implemented | stable persisted allocation with rollover; next platform ticket |

A surface definition should contain a surface key, delivery type, eligibility policy, ranking/compatibility strategy, accepted facets, exclusion contributors, response decorators, exposure/allocation policy, and stable not-configured error.

```text
HookUs
  discovery.for_you
    delivery: feed
    strategy: hookus
    facets: activity, option_group(vibes)
    exclusions: base + live_hook
    decorations: hook_viewer_state where requested by this surface

  discovery.new_here
    delivery: feed
    strategy: hookus/new_here

  discovery.hook_tonight
    delivery: restricted_pool
    capability dependency: match.hook_tonight
    pool/guard: HookUs availability policy

DateZA
  discovery.find
    delivery: browse
    implementation: Matching::Find::Search
    policy: Matching::Find::Policies::Dateza
    exposure limit: 10 per Johannesburg day

  discovery.curated_daily
    delivery: daily_batch
    status: planned and disabled in Phase 1
```

“Online Now” can be a configured activity facet or preset over a feed. “420 Friendly” can be HookUs presentation over its configured `vibes` option-group facet. Neither requires another universal Discovery engine.

Hook Tonight is a genuine HookUs product concept, but its candidate delivery is composed through D8N Discovery and its interactions through D8N Match. Product-specific semantics do not justify duplicated candidate, profile, safety, or messaging infrastructure.

### 3.8 How a brand accesses a feature

```text
request host/header
  -> Brands::Resolver selects Brand
  -> brand-bound session selects membership/profile
  -> D8n::Platform::BrandRegistry resolves contract
  -> D8n::Platform::CapabilityAccess checks capability and surface
  -> contract resolves policy/strategy/contributors
  -> existing shared domain engine executes
  -> generic serializer builds the base response
  -> configured surface decorators add optional fields
```

Brands do not gain features because a route happens to exist. A global route is usable only when the resolved brand contract enables its capability or surface. The frontend remains free to label `discovery.find` as “Find,” “Explore,” or another product name; presentation never changes backend ownership.

### 3.9 Boundary rule for new work

Before adding a brand feature, its ticket must answer which D8N namespace owns it, whether its feature key already exists, whether it is a surface over an existing engine, whether policy/strategy/facet/exclusion/decorator/allocation composition can express it, and whether genuinely new platform capability is required.

The A/B/C/D/E classification remains mandatory. A brand-named production engine requires written evidence that composition cannot express the product semantics.

## 4. Current architecture to preserve

Phase 1 must preserve the healthy shared architecture already confirmed by the audit:

- global `User` identity;
- global identity identifiers and credentials;
- `BrandMembership` as brand participation;
- `Profile` as brand-specific dating presence;
- host-based `BrandDomain` resolution;
- brand-bound bearer sessions;
- the shared profile/onboarding engine;
- controlled profile options and prompts;
- shared profile preferences, location, and photos;
- profile completion and publication;
- shared Like, Pass, and Match mechanics;
- shared conversations and messages;
- shared blocking and reporting;
- shared notification delivery infrastructure;
- brand-scoped admin moderation;
- shared media storage and processing; and
- brand-level account closure and suspension.

No separate HookUs, DateZA, or Date9ja version of these capabilities will be introduced.

## 5. Proposed brand capability contract

### 5.1 Shape

Introduce the small typed D8N Platform composition namespace defined above, returning one contract per production brand, conceptually:

```ruby
D8n::Platform::BrandRegistry.fetch(brand:)
```

The returned contract should expose focused sections rather than become one god object:

```text
BrandContract
├── capabilities             # stable D8N feature keys and status
├── profile                  # catalogue and field policy references
├── discovery_surfaces       # delivery composition
├── interaction_policy       # shared eligibility inputs
├── hooks                    # optional HookUs product policy
├── messaging                # enabled Chat subset
├── media                    # policy and readiness reference
└── notifications            # events/channels and readiness reference
```

Potential file organization:

```text
domains/d8n/platform/
├── catalog.rb
├── capability_key.rb
├── brand_contract.rb
├── brand_registry.rb
├── capability_access.rb
├── discovery_surface.rb
├── capabilities/
│   ├── id.rb
│   ├── profile.rb
│   ├── discovery.rb
│   ├── verify.rb
│   ├── match.rb
│   ├── chat.rb
│   ├── trust.rb
│   ├── media.rb
│   ├── notify.rb
│   ├── pay.rb
│   ├── ai.rb
│   ├── insights.rb
│   └── admin.rb
└── brands/
    ├── hookus.rb
    └── dateza.rb
```

This organization is intentional: brand resolution and installation remain in `Brands`, while D8N-wide capability composition belongs to `D8n::Platform`. Exact leaf names may be adjusted only if Zeitwerk or an established repository convention requires it; the ownership boundary must remain.

### 5.2 Responsibilities

The contract will:

- bind to a real `Brand` record;
- expose stable namespaced capability keys rather than free-form booleans;
- answer whether a capability is enabled;
- resolve configured capability surfaces;
- reference the brand's profile catalogue;
- reference existing matching, Find, compatibility, interaction, media, and notification policies;
- declare stable not-configured error codes;
- deny unknown or unconfigured brands by default;
- expose metadata needed by brand contract tests; and
- validate persisted brand configuration where appropriate.

The catalog answers what D8N implements independent of any brand. The brand contract answers which implemented capabilities that brand consumes. These must remain separate questions.

### 5.3 What remains persisted

The contract will not duplicate configuration already owned by the database.

Persisted configuration remains authoritative for:

- `Brand#auth_methods`;
- profile requirements;
- enabled identity/profile/preference fields;
- installed option groups and options;
- installed prompts;
- brand domains; and
- membership/profile lifecycle data.

The Ruby contract references and validates this data. It does not copy all field lists into another structure.

### 5.4 Specialized policies remain specialized

The contract references specialized domain objects instead of absorbing them.

Examples:

- DateZA Find continues to own its daily limit, timezone, and ranking policy.
- Hook policy continues to own Hook expiry and allowance.
- compatibility strategies continue to own scoring.
- media policy continues to own initial photo visibility.
- notification policy continues to own event-to-notification choices.

The brand contract is an authoritative composition map, not a replacement for domain logic.

## 6. Initial brand contracts

The initial contracts must describe current production behavior, not future intent.

### 6.1 HookUs

```text
D8N ID
  id.registration: enabled
  id.authentication.email_password: enabled
  id.authentication.phone_password: enabled
  id.session: enabled
  id.password_recovery: enabled

D8N Profile
  profile.onboarding: enabled
  profile.publication: enabled
  catalogue: Profiles::HookusProfileCatalog

D8N Discovery
  discovery.for_you: feed, enabled
  discovery.new_here: feed, enabled
  activity facet: enabled
  option_group(vibes) facet: enabled
  live Hook exclusion contributor: enabled
  Hook response decorator: enabled only on configured surfaces

D8N Verify
  verify.contact.email: enabled where configured by auth method
  verify.contact.phone: enabled where configured by auth method
  identity verification levels: unavailable

D8N Match
  match.interaction.like: enabled
  match.interaction.pass: enabled
  match.relationship: enabled
  match.hook: enabled
  match.hook_tonight: enabled
  interaction eligibility policy: HookUs

D8N Chat
  chat.conversation: enabled
  chat.message.text: enabled
  realtime/voice/video: unavailable

D8N Trust
  trust.block: enabled
  trust.report: enabled

D8N Media
  media.profile_photo: enabled
  initial visibility: immediate

D8N Notify
  configured current event/channel subset: enabled

D8N Pay / AI / Insights
  unavailable
```

Hook Tonight remains a specialized HookUs capability that uses a configured HookUs Discovery surface plus its current reciprocal availability guard and candidate-pool restriction.

### 6.2 DateZA

```text
D8N ID
  id.registration: enabled
  id.authentication.email_password: enabled
  id.authentication.phone_password: enabled
  id.session: enabled
  id.password_recovery: enabled

D8N Profile
  profile.onboarding: enabled
  profile.publication: enabled
  catalogue: Profiles::DatezaProfileCatalog

D8N Discovery
  discovery.find: browse, enabled
  policy: Matching::Find::Policies::Dateza
  daily limit: 10
  timezone: Africa/Johannesburg
  compatibility: Matching::Strategies::DatezaV1
  discovery.curated_daily: planned and disabled
  /api/v1/discovery feed route: matching_not_configured

D8N Verify
  verify.contact.email: enabled where configured by auth method
  verify.contact.phone: enabled where configured by auth method
  identity verification levels: unavailable

D8N Match
  match.interaction.like: enabled
  match.interaction.pass: enabled
  match.relationship: enabled
  verified login identifier required
  match.hook: disabled
  match.hook_tonight: disabled

D8N Chat
  chat.conversation: enabled
  chat.message.text: enabled
  realtime/voice/video: unavailable

D8N Trust
  trust.block: enabled
  trust.report: enabled

D8N Media
  media.profile_photo: enabled
  initial visibility: moderate_first

D8N Notify
  membership_registered: DateZA welcome

D8N Pay / AI / Insights
  unavailable
```

DateZA curated daily Discovery is catalogued as planned but remains disabled in its brand contract in Phase 1. A planned catalog entry must not be callable or appear production-ready.

### 6.3 Date9ja and unknown brands

Date9ja remains non-production in the D8N repository except for its existing strategy contract proof. It must not be accidentally marked production-ready.

Unknown brands receive a deny-by-default contract or a typed unconfigured error. They must never receive HookUs or DateZA defaults.

## 7. Make the contract authoritative

Existing enablement maps must delegate to the contract or be removed once their callers are migrated.

Relevant current entry points include:

- `Matching::StrategyRegistry`;
- `Matching::Find::PolicyRegistry`;
- `Hooks::CapabilityPolicy`;
- `Identity::InteractionAccess`;
- `Media::PhotoPolicy`;
- `Notifications::Policy`;
- `Notifications::Types`; and
- mailer/template mappings where brand enablement is involved.

There must not be two competing sources of truth.

Specialized registries may remain as internal strategy lookup helpers, but whether a brand can consume a capability or surface must come from the brand contract.

## 8. Generic capability gate

### 8.1 Proposed mechanism

Introduce one reusable authorization boundary, conceptually:

```ruby
D8n::Platform::CapabilityAccess.authorize!(
  brand:,
  capability: "discovery.surface",
  surface: nil
)
```

The gate will:

- fail closed for nil brands;
- fail closed for unknown brands;
- distinguish capability availability from surface availability;
- preserve existing consumer-facing error codes;
- run after authentication where the current controller already authenticates;
- avoid generic `NoMethodError` or 500 responses; and
- support global route presence.

### 8.2 Error compatibility

Expected preserved responses include:

```text
DateZA /discovery       -> matching_not_configured
DateZA /hook            -> hook_not_configured
DateZA /hook_tonight    -> hook_tonight_not_configured
unsupported /find       -> find_not_configured
```

Capability error mapping belongs to the capability contract or its access boundary, not repeated controller case statements.

### 8.3 Routes to gate

Initial optional product surfaces should include:

- Discovery;
- Find;
- Like/Pass interaction capability;
- Matches where policy-controlled;
- Hooks;
- Hook Tonight; and
- Messaging where policy-controlled.

Foundational Identity/Profile/account routes can remain available when the brand contract enables those platform foundations.

### 8.4 Security ordering

Authentication should continue to run before optional capability authorization on authenticated routes. This preserves current behavior and avoids exposing unnecessary product configuration to unauthenticated callers.

`HookTonightController#destroy` must retain its cleanup-safe exception so unsupported or legacy state can always be removed.

## 9. Consolidate discoverable-viewer validation

### 9.1 Current problem

Viewer validation is duplicated between:

- `Matching::Discovery#current_viewer!`; and
- `Matching::ProfileParticipant.discoverable!`.

The duplicated predicates can drift as profile lifecycle rules evolve.

### 9.2 Target

`Matching::ProfileParticipant.discoverable!` becomes the one authoritative discoverable-viewer validator.

`Matching::Discovery` delegates to it and translates the existing `Matching::InteractionError` into its existing `ViewerIneligible` error so the public API remains stable.

### 9.3 Semantics to preserve

- active brand;
- active global user;
- active brand membership;
- kept records;
- active, published, visible profile;
- adult birthdate;
- gender present;
- kept preference record;
- minimum age present;
- maximum age present;
- at least one interested-in value; and
- current lifecycle restrictions.

`discoverable!` must remain distinct from `match_member!`. A member viewing an existing Match or conversation does not necessarily need to satisfy the same publication requirements as someone entering Discovery.

### 9.4 Regression tests

Cover:

- inactive, suspended, and closed users;
- inactive/suspended/left memberships;
- draft profiles;
- hidden profiles;
- suspended profiles;
- missing birthdate;
- underage profiles;
- missing gender;
- missing preference fields;
- valid published viewers; and
- correct public error translation in Discovery and Find.

## 10. Normalize eligibility policy inputs

### 10.1 Current problem

Location freshness and related eligibility context currently come from different places:

- Discovery strategy;
- Find policy;
- Like/Pass interaction strategy;
- Hook Discovery strategy; and
- DateZA compatibility's direct dependency on the DateZA Find policy.

This creates an accidental dependency from compatibility into a product surface namespace.

### 10.2 Proposed seam

Introduce a small immutable eligibility-policy value, conceptually:

```ruby
Matching::EligibilityPolicy.new(
  location_max_age: 24.hours
)
```

Discovery surfaces, Find policies, interaction policy, Hooks, and compatibility receive this explicit value.

### 10.3 Boundaries

This policy contains only genuinely shared eligibility inputs.

It must not absorb:

- ranking weights;
- daily Find allowance;
- Hook allowance;
- Hook expiry;
- compatibility weights;
- notification policy; or
- media visibility.

### 10.4 DateZA compatibility

`Matching::Strategies::DatezaV1` must stop importing `Matching::Find::Policies::Dateza.location_max_age`.

It should receive DateZA's configured interaction/eligibility policy from the capability contract or from an explicit caller argument.

Compatibility scoring itself remains unchanged.

## 11. Split universal and capability-specific exclusions

### 11.1 Universal exclusions

`Matching::ExclusionsScope` should retain only exclusions that apply to every configured D8N candidate surface:

- existing outgoing Like;
- existing outgoing Pass; and
- active Match in either canonical direction.

Blocking and lifecycle continue to be enforced by `Matching::VisibilityScope` and `Trust::BlockPolicy` where they already belong.

### 11.2 Hook exclusion contributor

Live Hook exclusion moves to a focused Hooks-domain callable, conceptually:

```ruby
Hooks::DiscoveryExclusion.call(scope:, viewer:)
```

The HookUs Discovery surfaces declare that contributor in their capability configuration.

Composition becomes:

```text
base exclusions
+ exclusions contributed by the enabled surface capabilities
```

This should be a short callable list, not an event bus, plugin loader, or dependency-injection framework.

### 11.3 Behavior to preserve

For HookUs:

- a live outgoing Hook excludes the recipient;
- a live incoming Hook excludes the sender;
- accepted Hooks become Matches and remain excluded through Match rules;
- expired or declined Hooks follow current terminal behavior; and
- Hook creation continues to prevent duplicate/invalid interactions.

For DateZA and other brands with Hooks disabled, the generic candidate query must not reference Hook records.

## 12. Configured Discovery facets

### 12.1 Current problem

`Matching::FacetFilter` hardcodes:

- the HookUs `vibes` option-group key;
- the `vibe` parameter; and
- the product concept behind 420 Friendly.

Online activity is reusable, but vibes are not universal.

### 12.2 Surface resolution

Discovery will resolve the active configured surface before parsing facet values.

The surface declares accepted facet definitions.

### 12.3 Minimal facet types

Two small reusable facet types should cover current behavior:

1. activity facet, for online/recent-session filtering;
2. configured option-group facet, parameterized by query parameter and option-group key.

Conceptually, HookUs configures:

```text
parameter: vibe
kind: option_group
option_group: vibes
visibility: public_profile
```

The generic filter engine validates the supplied code against the current brand's active public group/options. It does not know the meaning of `vibes` or `420_friendly`.

### 12.4 API compatibility

HookUs retains its existing query API:

```text
?online=true
?vibe=420_friendly
```

The controller should not list HookUs-specific parameters directly. It can pass query parameters to the resolved surface parser, which selects only configured facet keys and rejects invalid configured values.

### 12.5 Cursor compatibility

Preserve:

- existing strategy keys;
- cursor brand binding;
- mode binding;
- facet binding; and
- current HookUs facet fingerprint format where possible.

The preferred implementation retains existing cursor validity across deployment. If exact compatibility proves impossible, that must be surfaced before implementation proceeds because invalidating in-flight cursors is an API behavior change.

### 12.6 Explicit non-goal

Do not add new DateZA facets, Verified Only, Visiting, age, distance, or other Discovery filters in this ticket.

## 13. Surface-specific response decoration

### 13.1 Goal

Generic profile and candidate serializers should emit generic D8N data. Optional product capability state should be added only when the current brand and surface enable it.

### 13.2 Proposed seam

Use a small list of bulk decorators configured on a surface, conceptually:

```ruby
surface.decorators.each do |decorator|
  payloads = decorator.call(viewer:, profiles:, payloads:)
end
```

The exact interface may return a profile-ID-to-fields map so candidate payloads can merge values without N+1 queries.

### 13.3 Generic status fields

`Profiles::StatusFields` should retain reusable status only:

- verified contact fact;
- online;
- active today;
- new here;
- last active time; and
- viewer-relative distance.

It should receive explicit location freshness from the resolved surface or interaction policy. It must not import `Matching::Strategies::Hookus::LOCATION_MAX_AGE`.

### 13.4 Hook decoration

Move Hook-specific fields into the Hooks domain:

- `hook_state`;
- `hook_tonight_active`.

HookUs enables the relevant decorators for:

- its Discovery surfaces;
- Hook Tonight Discovery; and
- HookUs public profile detail where the frontend needs the Hook action state.

DateZA does not enable them.

### 13.5 Expected response correction

After Phase 1:

- HookUs retains Hook state on configured surfaces;
- DateZA profile detail no longer receives `hook_state`;
- DateZA candidate/profile responses no longer receive `hook_tonight_active`; and
- generic serializers do not know about future optional D8N capabilities.

This is an intentional API response-shape correction and must be represented in OpenAPI and request/serializer tests.

### 13.6 Performance

Decorators must remain bulk operations. A page of profiles must not perform one Hook, Match, Like, session, or Hook Tonight query per profile.

Where query-count assertions already exist, they should be preserved or extended.

## 14. Authoritative profile field configuration

### 14.1 Current problem

`Profiles::Configuration` advertises brand-enabled scalar fields, but `Api::V1::ProfileController#profile_params` accepts the broad shared scalar set for every brand.

`Profiles::OwnerSerializer` and `Profiles::PublicSerializer` also emit the broad shared scalar shape regardless of enabled fields.

This makes configuration advisory rather than authoritative.

### 14.2 Shared field policy

Add a focused field policy derived from:

```ruby
brand.profile_completion_requirements
```

It should expose:

- enabled identity fields;
- enabled profile scalar fields;
- enabled preference fields;
- stable universal envelope fields; and
- public versus owner field availability.

This policy must use the same source as `Profiles::Configuration` so frontend configuration and backend enforcement cannot disagree.

### 14.3 Writes

Before `Profiles::CurrentProfile.upsert!`, inspect submitted known scalar fields.

If a submitted platform field is supported globally but disabled for the current brand, reject the request rather than silently persisting or ignoring it.

Proposed response:

```json
{
  "error": "invalid_profile_fields",
  "details": {
    "fields": ["body_type"]
  }
}
```

Status:

```text
422 Unprocessable Entity
```

The exact stable error shape will be aligned with existing API error conventions and documented in OpenAPI.

Unknown arbitrary parameters may continue to follow normal Rails strong-parameter behavior. The required correction is that known, brand-disabled fields cannot be persisted.

### 14.4 Universal envelope and operational fields

Some inputs may be platform operational controls rather than catalogue scalar capabilities. These need an explicit reviewed allowlist.

For example, current `visibility` handling must be preserved unless the publication API is deliberately made the only visibility writer in a separate change. Phase 1 should not silently remove existing behavior.

### 14.5 HookUs field behavior

HookUs currently defaults to the broad profile-field catalogue because its requirements do not contain an explicit `enabled_profile_fields` list.

Phase 1 should preserve what HookUs currently advertises. It should not invent a narrower HookUs field set without product approval.

Cross-brand negative testing can prove that a field enabled and accepted for HookUs is rejected and omitted for DateZA when DateZA does not enable it.

### 14.6 Owner serialization

The owner response retains a stable envelope:

- profile public ID;
- brand identity;
- status;
- visibility;
- completion;
- options;
- prompts; and
- other universal owner metadata.

Configured scalar values are included only when enabled for the brand.

Private global identity fields remain owner-only and appear only when enabled by the current brand's onboarding contract.

### 14.7 Public serialization

Public/detail/candidate serializers include a scalar field only if:

1. the brand enables it; and
2. its platform visibility permits the current audience.

Examples:

- age appears only when birthdate is enabled;
- approximate location is composed from enabled city/country fields;
- exact coordinates never appear;
- `company_name` remains private even if enabled;
- owner-only option groups remain hidden;
- matches-only groups remain gated by an active Match; and
- photos retain current deliverability requirements.

### 14.8 OpenAPI implications

Brand-dependent scalar properties must not be falsely represented as universally required response properties.

Update:

- profile update request schema;
- invalid-profile-fields error response;
- owner profile schema;
- public/detail/candidate profile schemas; and
- API integration guidance explaining brand-configured optional fields.

Run `test/contracts/openapi_contract_test.rb` after every API contract adjustment.

## 15. Preserve DateZA Find

DateZA Find is structurally reusable and will not be redesigned in Phase 1.

The capability contract will reference its existing policy cleanly, and the policy will expose or receive the normalized eligibility policy.

The following must remain unchanged:

- `GET /api/v1/find`;
- ten-profile daily allowance;
- Johannesburg calendar-day boundary;
- brand-membership locking;
- `FindProfileExposure` persistence;
- already-exposed candidate behavior;
- age filter;
- distance filter;
- relationship-intent filter;
- signed cursor payload and integrity;
- newest-first ranking;
- allowance response shape;
- DateZA v1 compatibility response; and
- exhausted-feed behavior.

There will be no namespace rename, route rename, or separate browse engine.

## 16. DateZA Discovery remains unconfigured

Phase 1 must preserve:

```text
GET /api/v1/discovery on DateZA
-> 404
-> { "error": "matching_not_configured" }
```

Out of scope:

- stable ten-profile DateZA daily batch;
- persisted curated batch rows;
- batch rollover;
- DateZA curated ranking registration;
- DateZA Discovery frontend enablement; and
- treating Find as curated Discovery.

The next ticket will build one reusable stable daily-selection capability and configure DateZA on top of it.

## 17. Brand capability contract tests

### 17.1 Test architecture

Add a reusable contract assertion helper plus small HookUs and DateZA declarations.

Do not clone full controller suites for each brand.

### 17.2 Contract coverage

For every installed production brand, validate:

- host-to-brand resolution;
- advertised authentication methods;
- profile catalogue class;
- catalogue installation/configuration availability;
- enabled identity fields;
- enabled profile fields;
- enabled preference fields;
- configured Discovery surfaces;
- configured Find surfaces;
- interaction eligibility policy;
- interaction verification requirement;
- Hook enablement;
- Hook Tonight enablement;
- messaging availability;
- media initial visibility policy;
- notification event configuration;
- stable not-configured errors; and
- optional response-field isolation.

### 17.3 Unsupported brand contract

An unconfigured test brand must prove:

- no HookUs or DateZA policy is inherited;
- Discovery fails closed;
- Find fails closed;
- Hooks fail closed;
- optional decorators do not run; and
- missing configuration produces stable API errors rather than exceptions.

### 17.4 Infrastructure readiness

Contract tests may inspect readiness metadata and configured service names without making provider calls.

They must not contact:

- Cloudflare R2;
- Resend;
- Twilio;
- APNs/FCM; or
- any production service.

## 18. Implementation slices

The ticket should be implemented in independently green slices.

### Slice 1 — Contract types and brand definitions

- add `D8n::Platform` catalog, key, contract, surface, registry, and access value objects;
- add one small definition module under `D8n::Platform::Capabilities` for every canonical platform namespace;
- register the implemented/partial/planned feature catalogue under canonical D8N namespaces;
- add HookUs and DateZA definitions;
- add unknown-brand denial;
- validate capability keys and reject brand-slugged or unknown keys;
- add contract unit tests;
- make no runtime behavior change.

Completion gate:

- one primary location accurately describes current HookUs and DateZA capability composition;
- contract tests pass.

### Slice 2 — Existing policies delegate to the contract

- make matching strategy resolution consult the contract;
- make Find resolution consult the contract;
- make Hook availability consult the contract;
- make interaction verification consult the contract;
- make media initial policy consult the contract;
- reference notification configuration;
- remove or delegate duplicate brand maps.

Completion gate:

- existing controller/domain tests pass without response changes;
- there is no competing enablement source.

### Slice 3 — Generic capability gate

- add reusable capability access service/error;
- integrate Discovery, Find, Hooks, Hook Tonight, matching interactions, and messaging where appropriate;
- preserve authentication ordering;
- preserve existing error codes;
- preserve Hook Tonight cleanup behavior.

Completion gate:

- HookUs enabled routes work;
- DateZA Hooks remain denied;
- DateZA Discovery remains denied;
- unconfigured brands fail closed.

### Slice 4 — Viewer eligibility and policy normalization

- make `ProfileParticipant.discoverable!` authoritative;
- remove duplicated Discovery viewer predicate;
- introduce normalized eligibility-policy value;
- remove DateZA compatibility's Find namespace dependency;
- route Like/Pass/Hook/Discovery/Find policy inputs explicitly.

Completion gate:

- eligibility regression tests pass;
- compatibility scores are unchanged;
- Discovery and Find viewer error behavior is unchanged.

### Slice 5 — Exclusion composition

- remove Hook queries from universal exclusions;
- add Hook-specific exclusion contributor;
- configure it only for HookUs surfaces;
- test Hook behavior and absence on DateZA/unconfigured brands.

Completion gate:

- HookUs candidate results remain correct;
- generic exclusions no longer reference Hook records.

### Slice 6 — Facets and response decorators

- resolve configured Discovery surface;
- make facets definition-driven;
- move vibes configuration to HookUs;
- keep online reusable;
- move Hook/Hook Tonight status out of generic status code;
- add HookUs surface decorators;
- pass explicit location policy to generic status;
- preserve cursor fingerprints and query efficiency.

Completion gate:

- HookUs For You, New Here, vibe, online, and Hook Tonight behavior pass;
- DateZA receives no Hook fields;
- generic Discovery contains no HookUs option-group knowledge.

### Slice 7 — Profile field authority

- add shared field policy;
- reject known disabled scalar writes;
- make serializers conditional on enabled fields;
- add HookUs/DateZA negative leakage tests;
- update OpenAPI and API guide.

Completion gate:

- enabled writes work;
- disabled writes return stable 422 response;
- disabled fields are absent from owner/public/detail output;
- options/prompts/preferences/publication behavior is unchanged.

### Slice 8 — Documentation and final verification

- document capability ownership and surfaces;
- preserve the historical audit unchanged;
- run focused suites;
- run OpenAPI contract tests;
- run the complete Rails suite;
- run Zeitwerk, RuboCop, Brakeman, and `git diff --check`;
- report exact results.

## 19. Detailed test plan

### 19.1 Brand capability contract

Cover:

- HookUs contract;
- DateZA contract;
- Date9ja/unconfigured behavior;
- registry lookup;
- nil/disabled brand behavior;
- contract/persisted-auth consistency;
- contract/profile-catalogue consistency; and
- stable error codes.

### 19.2 Discovery

Cover:

- HookUs For You;
- HookUs New Here;
- online facet;
- vibe facet;
- invalid facet values;
- facet-bound cursors;
- mode-bound cursors;
- Hook exclusion in both directions;
- blocks;
- reciprocal preferences;
- distance policy;
- lifecycle filtering;
- HookUs response decorations;
- unsupported DateZA Discovery; and
- unsupported unknown-brand Discovery.

### 19.3 Response leakage

Cover:

- DateZA profile detail has no `hook_state`;
- DateZA profile/candidate status has no `hook_tonight_active`;
- HookUs configured Discovery retains `hook_state`;
- HookUs configured profile detail retains its required Hook state;
- future/unconfigured brands receive no optional decorators; and
- decorator queries remain bulk.

### 19.4 Profile configuration

Cover:

- enabled DateZA scalar write accepted;
- disabled DateZA scalar write rejected;
- a currently advertised HookUs scalar field remains accepted;
- disabled scalar field absent from DateZA owner serialization;
- disabled scalar field absent from DateZA public/detail serialization;
- identity fields remain owner-only;
- age/birthdate behavior follows field policy;
- company remains private;
- options remain brand-scoped;
- prompts remain brand-scoped;
- preferences remain unchanged;
- completion remains unchanged; and
- publication remains unchanged.

### 19.5 Eligibility

Cover:

- shared discoverable-viewer service;
- user lifecycle;
- membership lifecycle;
- profile lifecycle/publication;
- adult gate;
- required preference state;
- reciprocal gender;
- reciprocal ages;
- reciprocal distance;
- blocks in both directions;
- Discovery regression; and
- Find regression.

### 19.6 Find

Cover:

- ten-profile daily allowance;
- Johannesburg reset boundary;
- exposure ledger;
- concurrent allocation;
- already-exposed candidates;
- filters;
- cursor integrity;
- exhausted allowance;
- compatibility payload; and
- DateZA verification behavior around subsequent interactions.

### 19.7 Hooks

Cover:

- Hook enabled on HookUs;
- Hook denied on DateZA;
- Hook Tonight enabled on HookUs;
- Hook Tonight denied on DateZA;
- cleanup-safe deactivate behavior;
- Hook send;
- Hook inbox;
- Hook decline;
- Hook reply/acceptance;
- Match/conversation promotion;
- Hook expiry;
- Hook allowance; and
- Hook Discovery exclusion.

### 19.8 Shared platform regressions

Run focused smoke coverage for:

- sessions and cross-brand replay;
- Likes/Passes/Matches;
- conversations/messages;
- profile photos/media policy;
- blocking/reporting;
- admin suspension;
- notifications; and
- account closure.

## 20. Required verification commands

Exact commands may use the repository's required Ruby/Bundler wrapper, but the logical checks are:

```sh
RAILS_ENV=test bin/rails test <focused brand/profile/matching files>
RAILS_ENV=test bin/rails test test/contracts/openapi_contract_test.rb
RAILS_ENV=test bin/rails test
bin/rails zeitwerk:check
RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bin/rubocop --no-server
bin/brakeman --no-pager
git diff --check
```

The final report must include:

- exact commands run;
- run/assertion counts;
- failures/errors/skips;
- checks that could not run and why; and
- whether the complete suite was actually executed.

No claim of full-suite success may be made unless the full suite command completes successfully.

## 21. Documentation plan

The audit file remains unchanged as historical evidence.

Add one concise architecture decision describing:

> Capabilities belong to D8N; brands compose capability surfaces through an authoritative contract.

Add or update a focused architecture document covering:

- D8N capability ownership;
- the canonical D8N namespace and feature catalogue;
- public pillar versus Ruby implementation domain versus capability key;
- brand capability composition;
- surface identity versus frontend naming;
- Find/Discover/Explore as surface or presentation names over D8N Discovery delivery types;
- deny-by-default route behavior;
- specialized policy and strategy references;
- optional exclusion contributors;
- configured facets;
- optional response decorators;
- authoritative profile fields; and
- the new-brand registration checklist.

Update existing matching/profile architecture documents and API integration guidance only where runtime contracts change.

Do not rewrite the audit to make the earlier architecture appear cleaner.

## 22. Principal risks and controls

### Risk: two sources of truth

If old registries and the new contract both retain independent mappings, behavior will drift again.

Control:

- migrate callers in slices;
- make old entry points delegate;
- remove duplicate maps when safe;
- add consistency tests.

### Risk: frontend response changes

Removing Hook fields and disabled scalar fields from DateZA responses changes JSON shape.

Control:

- treat it as intentional capability isolation;
- update OpenAPI and integration docs;
- add explicit response-shape tests;
- list every removed field in the final report.

### Risk: cursor invalidation

Changing facet representation can invalidate existing HookUs cursors.

Control:

- preserve strategy keys;
- preserve current filter fingerprint format;
- preserve signed cursor payload semantics;
- add legacy/current cursor regression tests.

### Risk: query-count regression

Composable decorators/exclusions could create N+1 queries.

Control:

- require bulk callable interfaces;
- preload as today;
- preserve query-count tests where present;
- inspect generated SQL for Discovery and Find.

### Risk: capability enumeration

Returning not-configured errors before authentication may disclose product configuration.

Control:

- preserve authentication-before-capability ordering on authenticated routes.

### Risk: nil or unknown brands

New code could call `brand.slug` before proving a brand exists.

Control:

- registry handles nil/unconfigured inputs explicitly;
- capability gate fails closed;
- add no-brand and unknown-brand request tests.

### Risk: Hook Tonight cleanup regression

Strict gating could prevent corrective state removal.

Control:

- preserve the current destroy exception;
- add regression coverage.

### Risk: over-restricting profile writes

Field enforcement could accidentally reject operational fields or fields currently advertised by HookUs.

Control:

- derive policy from the configuration clients receive;
- maintain an explicit small universal-envelope allowlist;
- preserve HookUs's current advertised field set;
- test enabled and disabled writes on both brands.

### Risk: circular domain dependencies

A Brands contract referencing domain policies could lead those same domains to call back into Brands unpredictably.

Control:

- Brands resolves composition;
- capability engines receive resolved policy/surface values;
- strategies do not reach into unrelated product namespaces;
- keep typed values small and immutable.

### Risk: accidental scope expansion

The capability contract could become an excuse to implement missing platform pillars.

Control:

- represent missing capabilities as disabled/unavailable only;
- do not implement them in Phase 1.

## 23. Explicitly out of scope

Phase 1 does not implement:

- DateZA stable ten-profile daily Discovery;
- daily Discovery batch records;
- DateZA curated ranking registration;
- D8N Pay;
- plans or subscriptions;
- entitlements;
- payment providers or webhooks;
- RealMe;
- selfie, liveness, face matching, ID, or video verification;
- trust/reputation scores;
- fraud detection engines;
- AI matchmaker;
- LLM or embedding infrastructure;
- realtime chat;
- read receipts;
- chat media;
- voice or video;
- join/rejoin membership;
- legal erasure/export; or
- photo moderation workflow.

Disabled contract entries may describe that these capabilities do not exist, but no placeholder implementation should be added.

## 24. Acceptance criteria

Phase 1 is complete only when all of the following are true:

1. `D8n::Platform` is the one explicit namespace for the capability catalog, brand composition, surface definitions, and capability access.
2. The catalogue records the nine headline pillars plus Profile, Discovery, Media, and Notify without claiming planned features are implemented.
3. Every gated product route maps to a stable D8N capability key and, where applicable, a configured surface.
4. Capability keys contain no brand slugs and frontend labels do not determine engine ownership.
5. One primary location accurately answers what HookUs and DateZA enable.
6. The contract references existing policies/strategies instead of copying their logic.
7. Unknown brands and unsupported surfaces fail closed.
8. Existing stable not-configured errors are preserved.
9. Generic Discovery contains no HookUs `vibes` knowledge.
10. Generic exclusions contain no direct `Hook` query.
11. Generic status/profile code contains no direct `HookTonightState` dependency.
12. Generic status code no longer imports a HookUs location constant.
13. HookUs For You and New Here behave unchanged.
14. HookUs online and vibe facets behave unchanged.
15. HookUs Hook exclusion behaves unchanged.
16. HookUs Hook state is present where its configured surfaces require it.
17. DateZA receives no Hook or Hook Tonight response fields.
18. One discoverable-viewer validator is authoritative.
19. Discoverable and match-member semantics remain distinct.
20. DateZA compatibility no longer imports Find policy for generic eligibility data.
21. Known disabled scalar profile writes are rejected.
22. Enabled scalar profile writes remain accepted.
23. Disabled scalar profile fields are omitted from owner/public/detail output.
24. Option, prompt, preference, completion, and publication behavior is unchanged.
25. DateZA Find behavior and API contract are unchanged and Find is represented as a DateZA surface over D8N Discovery's existing browse delivery.
26. Hook Tonight is represented as an optional HookUs capability composed with a D8N Discovery restricted-pool surface.
27. DateZA `/api/v1/discovery` remains intentionally unavailable.
28. No curated daily-selection implementation is introduced.
29. Generic capability tests and compact brand contract tests pass.
30. OpenAPI reflects intentional request/response/error changes.
31. Zeitwerk, RuboCop, Brakeman, and `git diff --check` pass or any inability is reported precisely.
32. The complete test-suite result is reported accurately.

## 25. Final implementation report format

After implementation, return:

### 1. Architecture before

Summarize fragmented enablement, HookUs leakage, duplicated viewer validation, inconsistent policy sourcing, and advisory profile configuration.

### 2. Brand capability contract

Explain the authoritative composition mechanism and show HookUs/DateZA summaries.

### 3. Discovery cleanup

Explain how HookUs facets, exclusions, and response state were removed from generic code and composed back into HookUs.

### 4. Eligibility and policy cleanup

Explain the shared viewer validator and normalized eligibility-policy input.

### 5. Profile enforcement

Explain authoritative writes and brand-aware serialization, including intentional API field changes.

### 6. Surface decoration

Explain the optional bulk decorator seam and its configured surfaces.

### 7. Find status

Confirm DateZA Find allowance, exposure, cursor, filters, and compatibility remain unchanged.

### 8. DateZA Discovery status

Confirm it remains intentionally unconfigured.

### 9. Regression results

List exact commands, tests, assertions, failures, errors, skips, lint, Zeitwerk, Brakeman, OpenAPI, and diff-check results.

### 10. Remaining platform gaps

List only genuine missing platform capabilities, not configuration work.

### 11. Next recommended ticket

The next ticket is:

> **Build reusable stable daily-selection capability and configure DateZA curated Discovery on top of it.**

Do not implement that ticket as part of Phase 1.

## 26. Execution rule

Implementation should proceed slice by slice, keeping the suite green after each slice. No commit, push, or deployment is authorized by this plan.

Before any implementation begins, confirm the working tree and use the current audit as evidence. Existing unrelated user changes must be preserved.
