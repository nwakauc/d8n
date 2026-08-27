# D8N Platform Architecture & Reuse Audit

**Audit date:** 2026-08-24  
**Repository revision inspected:** `917de86` (`dev`)  
**Scope:** Current D8N Rails backend production code, routes, schema, configuration, jobs, and tests  
**Method:** Read-only runtime-path tracing. Product plans, ADRs, comments, and filenames were treated as intent only unless production code or tests confirmed them.

## 1. Executive conclusion

### Verdict: Moderate drift

D8N is still one multi-brand platform, not three backend applications hidden in one repository. The most important foundations are genuinely shared:

- one global identity and credential model;
- one brand-membership and brand-profile model;
- one host-resolved, brand-bound session system;
- one profile/onboarding engine composed through brand catalogues;
- one eligibility query core;
- one Like/Pass/Match engine;
- one conversation/message engine;
- one media pipeline;
- one block/report/moderation system;
- one notification delivery foundation; and
- one brand-level account closure and suspension model.

There is no separate DateZA onboarding controller, DateZA profile table, HookUs messaging implementation, or parallel Date9ja backend in D8N. HookUs and DateZA use the same profile controllers, models, option/prompt infrastructure, completion service, publication service, media flow, interactions, safety flows, and messaging records. This is strong evidence that the platform principle remains intact.

The drift is nevertheless more than cosmetic. Four central shared surfaces now know too much about one product:

1. `Matching::FacetFilter` embeds HookUs's `vibes` concept in the generic Discovery engine.
2. `Matching::ExclusionsScope` always queries live Hooks, even for brands where Hooks are disabled.
3. generic discovery and profile detail decorate every response with Hook/Hook Tonight state; `Profiles::StatusFields` also imports HookUs's location policy.
4. brand capability choices are scattered across profile catalogues, `Brand#auth_methods`, matching registries, Find policy registry, Hook capability policy, interaction verification requirements, media policy, notification policy/types, storage configuration, and mailer template maps.

There is also a correctness gap between profile configuration and profile writes: `Profiles::Configuration` tells a client which scalar fields a brand enables, but `Api::V1::ProfileController#profile_params` accepts the entire shared scalar field set for every brand. Configuration is presentation metadata, not an authorization or validation boundary.

The conclusion is therefore:

> D8N has a healthy reusable core and has not forked by brand, but capability composition is not yet coherent enough to make a new brand configuration-only. Product-specific concerns are beginning to leak into shared discovery and serialization, and several reusable seams are represented by separate hard-coded registries rather than one auditable brand contract.

The right response is consolidation of policy boundaries, not a rewrite and not a new plugin framework.

### What is healthy

- Identity/profile separation is implemented in `User`, `BrandMembership`, and `Profile`.
- Request tenancy is explicit in `Brands::Resolver`, `ApplicationController#set_current_context`, and `Identity::SessionAuthenticator`.
- Database-level composite foreign keys protect brand ownership across profiles, options, locations, media, Find exposures, likes, matches, conversations, messages, blocks, reports, and notifications (`db/schema.rb`, especially the named `*_tenant` and `*_owner` foreign keys).
- HookUs and DateZA onboarding are compositions of the same engine through `Profiles::HookusProfileCatalog` and `Profiles::DatezaProfileCatalog`.
- Discovery ranking is a strategy behind shared eligibility, cursor, and serialization infrastructure.
- DateZA compatibility is correctly a strategy (`Matching::Strategies::DatezaV1`), not a second matching subsystem.
- Hook Tonight correctly narrows the shared Discovery engine through `guard` and `restrict` callbacks in `HookTonight::Discovery`.
- Hooks promote into the ordinary shared `Match`, `Conversation`, and `Message` system through `Hooks::ReplyToHook`.
- Media initial visibility is already represented as a brand policy in `Media::PhotoPolicy`.
- Safety and admin moderation are shared and brand-scoped.
- Notification provider integration is shared; brand presentation and event choices are separated, although currently fragmented.

### What is not configuration-only today

Launching a new brand currently requires more than inserting a `Brand` row:

- provision a `BrandDomain`;
- set `Brand#auth_methods` and `profile_requirements`;
- write or invoke a profile catalogue to install option groups, options, interests, and prompts;
- add a production discovery strategy and registry entry, or add a Find policy and compatibility strategy;
- add an interaction strategy entry before Likes/Passes work;
- choose media storage environment entries and an initial photo policy;
- add product-notification plans/types/templates if wanted;
- add any interaction verification requirement;
- configure sender identities, SMS sender, CORS origins, and R2 credentials; and
- add brand contract/isolation tests.

That is still dramatically less work than a new backend, but it is not yet one manifest plus optional strategies.

## 2. Current platform architecture

### Runtime request shape

```text
Host
  -> Brands::Resolver
  -> Current.brand
  -> bearer token
  -> Identity::SessionAuthenticator (token must belong to Current.brand)
  -> shared API controller
  -> shared domain service with explicit brand argument
  -> brand-scoped records / strategy / policy
```

Evidence:

- `domains/brands/resolver.rb`, `Brands::Resolver#call`: resolves only an active `BrandDomain` by normalized host. It does not trust a client-provided brand header.
- `app/controllers/application_controller.rb`, `set_current_context`: establishes `Current.brand`, locale, permissions, and session context. `Current.features` is currently always `{}`; it is not a functioning feature-flag system.
- `domains/identity/session_authenticator.rb`, `SessionAuthenticator#call`: rejects a token unless its `brand_id` matches the host-resolved brand and its user, membership, session, and credential remain active.
- `app/models/session.rb`, `Session.issue!`: creates a brand-bound session with a 30-day expiry.
- `config/routes.rb`: exposes one shared `/api/v1` route family. There are no separate HookUs, DateZA, or Date9ja controller namespaces.

### Data ownership

| Scope | Principal records | Actual behavior |
|---|---|---|
| Platform/global | `User`, `IdentityIdentifier`, `Credential`, password hash | A person has one D8N identity. Identifier uniqueness is global by `(kind, normalized_value)` in `IdentityIdentifier`. |
| Brand participation | `BrandMembership`, `Profile`, `Session` | A user may have one kept membership/profile per brand. A session belongs to exactly one brand. |
| Brand dating state | preferences, options, prompts, locations, photos, Find exposures, likes, passes, matches, conversations, messages, Hooks, blocks, reports | Records carry `brand_id`; core workflows query with the active brand. |
| Brand operations | admin assignments, reports, account enforcements, notification events/preferences/deliveries | Admin and delivery context is brand-scoped. |
| Network capability not yet implemented | platform erasure, network trust/reputation, shared identity verification beyond contact ownership | Planned architecture only. |

`db/schema.rb` provides unusually strong protection for a Rails modular monolith. Examples include `fk_profiles_membership_tenant`, `fk_likes_*_tenant`, `fk_matches_*_tenant`, `fk_conversations_match_tenant`, `fk_messages_*_tenant`, `fk_find_exposures_*_tenant`, `fk_profile_blocks_*_tenant`, `fk_reports_*_tenant`, and notification membership-owner foreign keys. These prevent many cross-brand associations even if application validation is bypassed.

### Authentication ownership and reuse

Authentication uses one Identity implementation for every brand. Brand policy selects allowed methods through `Brand#auth_methods` and `Identity::AuthPolicy`; all successful methods produce the same brand-bound `Session`.

| Flow | Shared runtime path | Global versus brand behavior |
|---|---|---|
| Registration | `Api::V1::Auth::PasswordsController#register` -> `Identity::PasswordRegistration` | Creates global User/identifier/credential, then one current-brand membership and session. Email and phone are both password identifiers. |
| Login | `PasswordsController#login` -> `Identity::PasswordLogin` | Looks up the global identifier/credential, but succeeds only with an active current-brand membership and configured auth method. |
| Logout | `Auth::SessionsController#destroy` -> `Identity::SessionRevoker` | Revokes only the bearer session. |
| Password change | `PasswordsController#update` -> `Identity::PasswordChange` | Authenticated shared credential workflow; affects the global credential used by any memberships. |
| Password recovery | `Auth::PasswordRecoveriesController` -> `RecoveryRequester`, `RecoveryVerifier`, `PasswordReset` | Request is brand-contextual and requires eligible brand membership/verified identifier; reset changes the global credential and revokes relevant sessions according to the shared workflow. |
| Contact verification | `Auth::VerificationsController` -> `VerificationRequester`/`VerificationVerifier` | Challenge carries a brand, while successful ownership verification is stored on the global `IdentityIdentifier`. |
| Email change | `Auth::EmailChangesController` -> `EmailChangeRequester`/`EmailChangeVerifier` | Requested through a brand session but changes a global identifier. Its cross-brand effect is therefore identity-wide. |
| Session use | `ApplicationController` -> `SessionAuthenticator` | Token replay on another brand host is rejected. |

The implementation supports phone+password and email+password. It does not implement passwordless/phone-first OTP login: OTP is used for contact verification, recovery, and email change. Google is listed in `SUPPORTED_METHODS` but excluded from `IMPLEMENTED_METHODS`, so it is not advertised as available.

Identity-wide password/email changes are consistent with `User` being global, but product should explicitly confirm that users understand one credential may unlock multiple brand memberships. The absent join-brand flow currently prevents this portability from being completed cleanly.

### Capability composition mechanisms that exist today

| Mechanism | Used for | Assessment |
|---|---|---|
| Brand columns | auth methods and profile requirement/enabled-field lists | Good, persisted configuration. |
| Brand catalogues | profile option groups/options, prompts, interests, copy, visibility | Good composition pattern. |
| Strategy registries | Discovery ranking, Like/Pass interaction location policy, compatibility | Appropriate seam, but spread across several maps and incomplete by brand. |
| Product capability policy | Hook and Hook Tonight enablement | Good deny-by-default route gate; narrowly implemented only for Hooks. |
| Policy maps | media visibility, interaction verification, Find, notifications | Useful small seams, but no single brand contract and inconsistent semantics. |
| Environment configuration | CORS, email/SMS senders, R2 buckets/services | Necessary operational configuration, partly brand-enumerated. |
| `Current.features` | nothing | Scaffold only. It is initialized to an empty hash and not used as capability authority. |

## 3. Capability matrix

Architecture labels mean: **HEALTHY**, **CONFIGURATION NEEDED**, **PLATFORM GAP**, **DUPLICATED**, **COUPLED**, or **UNKNOWN**.

| Capability | Platform implementation | HookUs | DateZA | Date9ja | Architecture |
|---|---|---|---|---|---|
| Brand tenancy | Shared `Brand`, `BrandDomain`, request context | Enabled when provisioned | First-class installer exists | No installer in this repository | HEALTHY / CONFIGURATION NEEDED |
| Global identity | Shared `User`, identifiers, credentials | Shared | Shared | Schema/auth-ready, migration not present | HEALTHY |
| Registration/login | Shared password services and controllers | Enabled by catalogue/brand row | Enabled by installer/catalogue | Migration can set methods, but no complete tenant provisioning | HEALTHY / CONFIGURATION NEEDED |
| Join another brand | No public workflow for an existing global identity | Missing | Missing | Missing | PLATFORM GAP |
| Sessions | Shared, brand-bound bearer sessions | Enabled | Enabled | Works if membership/brand exists | HEALTHY |
| Onboarding | Shared profile/config/options/prompts/preferences/photos/publication engine | Configured by HookUs catalogue | Configured by DateZA catalogue | No production catalogue/migration | HEALTHY / CONFIGURATION NEEDED |
| Scalar field enablement | Shared fields advertised by brand requirements | Advertised | Advertised | Not configured | COUPLED: writes do not enforce enabled lists |
| Discovery engine | Shared eligibility/ranking/cursor/serializer pipeline | `for_you`, `new_here` enabled | No production mode; route returns 404 | Contract only; route returns 404 | HEALTHY core / COUPLED facets / CONFIGURATION NEEDED |
| Stable curated daily Discovery | No shared batch model/allocation lifecycle | Not used | Required semantics absent | Absent | PLATFORM GAP |
| Find/Browse | `Matching::Find::Search` plus policy/filter/exposure ledger | Not registered | Enabled, 10/day | Not registered | CONFIGURATION NEEDED / CANDIDATE TO EXTRACT |
| Likes/Passes | Shared `LikeProfile`/`PassProfile` | Enabled via interaction strategy | Enabled via interaction strategy | Not registered | HEALTHY core / CONFIGURATION NEEDED |
| Matches | Shared `Match`, mutual-Like creation, listing | Shared | Shared | Data model ready | HEALTHY |
| Compatibility | Strategy registry + surface-specific strategy | HookUs score embedded in Discovery ranking | `DatezaV1` pair strategy | Contract only | HEALTHY direction / COUPLED interfaces |
| Hooks | Shared product domain, explicitly brand-gated | Enabled | Disabled | Disabled | HEALTHY capability gating |
| Hook Tonight | Shared product domain over Discovery, explicitly gated | Enabled | Disabled; delete remains cleanup-safe | Disabled | HEALTHY capability gating |
| Messaging | Shared match-gated conversations/messages | Shared | Shared | Data model ready | HEALTHY, but no explicit enablement policy |
| Media | Shared upload/R2/processing/delivery/delete pipeline | Immediate visibility policy | Moderate-first default; no approval path | Default policy, storage unconfigured | HEALTHY core / PLATFORM GAP moderation |
| Blocking/reporting | Shared brand-scoped Trust domain | Shared | Shared | Data model ready | HEALTHY |
| Admin moderation | Shared reports/suspension APIs with brand assignment | Shared | Shared | Works if provisioned/assigned | HEALTHY but narrow |
| Contact verification | Shared email/phone OTP ownership verification | Available | Available and gates interactions | Available if providers/auth configured | HEALTHY / brand-policy fragmented |
| Selfie/ID/liveness/RealMe | None | Missing | Missing | Missing | PLATFORM GAP |
| Trust/reputation | Blocks/reports/enforcement only; no score/standing engine | Partial | Partial | Partial | PLATFORM GAP |
| Notifications | Shared durable event/materialization/delivery foundation | Auth notifications; no product event plan | Welcome event/email/in-app configured | No product plan | HEALTHY infrastructure / CONFIGURATION NEEDED |
| Push | Shared records/gateway seam, no real provider or registration API | Not usable | Not usable | Not usable | PLATFORM GAP |
| Billing/payments | None | Missing | Missing | Missing | PLATFORM GAP |
| Brand account closure | Shared brand-level closure | Shared | Shared | Works if membership exists | HEALTHY but lifecycle incomplete |
| Legal erasure/rejoin | None | Missing | Missing | Missing | PLATFORM GAP |

No capability is classified **DUPLICATED** at subsystem level. The duplication found is within eligibility entry checks, not parallel brand implementations.

## 4. Onboarding reuse analysis

### Are HookUs and DateZA using the same engine?

Yes.

Both brands use:

- `Api::V1::ProfileController` for owner profile read/write;
- `Profiles::CurrentProfile` for brand-membership-scoped upsert;
- `Api::V1::ProfilePreferencesController` and the shared `ProfilePreference` model;
- `Api::V1::ProfileOptionsController` and `Profiles::OptionSelections`;
- `Api::V1::ProfilePromptsController` and `Profiles::PromptAnswers`;
- `Api::V1::ProfileLocationsController` and shared location storage;
- `Api::V1::ProfilePhotosController`, `Profiles::PhotoUpload`, and `Profiles::PhotoLibrary`;
- `Profiles::Configuration` for frontend-readable configuration;
- `Profiles::Completion` for required-field evaluation;
- `Profiles::OnboardingStatus` for next-step state; and
- `Profiles::Publication` for activation/deactivation.

The brand differences are compositions:

- `Profiles::HookusProfileCatalog` defines HookUs-only `intents` and `vibes`, enables generic capabilities, installs HookUs prompts, and writes HookUs requirements/auth methods.
- `Profiles::DatezaProfileCatalog` enables a different generic option subset, a curated interest set and prompt set, and DateZA requirements/auth methods.
- `Profiles::CapabilityCatalog` is the shared controlled-vocabulary and prompt definition source.

`test/integration/dateza_tenant_foundation_test.rb` proves one identity can hold separate HookUs and DateZA profiles and receives different configuration groups without cross-brand catalogue leakage. `test/integration/dateza_profile_onboarding_test.rb`, `test/models/dateza_profile_catalog_test.rb`, `test/models/hookus_profile_catalog_test.rb`, and `test/models/profiles_capability_catalog_test.rb` reinforce the shared-engine/configured-brand structure.

### What has been duplicated?

No onboarding engine has been duplicated. The two catalogue classes necessarily repeat the composition shape—enabled capabilities, prompts, and requirements—but that is brand policy, not duplicated workflow code.

The architectural defects are instead:

1. **Configuration is not enforced on scalar writes.** `Api::V1::ProfileController#profile_params` permits every shared scalar field for every brand. `Profiles::CurrentProfile.upsert!` persists those attributes without checking `enabled_profile_fields` or `enabled_identity_fields`. A DateZA or future-brand client can write fields that its configuration says are disabled.
2. **Owner/public serializers expose the full shared scalar schema.** `Profiles::OwnerSerializer` and `Profiles::PublicSerializer` return many fields irrespective of the brand's enabled field list. Disabled fields are usually nil, but the contract still leaks platform fields across brand products.
3. **Completion informational sections contain mixed generic/HookUs keys.** `Profiles::Completion::INTENT_GROUP_KEYS` includes `intents` and `relationship_intent`; `INTERESTS_GROUP_KEYS` includes `interests` and `vibes`. This is harmless to publication because sections are informational, but it makes a shared component aware of HookUs vocabulary.
4. **Date9ja has no production composition.** There is no `Date9jaProfileCatalog` or imported profile mapping. ADR and architecture documents describe a migration gate, but runtime implementation is absent.

### Completion/publication architecture

This area is healthy. `Brand#profile_completion_requirements` supplies requirements; `Profiles::Completion` interprets them; `Profiles::Publication.activate!` enforces the result. Clients do not own completion truth. Required option groups are brand-owned database records. The design matches the target model.

One limitation matters for future brands: completion supports fixed allowlists of scalar fields/collections plus required option groups. Conditional requirements are not represented. Date9ja's documented conditional onboarding therefore remains a product/migration decision and possibly a small platform extension, not a reason to fork onboarding.

## 5. Discovery reuse analysis

### HookUs runtime path

```text
GET /api/v1/discovery
  -> Api::V1::DiscoveryController#index
  -> Matching::Discovery.call
  -> Matching::StrategyRegistry.fetch
  -> Matching::FacetFilter.parse
  -> Matching::EligibilityScope
       -> Matching::VisibilityScope
       -> Trust::BlockPolicy
  -> optional restrict/guard
  -> Matching::ExclusionsScope
  -> Matching::FacetFilter.apply
  -> HookUs ranking strategy
  -> Matching::Cursor
  -> Matching::CandidateSerializer
```

The shared engine is real. `Matching::Discovery` owns common viewer validation, eligibility, exclusions, filtering, strategy invocation, signed cursor pagination, eager loading, and page sizing. `Matching::StrategyRegistry::MODES` selects HookUs `for_you` (`Matching::Strategies::Hookus`) and `new_here` (`Matching::Strategies::HookusNewHere`). `Matching::Cursor` binds a cursor to brand, strategy, filter, and profile order state.

### Feature classification

| Mode/feature | Classification | Evidence |
|---|---|---|
| For You | Generic engine with a HookUs ranking strategy | `StrategyRegistry::MODES`; `Strategies::Hookus.rank` scores shared intent, vibes, age fit, and distance. |
| New Here | Generic engine with HookUs strategy/configuration | `Strategies::HookusNewHere` reorders the same scored/eligible scope by recency. |
| Online Now | Generic candidate/activity concept, currently embedded in Discovery facet code | `Matching::FacetFilter::online_user_ids` uses brand sessions within 10 minutes. It is reusable but not declared per surface/brand. |
| 420 Friendly | HookUs-specific product filter implemented through HookUs `vibes` data | `FacetFilter::VIBES_GROUP = "vibes"`; the `420_friendly` option comes from `HookusProfileCatalog`. |
| Verified Only | Not implemented as a Discovery filter | No accepted parameter or filter branch in controller/service. |
| Visiting | Not implemented | No profile/location/travel state used as a Discovery facet. |
| Hook Tonight | Genuinely HookUs-specific product capability reusing generic Discovery | `HookTonight::Discovery` injects reciprocal activation guard and pool restriction. |
| Hook state on cards | HookUs-specific decoration incorrectly emitted by generic Discovery | `DiscoveryController#index` always calls `Hooks::ViewerStates` and merges `hook_state`. |

### Incorrect coupling inside the generic engine

- `Matching::FacetFilter` names and queries the HookUs `vibes` group directly. A generic facet engine should receive the configured facet definition or HookUs should decorate the shared eligible scope.
- `Matching::ExclusionsScope` always excludes `Hook.live` relationships. This remains brand-safe because the query is scoped to `viewer.brand`, but a supposedly generic exclusion primitive depends on a capability disabled for most brands.
- `DiscoveryController#index` accepts `vibe` and serializes Hook state for the generic route.
- `Profiles::StatusFields` always queries `HookTonightState` and exposes `hook_tonight_active`.
- `Profiles::StatusFields::LOCATION_MAX_AGE` imports `Matching::Strategies::Hookus::LOCATION_MAX_AGE`, coupling a generic status serializer to one matching strategy.

### Why DateZA `/api/v1/discovery` returns 404

The route is present and reaches the shared controller. It is not host-route gating and not an absent controller.

`Matching::Discovery#call` invokes `Matching::StrategyRegistry.fetch(brand:, mode:)`. `StrategyRegistry::MODES` contains only `hookus`. DateZA appears only in `CONTRACT_STRATEGIES`, whose `DatezaContract.production_ready?` is false and which is never used by the public Discovery path. `StrategyRegistry.fetch` therefore raises `UnsupportedBrand`, and `DiscoveryController` renders `404 { "error": "matching_not_configured" }`.

This is deliberate and test-covered in `test/models/matching_strategy_contract_test.rb`, `test/controllers/api/v1/discovery_controller_test.rb`, and `test/integration/dateza_tenant_foundation_test.rb`.

### What actually prevents DateZA enablement

There are two different blockers:

1. **Configuration/strategy blocker:** DateZA has no production Discovery mode/ranking entry. This is a **B — Configure** problem once the desired strategy and surface contract are approved.
2. **Product-semantics blocker:** DateZA's desired stable curated 10-profile daily selection is not what the current Discovery engine does. Current Discovery is stateless cursor pagination, default 20/max 50, with no exposure ledger, persisted batch, stable same-day set, daily consumption, or rollover. This is an **E — Build platform capability** problem for a reusable daily-batch/allocation layer.

### Can DateZA 10/day be built over the existing engine?

Yes, but not by adding one registry line.

The shared `VisibilityScope`, `EligibilityScope`, block policy, interaction exclusions, profile loading, safe serializers, and compatibility strategy should be reused. DateZA needs a reusable persisted daily-selection/allocation layer and a DateZA ranking/selection policy. That layer should be a platform Discovery surface option because future brands may also want daily picks. It should not be a separate DateZA controller, table family, or eligibility implementation.

The closest existing precedent is `Matching::Find::Search`, whose `FindProfileExposure` ledger, membership lock, policy date/reset logic, and allowance response already solve parts of persisted daily allocation. It does not provide a stable preselected batch, so it is reusable evidence—not the complete DateZA Discover implementation.

## 6. Find / browse analysis

### Runtime path

```text
GET /api/v1/find
  -> Api::V1::FindController#index
  -> Matching::Find::Search
  -> Matching::Find::PolicyRegistry (DateZA only)
  -> Matching::ProfileParticipant.discoverable!
  -> Matching::EligibilityScope
  -> Matching::ExclusionsScope
  -> Matching::Find::Filter
  -> DateZA Find policy ranking/day boundary/allowance
  -> signed Matching::Find::Cursor
  -> FindProfileExposure ledger
  -> DateZA compatibility strategy
  -> shared public serializer/status fields
```

`Matching::Find::Search` is structurally reusable. It receives a brand, resolves a policy, reuses shared eligibility/exclusions, uses a generic exposure record, binds its cursor to brand/membership/policy/filter, and asks the policy for ranking, date, reset time, location freshness, and daily limit.

The only registered policy is `Matching::Find::Policies::Dateza`, with a 10-profile daily limit and Johannesburg day boundary. `FindProfileExposure` is not DateZA-named and has tenant-owner composite foreign keys. `Matching::Find::Filter` validates relationship-intent values against the current brand's option catalogue.

### Architectural classification

DateZA Find is not a duplicated DateZA backend capability. It is an implicitly reusable browse/exposure engine with DateZA as its first policy. Its namespace and hard-coded page ceiling (`DEFAULT_LIMIT = MAX_LIMIT = 10`) make the product boundary look more DateZA-owned than necessary, and the registry has no second-brand proof.

Classification: **C — Extract** the reusable browse/allocation semantics conceptually, plus **B — Configure** additional brands. No refactor should happen until the intended distinction among Find, Browse, Search, and Discovery is approved.

### Find versus Discovery today

| Concern | Discovery | Find |
|---|---|---|
| Persistence | No exposure persistence | `FindProfileExposure` per day/member/candidate |
| Daily allowance | None | Policy-provided; DateZA 10/day |
| Stable daily batch | No | No; only already-exposed profiles do not consume twice |
| Ranking | Strategy registry; HookUs score/recency | Policy rank; DateZA newest first |
| Filters | HookUs `vibe`, generic online | age, distance, relationship intent |
| Pagination | signed strategy/filter cursor | signed brand/member/policy/filter cursor |
| Brands | HookUs only | DateZA only |

They are distinct runtime products. Treating them as synonyms would hide real semantics.

## 7. Eligibility architecture

### Shared primitives

- `Matching::VisibilityScope`: brand, active/visible profile, active user, active membership, adult, preference row, and block exclusion.
- `Trust::BlockPolicy`: block checks and exclusion of profiles/matches.
- `Matching::EligibilityScope`: reciprocal gender preference, reciprocal age ranges, and reciprocal distance policy layered on visibility.
- `Matching::ExclusionsScope`: prior outgoing Like, Pass, active Match, and live Hook in either direction.
- `Matching::ProfileParticipant`: validates the viewer as discoverable or as a match member.

Discovery, Find, Likes, Passes, Hook sending, public profile lookup, Hook inbox, Matches, and Messaging reuse meaningful portions of this stack.

### Duplication and inconsistency

1. `Matching::Discovery#current_viewer!` duplicates most of `Matching::ProfileParticipant.discoverable!` instead of calling it.
2. `ProfileParticipant.discoverable!` and `ProfileParticipant.match_member!` are intentionally different, but there is no named policy object explaining which surfaces require publication versus only an available profile.
3. `EligibilityScope` accepts `location_max_age` from a strategy/policy. This is a useful seam, but Like/Pass obtains it from `StrategyRegistry.interaction_for`, Hook send obtains it from production Discovery `StrategyRegistry.fetch`, and DateZA compatibility directly reaches `Find::Policies::Dateza`. The same location rule is routed through three abstractions.
4. `ExclusionsScope` mixes universal interaction exclusions with Hook-specific exclusions.
5. Discovery and Find do not use `Identity::InteractionAccess`; Likes, Passes, matches, profile detail, conversations, messages, and Hooks do because they inherit `InteractionController`. DateZA can browse unverified but cannot perform those interactions. This may be intentional, but it is not represented as a surface capability manifest.
6. Verification is not an input to `EligibilityScope`; it is a controller-level mutation/access gate. There is no verified-only candidate policy.

### Reuse verdict

The core query logic is shared and valuable. The risk is not parallel brand eligibility implementations; it is the accumulation of surface-specific exceptions inside one broad scope plus duplicated viewer validation. Consolidate the primitives before adding a third production matching brand.

## 8. Matching and compatibility architecture

### Shared engine mechanics

- `Matching::LikeProfile` creates idempotent directional Likes and creates a canonical active `Match` when the reverse Like exists.
- `Matching::PassProfile` creates idempotent passes and prevents passing after a positive relationship.
- `Match.canonical_pair` and the active unique index prevent duplicate active pair records.
- `Matching::MatchList` is shared, brand-scoped, block-aware, lifecycle-aware, and signed-cursor paginated.
- `Matching::CandidateSerializer` provides a common Discovery candidate/compatibility shape.

### Strategy/policy boundaries

- HookUs Discovery compatibility/ranking is `Matching::Strategies::Hookus`. It computes intent/vibe/distance-based score and reasons in SQL.
- HookUs New Here reuses the HookUs score projection and only changes ordering.
- DateZA pair compatibility is `Matching::Strategies::DatezaV1`, a deterministic symmetric weighted comparison over DateZA-configured fields.
- Date9ja and DateZA contract strategies prove the ranking/cursor interface but explicitly report `production_ready? == false`.

DateZA compatibility is architecturally correct as a brand strategy over shared profiles and eligibility. It is deterministic logic, not AI, embeddings, or an LLM.

### Coupling to fix

- `DatezaV1#assert_eligible!` directly references `Find::Policies::Dateza.location_max_age`. A compatibility strategy should not depend on the Find product namespace for a general pair-eligibility parameter.
- `StrategyRegistry::INTERACTION_STRATEGIES` maps DateZA to its Find policy and HookUs to its Discovery strategy. The registry values happen to share `location_max_age`, but they do not represent one coherent interaction-policy interface.
- HookUs score and generic compatibility presentation are combined in the Discovery ranking strategy, while DateZA uses a separately instantiated pair scorer in `FindController`. The product behavior is valid, but the interfaces are inconsistent.

No duplicated Like, Pass, Match, or compatibility subsystem exists.

## 9. Profiles

There is one D8N profile platform:

- scalar data: shared `profiles` table and `Profile` validations;
- preferences: shared `profile_preferences`;
- controlled options: brand-scoped groups/options/selections;
- prompts: brand-scoped prompts and answers;
- interests: the generic `interests` option group when enabled;
- location: shared exact private `ProfileLocation` plus approximate serialized city/country and computed distance;
- media: shared `ProfilePhoto` records and Active Storage attachments;
- lifecycle: draft/active/suspended plus hidden/visible and soft-deletion;
- completion/publication: shared services driven by brand requirements.

### Generic fields

The stable shared schema includes identity names on `User`, profile display/bio/birthdate/gender/pronouns, country/city, occupation/employment/education text, height/body type, languages, smoking/drinking/fitness, children count, and preference fields. Controlled capabilities provide relationship intent, interests, lifestyle, family, religion, orientation, and other typed option groups.

### Brand-enabled/required fields

The source of truth for advertised and required scalar fields is `Brand#profile_requirements`, installed by brand catalogues. Option/prompt availability is enforced through brand-owned database records and `Profiles::OptionSelections` / `Profiles::PromptAnswers`.

### Leakage inventory

- Disabled scalar fields can be written because `profile_params` does not use brand enabled lists.
- `OwnerSerializer` and `PublicSerializer` emit the broad shared scalar contract rather than the enabled subset.
- `ProfilesController#show` always adds `hook_state`; `StatusFields` always adds `hook_tonight_active`. DateZA currently receives Hook product state despite Hooks being disabled.
- Generic completion section labels know the HookUs `intents`/`vibes` keys.
- Contact verification is exposed as `verified` across brands based on any global verified identifier, while DateZA mutation authorization requires the current session's login identifier. The badge and authorization can therefore disagree.

The leak is response/policy coupling, not cross-brand record disclosure: Hook queries remain scoped by the viewer's brand.

## 10. Media

### Shared platform path

```text
POST profile/photos/uploads
  -> Profiles::PhotoUpload.create_intent
  -> brand/environment Media::StorageResolver
  -> signed direct upload URL to private storage

POST profile/photos
  -> signed blob lookup
  -> verify service belongs to brand
  -> verify object exists, magic bytes, actual size
  -> ProfilePhoto with Media::PhotoPolicy state
  -> Media::ProcessProfilePhotoJob
  -> safe display derivative / processing state

GET serializer
  -> only deliverable kept photos
  -> short-lived signed display-image URL

DELETE
  -> owner+brand lookup
  -> soft-delete/hide row
  -> purge original and derivative later
```

Evidence: `Profiles::PhotoUpload`, `Media::StorageResolver`, `Media::ObjectKey`, `Media::ProcessProfilePhotoJob`, `Media::ImageProcessor`, `Profiles::PhotoLibrary`, `ProfilePhoto#deliverable?`, and `Profiles::PublicSerializer#public_photos`.

This is a reusable platform implementation. Object keys and storage resolution include the brand; blob attachment verifies compatibility with the active brand. Safe JPEG re-encoding strips metadata/EXIF before public delivery. Originals are not serialized publicly.

### Brand policy

`Media::PhotoPolicy` is the correct kind of seam:

- HookUs: pending review but visible immediately.
- all unlisted brands, including DateZA/Date9ja: pending review and hidden.

The limitation is operational: there is no automated moderation provider or staff photo-approval/rejection endpoint. A moderate-first brand's valid processed photos have no production API path to become approved/visible. HookUs can ship because its policy is immediate; DateZA cannot rely on public photos without completing moderation policy/operations or explicitly choosing immediate visibility.

`config/storage.yml` enumerates HookUs and DateZA R2 services. Production dynamically validates the configured brand list, but adding a new brand still requires service configuration and secrets. The HookUs legacy `r2` service exception in `Media::StorageResolver.compatible_service?` is correctly narrow migration compatibility, not a new media subsystem.

Video is absent. Media reporting correctly reuses the shared Trust report target resolver.

## 11. Messaging

Messaging is genuinely platform-wide:

- `Messaging::StartConversation` authorizes a current-brand active Match, creates one conversation, and creates both participants.
- `Messaging::ConversationAccess` and `Messaging::MatchAccess` enforce membership, participant, active-match, lifecycle, and both-direction block rules.
- `Messaging::ConversationList` and `Messaging::MessageList` are signed-cursor paginated and brand-scoped.
- `Messaging::SendMessage` persists a normalized, bounded plain-text message.
- Hook acceptance invokes the same `Match`, `Conversation`, `ConversationParticipant`, and `Message` records.

There are no HookUs- or DateZA-specific messaging services. Composite database foreign keys bind participants/messages/conversations to the same brand.

Platform gaps are read state, unread message counts, message editing/deletion, message media, replies/reactions, typing/presence, realtime delivery, and message notification events. `config/cable.yml` explicitly has no exposed D8N channel. These are missing shared capabilities, not brand divergence.

Messaging has no explicit brand enablement policy. Any correctly provisioned brand with a Match can use it. That is acceptable if messaging is mandatory platform functionality; if future brands may disable chat, the decision belongs in the capability contract.

## 12. Safety and moderation

Safety is shared and brand-scoped:

- `Trust::BlockProfile` resolves the viewer/target in one brand, creates an idempotent block, removes Likes, and ends an active Match.
- `Trust::BlockPolicy` is reused by visibility, matching, match listing, conversation access, and Hook flows.
- `Trust::FileReport` is one target-agnostic report workflow with target resolvers for profile, media, message, and Hook.
- report evidence is derived server-side by `Trust::ReportTargets::*` rather than trusted from the client.
- `Admin::ReportQueue`, `ReportDetail`, and `TransitionReport` implement a brand moderation queue/lifecycle.
- `Admin::SuspendProfile` and `ReinstateProfile` operate at brand membership level, revoke only that brand's sessions, and audit changes.
- `Admin::ModeratorContext` derives staff authority from current-brand assignments.

Hook is a legitimate extra report target, not a duplicate reporting system.

Gaps: no network-level safety action, no automated media moderation, no trust/reputation aggregation, no admin user search/list API, no appeals, no legal evidence-retention policy engine, and coarse admin roles. These should be built once in the Trust/Admin domains.

## 13. Notifications

### Reusable infrastructure

The durable flow is:

```text
domain event
  -> Notifications::EventPublisher
  -> NotificationEvent (idempotent outbox row)
  -> ProcessEventJob
  -> MaterializeEvent
  -> Notification + in-app/email/push deliveries
  -> DeliverProductNotificationJob
  -> provider gateway
  -> retry/recovery jobs
```

`Notifications::MaterializeEvent`, `NotificationEvent`, `Notification`, `NotificationDelivery`, preferences, inbox presentation, and delivery jobs are shared and brand-scoped. Email and SMS use provider abstractions. Resend and Twilio implementations are isolated behind `Notifications::Email` and `Notifications::Sms`; push has only a fail-closed/test gateway.

Brand presentation is separated from providers:

- mailers choose a brand template name;
- sender addresses resolve per brand;
- Twilio sender resolves from a brand-derived environment key;
- notification policy maps `(brand, event_type)` to a notification type/template.

### Current coupling/gaps

- Only DateZA's `membership_registered` event is handled, producing `dateza.welcome` (`Notifications::Policy`, `Notifications::Types`, DateZA templates).
- Likes, matches, messages, Hooks, reports, enforcement, and account security do not publish product notification events.
- Auth code delivery is shared, but DateZA has custom mailer templates while other brands fall back to generic templates.
- Product event policy, type definitions, mailer maps, and templates are separate registries; a new brand must be added in several places.
- `Notifications::Email` retains a correctly narrow legacy HookUs sender fallback.
- Twilio maps sender by brand dynamically. Staging now declares both HookUs and
  DateZA Messaging Service SID secrets, and `Sms.configured?` includes the
  resolved brand sender instead of checking only account credentials. Whether
  the DateZA secret currently points to a provider-approved sender remains an
  operational staging check.
- Device registrations and push materialization exist, but there is no public device registration route and no production APNs/FCM provider.

The desired “generic events/delivery + brand templates/configuration” direction is present, but only one product event proves it.

## 14. Verification, trust, and RealMe

These concepts must not be conflated.

| Concept | Current implementation | Reuse assessment |
|---|---|---|
| Email/phone ownership | Shared OTP challenges, request/verify services, expiry/attempt throttles, provider jobs | Healthy platform Identity capability. |
| Interaction verification policy | DateZA requires verified session login identifier through `Identity::InteractionAccess` | Correct intent, scattered hard-coded brand policy. |
| Public `verified` badge | Any global verified contact identifier in `Profiles::StatusFields` | Reusable fact but semantically inconsistent with DateZA access policy. |
| Selfie/liveness/face match | None | Platform gap. |
| Government ID | None | Platform gap. |
| Video verification | None | Platform gap. |
| RealMe/verification levels | None | Platform gap. |
| Trust/reputation/behavior score | None | Platform gap. |
| Safety history/enforcement | Reports, blocks, security events, brand suspension | Reusable raw signals; no trust aggregate. |

The identity/profile separation leaves a sound path: provider evidence and identity-level verification can remain global where appropriate; brand policy decides acceptance, freshness, display, and required level; serious network safety can remain distinct from brand moderation. That policy model does not yet exist.

Before building it, product must decide whether verification is portable across brands, which evidence is identity-level versus membership-level, whether contact verification may be publicly badged, and whether a brand can require a fresh or brand-specific proof.

## 15. Monetization readiness

There are no plan, subscription, payment, entitlement, price, webhook, renewal, cancellation, or payment-provider records/services/routes. `D8N Pay` is planned only.

Existing allowance code has useful seams:

- `Hooks::Policy.daily_limit_for(profile)` can later consult entitlements.
- `Matching::Find::Policies::Dateza.daily_limit(membership)` can later consult entitlements.

However, limits are scattered by product and there is no shared `Entitlements` query. Discovery rate limits in `AbuseProtection::Policy` are explicitly security ceilings, not product allowances. Future billing should provide a shared entitlement/allowance service used by product policies; it should not move product semantics into payment controllers.

Hard-coded free limits do not make billing impossible, but adding premium independently to each policy would create drift quickly.

## 16. Account lifecycle

### What exists

- Registration creates a global `User`, a global identifier/credential, a brand membership, and a brand session (`Identity::PasswordRegistration`).
- Login resolves the global credential but requires an active membership in the requested brand (`Identity::PasswordLogin`).
- `Accounts::CloseAccount` closes one brand membership, hides/anonymizes its profile, ends matches, discards likes/passes/preferences/photos, deletes exact location history, revokes that brand's sessions/devices, writes a security event, and enqueues `Media::PurgeProfileMediaJob`.
- Other brand memberships, profiles, and sessions remain intact. `test/integration/dateza_tenant_foundation_test.rb` proves this.
- `Admin::SuspendProfile`/`ReinstateProfile` operate on one brand membership and leave other brands untouched.

### Missing multi-brand lifecycle

- No authenticated “join another brand” path for an existing `User`.
- No account-linking flow. Because `IdentityIdentifier` is globally unique, registering the same email/phone on another brand returns a neutral duplicate failure instead of creating a second membership.
- No rejoin path after `BrandMembership.status_left`; registration still collides with the retained global identifier.
- No explicit leave-with-retention choices, restoration workflow, or profile transfer/copy policy.
- No platform-wide legal erasure/anonymization workflow.
- No user data export.
- No network-level suspension separate from `User.status` and brand-level enforcement workflow.

The model is correctly multi-brand; the public lifecycle is incomplete.

## 17. Brand isolation

### Proven controls

| Surface | Isolation control |
|---|---|
| Request tenant | Active host-to-`BrandDomain` resolution only. |
| Session | Token's `brand_id` must match host-resolved brand; active membership required. |
| Profiles/options/prompts | Brand-owned rows and brand-scoped lookups; composite tenant FKs. |
| Discovery/Find | Services receive brand; candidate scopes start from `brand.profiles`; cursors bind brand. |
| Likes/Passes/Matches | Brand-scoped target lookup and composite profile-brand FKs. |
| Conversations/messages | Brand-scoped access plus match/participant composite FKs; cursors bind brand/viewer. |
| Media | Brand/profile/user ownership, brand-derived object key/service, signed blob/service compatibility checks. |
| Blocks/reports | Brand-scoped target resolvers and tenant FKs. |
| Notifications | Brand/membership/user composite owner FKs; brand-scoped inbox. |
| Admin | Current-brand assignment resolution; report/profile target query constrained to brand. |
| Rate limits | Authenticated keys include current brand; global IP ceilings are intentionally network-wide abuse controls. |

Tests with direct isolation evidence include `test/integration/dateza_tenant_foundation_test.rb`, `test/models/brands_resolver_test.rb`, `test/models/session_test.rb`, `test/controllers/api/v1/discovery_controller_test.rb`, `test/models/matching_eligibility_scope_test.rb`, `test/controllers/api/v1/conversations_controller_test.rb`, `test/controllers/api/v1/profile_photos_controller_test.rb`, `test/controllers/api/v1/generic_reports_controller_test.rb`, and admin controller tests.

### Leakage findings

| Finding | Severity | Explanation |
|---|---|---|
| Hook/Hook Tonight fields appear on non-Hook brands | Medium architectural/API leakage | Queries remain brand-scoped, so another brand's records are not exposed; DateZA still receives an irrelevant capability contract. |
| Scalar profile fields can be written when not enabled | Medium product/isolation-of-capability risk | Does not cross tenant rows, but one brand can accumulate another product's fields and expose them through generic serializers. |
| Public contact `verified` derives from global identifiers | Medium privacy/product-policy risk | Verification on one brand can produce a badge on another brand. This may be intended portability, but no explicit policy decides it. |
| Notification/SMS provider readiness not fully brand-aware | Medium operational isolation risk | One brand can appear configured because global Twilio credentials exist while its sender identity is absent. |
| Generic exclusions query Hook records for disabled brands | Low data-leak risk, medium coupling | Query is brand-scoped and returns none; cost and dependency still leak product behavior into shared code. |
| Legacy HookUs R2/email fallbacks | Low | Narrowly guarded and explicitly migration-compatible; no cross-brand fallback. |

No concrete cross-brand record disclosure path was found in the audited public runtime flows.

## 18. Brand-specific production-code inventory

The literal search found 23 Ruby production files under `app/` and `domains/` containing `hookus`, `dateza`, or `date9ja`; including deployment/storage/templates/load tooling raises the non-test total to 29 files. Literal counts are only a locator, not an architectural verdict.

### Correctly brand-specific

| Code | Classification | Reason |
|---|---|---|
| `domains/brands/dateza_installer.rb` | Correct | Tenant provisioning and DateZA catalogue installation. |
| `domains/profiles/hookus_profile_catalog.rb` | Correct | HookUs field/options/prompts/completion composition. |
| `domains/profiles/dateza_profile_catalog.rb` | Correct | DateZA field/options/prompts/completion composition. |
| `domains/matching/strategies/hookus.rb` | Correct | HookUs ranking/compatibility philosophy. |
| `domains/matching/strategies/hookus_new_here.rb` | Correct | HookUs-enabled Discovery ordering mode. |
| `domains/matching/strategies/dateza_v1.rb` | Correct strategy, one coupling | DateZA deterministic compatibility is valid; dependence on Find location policy is not. |
| `domains/matching/find/policies/dateza.rb` | Correct | DateZA allowance/day/ranking policy. |
| `domains/matching/strategies/date9ja_contract.rb` and `dateza_contract.rb` | Correct non-production proofs | Explicitly unavailable contract fixtures, not separate engines. |
| DateZA mail templates/views | Correct | Brand presentation/copy. |
| Hook/Hook Tonight domain models/services | Correct product-specific capability | Product semantics are genuinely HookUs-oriented and explicitly gated. |
| DateZA/HookUs demo seed modules and tasks | Correct tooling | Brand demo content, not runtime platform behavior. |

### Suspicious: should remain policy/configuration, but is scattered

| Code | Concern |
|---|---|
| `domains/matching/strategy_registry.rb` | Four separate maps for modes, contracts, interactions, and compatibility; adding a brand requires coordinated edits. |
| `domains/matching/find/policy_registry.rb` | Find is reusable in shape but has only a DateZA mapping and no generic capability declaration. |
| `domains/identity/interaction_access.rb` | DateZA requirement is a hard-coded map separate from capability enablement. |
| `domains/media/photo_policy.rb` | Good policy object, but another isolated brand map. |
| `domains/notifications/policy.rb`, `types.rb`, mailer template maps | Correct concepts split across multiple registration points. |
| `config/storage.yml` and deployment env | New brands require explicit infrastructure entries; expected operationally, but should be checked by one brand launch contract. |
| `domains/notifications/email.rb` and `domains/media/storage_resolver.rb` | HookUs literal is narrow legacy compatibility and should not spread. |

### Incorrect coupling

| Code | Problem |
|---|---|
| `domains/matching/facet_filter.rb` | Generic Discovery filter hardcodes HookUs `vibes`. |
| `domains/matching/exclusions_scope.rb` | Universal exclusion scope directly depends on `Hook`. |
| `app/controllers/api/v1/discovery_controller.rb` | Generic route accepts `vibe` and emits Hook viewer state. |
| `app/controllers/api/v1/profiles_controller.rb` | Generic profile detail emits `hook_state`. |
| `domains/profiles/status_fields.rb` | Generic status includes Hook Tonight and imports HookUs location freshness. |
| `domains/profiles/completion.rb` | Informational generic sections know HookUs `intents` and `vibes`. Low severity. |

### Incorrect duplication

None found at capability/subsystem level. There are duplicated viewer-eligibility predicates inside shared matching code, but no separate HookUs/DateZA onboarding, matching, messaging, media, safety, or notification engines.

Historical migration names such as `AddHookusProfileDetails` describe when fields entered the schema. The resulting fields live on the shared `profiles` table and are used by the generic profile API; the filename is not evidence of a runtime fork.

## 19. Brand conditional inventory

### Centralized and acceptable conditionals

- profile catalogue selection in `db/seeds.rb`;
- Hook enablement in `Hooks::CapabilityPolicy::ENABLED`;
- matching mode/strategy selection in `Matching::StrategyRegistry`;
- Find policy selection in `Matching::Find::PolicyRegistry`;
- interaction verification in `Identity::InteractionAccess::REQUIREMENTS`;
- media initial state in `Media::PhotoPolicy::BRAND_POLICIES`;
- notification plan/type/template maps;
- brand-derived provider/storage environment keys; and
- narrow HookUs legacy sender/blob compatibility.

These are the right categories of brand decision. Their weakness is dispersion, not the existence of a conditional.

### Hidden conditionals without a slug check

The more serious coupling does not appear as `if brand.slug == ...`:

- a `vibes` database key in `Matching::FacetFilter` silently makes the generic filter HookUs-aware;
- direct `Hook.live` queries in `Matching::ExclusionsScope` make generic exclusions depend on Hooks;
- direct `HookTonightState` and `Hooks::ViewerStates` calls make generic profile/discovery responses product-aware;
- `Profiles::Completion` hardcodes HookUs option-group keys.

This is why counting `if dateza?` alone understates drift.

### Trend assessment

The repository is still trending more toward policy/strategy than controller-level slug branching. Controllers contain almost no direct brand slug conditionals. The risk is that each new capability introduces another independent registry or silently enters a generic query/serializer. Without one auditable brand contract, a fourth brand will be enabled inconsistently.

## 20. Test architecture

### Healthy pattern

Most capability behavior is tested generically:

- authentication controllers/services;
- profile models, configuration, completion, options, prompts, preferences, photos, publication;
- generic eligibility, Discovery controller, Like/Pass/Match concurrency and behavior;
- conversations/messages;
- block/report/admin enforcement;
- media processing/storage policy;
- notification event/materialization/delivery; and
- tenant schema/model behavior.

Brand contract tests sit on top:

- `test/models/hookus_profile_catalog_test.rb`;
- `test/models/dateza_profile_catalog_test.rb`;
- `test/integration/dateza_profile_onboarding_test.rb`;
- `test/integration/dateza_tenant_foundation_test.rb`;
- `test/controllers/api/v1/dateza_interaction_verification_test.rb`;
- `test/controllers/api/v1/hook_brand_capability_test.rb`;
- DateZA Find day/concurrency/controller tests;
- DateZA compatibility tests;
- DateZA welcome-notification tests; and
- `test/models/matching_strategy_contract_test.rb` for non-production Date9ja/DateZA contracts.

This is close to the desired generic capability suite plus brand contract suite. There are not full duplicated onboarding or messaging suites per brand.

### Test gaps that allow drift

- No general “disabled capabilities never appear in response fields” contract. Existing tests correctly prove Hook endpoints are disabled on DateZA but do not prevent `hook_state`/`hook_tonight_active` leakage on generic profile detail.
- No test that rejects writes to scalar fields disabled by a brand's profile configuration.
- No shared contract runner that every installed brand must satisfy for host/session/profile/media/safety/capability behavior.
- Find's reusable engine is exercised almost entirely through DateZA; no neutral policy fake or second-brand contract proves reuse.
- Notification product behavior has only the DateZA welcome event; no generic event-plan contract for another brand.
- Date9ja has interface contract tests only, appropriately reflecting its non-production state, but no installer/profile catalogue/migration contract.
- No test establishes whether global contact verification should or should not create a public badge across brands.

### Test architecture verdict

Tests currently reinforce reuse more than duplication. Add capability-contract and negative-leakage tests before adding another production brand; do not copy entire controller suites under a brand namespace.

## 21. Architecture drift assessment

### Have we deviated from D8N's platform architecture?

**Moderate drift.**

The platform model itself has not been abandoned. Shared tables, services, controllers, jobs, policies, and tenant constraints dominate production architecture. There are no parallel brand backends.

The rating is moderate because the drift occurs in central seams:

1. **Capability composition is fragmented.** There is no coherent answer to “what can this brand do?” without consulting many maps and environment files.
2. **Generic Discovery is HookUs-coupled.** Filters, exclusions, card state, and status fields embed Hook concepts.
3. **Configuration is advisory in part.** Scalar field enablement is not enforced on write/serialization.
4. **Eligibility entry rules are duplicated and policy sourcing is inconsistent.** This raises the chance that Discovery, Find, Likes, Hooks, and compatibility diverge.
5. **DateZA Find is reusable in implementation but presented as a one-brand subsystem.** Without an explicit platform surface abstraction, a future browse product may be copied instead of configured.
6. **Verification semantics are inconsistent.** Global contact ownership drives a public badge, while DateZA interaction access is session-identifier-specific.

### Top drift risks

1. More HookUs state entering shared serializers and candidate scopes.
2. A DateZA daily Discovery implementation copying Find/Discovery eligibility rather than composing it.
3. A future brand catalogue advertising one field set while APIs accept/emit another.
4. Product allowances integrating billing independently in Hooks, Find, Likes, and Discovery.
5. A new brand being partially enabled across auth, matching, media, notifications, and safety because no single contract validates the complete composition.
6. Date9ja migration pressure introducing a separate conditional onboarding/matching path instead of extending the existing typed capability and strategy boundaries.

## 22. Proposed target architecture

The smallest coherent target is an incremental modular-monolith refinement:

```text
Brand
  -> one auditable product/capability contract
       -> auth methods and interaction verification policy
       -> profile catalogue + required/enabled fields
       -> enabled surfaces (discovery/find/hooks/messaging/etc.)
       -> surface policy (limits, filters, timezone, media visibility)
       -> optional strategy (ranking/compatibility)
       -> notification presentation/events
       -> infrastructure readiness checks

Shared capability controller
  -> capability authorization
  -> shared domain engine
  -> configured policy/strategy
  -> surface-specific serializer decorations
```

This does not require a dynamic plugin system or a generic rules language.

### Preserve these existing patterns

- explicit `brand:` arguments;
- brand-scoped Active Record models and composite foreign keys;
- `Profiles::CapabilityCatalog` plus one catalogue per brand;
- focused strategy classes for ranking and compatibility;
- deny-by-default behavior such as `Hooks::CapabilityPolicy` and matching registries;
- provider-independent notification gateways;
- shared eligibility/visibility/blocking primitives; and
- route presence separated from capability availability.

### Small extensions needed

1. Establish one brand capability contract or manifest that references existing policies/strategies rather than replacing them. It can remain Ruby configuration initially.
2. Make all product routes use one generic capability gate, preserving stable `*_not_configured` responses.
3. Split universal matching exclusions from capability-contributed exclusions. Hooks should register/inject their exclusion only when enabled.
4. Make Discovery facets surface/brand configuration. Online can be generic; HookUs vibe/420 remains a HookUs facet definition.
5. Make response decorations surface-specific. Generic profile/detail serializers should not know Hooks; a HookUs surface decorator may add Hook state.
6. Enforce profile enabled fields on write and serialize only enabled public fields, while retaining shared schema storage.
7. Consolidate discoverable viewer validation and pair eligibility into named shared primitives. Policies should provide location freshness without reaching into another product namespace.
8. Add a reusable daily-selection/exposure capability for curated Discovery, using shared eligibility and a policy for limit/timezone/ranking/stability.
9. Introduce a shared entitlement query before premium changes any hard-coded product allowances.
10. Add a brand launch contract/test helper that checks tenant host, auth, profile catalogue, matching/interaction strategy, media readiness, notifications, and explicitly disabled capability responses.

## 23. A/B/C/D/E classification

Definitions:

- **A — Leave alone:** already correctly reusable.
- **B — Configure:** capability exists; brand configuration is missing.
- **C — Extract:** reusable behavior exists implicitly inside product-specific or overly broad code.
- **D — Consolidate:** multiple implementations duplicate the same capability.
- **E — Build platform capability:** capability genuinely does not exist.

| Finding | Class | Why |
|---|---|---|
| Global identity, membership, brand profile model | A | Correct platform/brand separation. |
| Host resolution and brand-bound sessions | A | Shared and strongly isolated. |
| Profile option/prompt/catalogue composition | A | Correct generic definitions plus brand catalogues. |
| Shared completion/publication | A | Requirements are brand configuration over one engine. |
| Hook/Hook Tonight capability gate | A | Clear deny-by-default pattern. |
| Shared Like/Pass/Match mechanics | A | One implementation with strategy-supplied policy. |
| Shared messaging | A | One match-gated brand-scoped implementation. |
| Shared safety/admin moderation | A | One target-agnostic report/block/enforcement implementation. |
| DateZA production Discovery strategy | B | Shared engine exists; DateZA mode/ranking is not registered. |
| Date9ja profile/matching production composition | B, with migration decisions | Shared engines exist, but catalogue/strategy/migration mapping is absent. |
| New-brand media/notification/provider setup | B | Infrastructure exists; configuration/templates/readiness are needed. |
| DateZA Find as reusable browse surface | C | Shared mechanics exist under a one-product namespace/registry. |
| HookUs `vibes` facet in generic Discovery | C | Product facet should be injected/configured. |
| Hook exclusions in generic `ExclusionsScope` | C | Capability-specific exclusion should compose with universal exclusions. |
| Hook state in generic serializers/status fields | C | Surface-specific decoration embedded in platform response. |
| Scalar enabled-field enforcement | C | Configuration exists; persistence/serialization must consume it. |
| Viewer eligibility duplication | D | `Discovery#current_viewer!` and `ProfileParticipant.discoverable!` repeat the same predicate. |
| Location-policy sourcing across Discovery/Find/interactions/compatibility | D | Multiple strategy/policy paths represent the same freshness decision. |
| Stable curated daily Discovery batch | E | No persisted batch/stability/rollover capability exists. |
| Join/rejoin another brand | E | Global identity model exists, public membership workflow does not. |
| Legal erasure/export | E | Brand closure is not platform erasure. |
| Identity/selfie/ID/liveness/RealMe | E | No domain implementation. |
| Trust/reputation score | E | Raw safety signals exist; aggregation/policy does not. |
| Billing/subscriptions/entitlements/payments | E | No backend capability exists. |
| Realtime/read/media messaging | E | Core text messaging exists; these shared features do not. |
| Photo moderation decision path | E | Moderate-first policy exists; approval/rejection operation does not. |

The critical distinction is that DateZA Discovery is both **B** and **E**: registering a strategy is configuration, while stable daily curated-batch semantics are a missing reusable capability. It is not a reason to build a parallel DateZA Discovery stack.

## 24. Answers to the 13 special questions

### 1. Are HookUs and DateZA using the same D8N onboarding engine?

Yes. They share routes, controllers, models, configuration, completion, publication, options, prompts, preferences, location, and photo services. Only their catalogue composition and policy data differ.

### 2. If not, exactly what has been duplicated?

The premise is false: no onboarding engine is duplicated. Catalogue declarations repeat the expected composition shape. The only true duplication is discoverable-viewer eligibility inside shared matching code, unrelated to brand onboarding.

### 3. Does HookUs Discovery use a generic D8N Discovery engine?

Yes. `Matching::Discovery` is shared and delegates ranking/cursor details to HookUs strategies. It reuses shared visibility, eligibility, blocks, exclusions, loading, and candidate serialization. The engine is partially HookUs-coupled through facets, exclusions, and response decoration.

### 4. Why does DateZA `/api/v1/discovery` return 404?

The route/controller run, but `Matching::StrategyRegistry::MODES` has no DateZA production entry. `DatezaContract` is deliberately non-production and lives only in the contract registry. `UnsupportedBrand` becomes `matching_not_configured` 404.

### 5. Can DateZA's curated 10/day Discovery be expressed as policy/configuration/strategy over the existing engine?

Mostly. Shared eligibility, blocking, interaction exclusions, profile loading, compatibility, and serialization should be reused. A new reusable persisted daily-batch/allocation capability is still needed for stable selection, daily rollover, and consumption semantics. Build that once and configure DateZA's limit/timezone/ranking.

### 6. Is DateZA Find reusable or unnecessarily brand-specific?

Its implementation is largely reusable: policy registry, shared eligibility/exclusions, generic exposure ledger, signed cursor, and brand-validated filters. It is unnecessarily one-brand in naming/registration and lacks a neutral/second-brand contract. Extract/configure; do not duplicate.

### 7. Which HookUs features are platform capabilities DateZA could enable?

Shared auth, profiles/options/prompts/preferences/location, Discovery mechanics, Likes/Passes/Matches, public profile detail, media, text messaging, blocks, reports, admin moderation, contact verification, sessions, notification infrastructure, and brand closure. DateZA already uses many. Online and New Here are reusable concepts but need surface/brand policy rather than copying HookUs wiring.

### 8. Which HookUs features are genuinely HookUs-specific product concepts?

Hook as a one-opener interaction, Hook inbox/decline/reply semantics, Hook Tonight temporary availability/pool, HookUs `intents` and `vibes` vocabulary/copy, 420 Friendly presentation, and HookUs ranking weights/reasons. Their storage/workflow may still be a platform capability enabled for HookUs, but their product semantics should not leak into DateZA.

### 9. Are Likes, Matches, Messaging, Profiles, Media, Safety, and Notifications genuinely shared today?

Likes, Matches, Messaging, Profiles, Media, and Safety are genuinely shared. Notifications have genuinely shared infrastructure and provider jobs, but product event materialization is only configured for DateZA welcome; most dating events publish nothing.

### 10. Where are brand conditionals accumulating?

Matching registries, Find policy registry, Hook capability policy, interaction verification, media policy, notification policy/types/templates, mailer selection, provider sender selection, storage configuration, seeds/installers, and compatibility assertions. More concerning than literal slug checks are Hook concepts embedded in generic FacetFilter, ExclusionsScope, StatusFields, and controllers.

### 11. What would happen if we added a new brand tomorrow?

It would resolve and authenticate only after Brand/Domain/auth setup. Shared profile, safety, account, and messaging code could work after membership/profile creation. Discovery, Find, Likes/Passes, compatibility, media publication, and product notifications would fail closed or remain unusable until their policies/strategies/infrastructure are configured. Hooks would correctly return not configured. The brand could be partially live in inconsistent ways unless a launch contract checks every surface.

### 12. How much backend code would we need to launch that brand using existing capabilities?

For a conventional brand that accepts existing platform semantics: one brand installer/catalogue, registry/manifest entries for desired matching surfaces and interaction policy, optional ranking/compatibility strategy, media/notification policies and templates, environment configuration, and brand contract tests. Auth, profiles, preferences, photos, likes/matches, messaging, safety, admin, and account closure should not be rewritten. A novel product semantic—such as stable daily picks—requires one reusable platform extension plus brand policy.

### 13. What prevents arbitrary future products from configuration + selective enablement?

No single capability manifest; scalar profile configuration is not enforced; Discovery embeds HookUs concepts; eligibility policy is duplicated/inconsistently sourced; Find has only a DateZA proof; notification event configuration is fragmented; media moderate-first lacks an approval path; join/rejoin lifecycle is absent; and major platform capabilities (billing, identity verification, trust reputation, realtime/media chat) do not exist.

## 25. Recommended architectural guardrails

1. **One brand capability contract.** Every production brand must declare enabled/disabled surfaces and reference its existing policy/strategy objects in one reviewable location.
2. **Deny by default.** A globally routed capability must return a stable not-configured response unless enabled, following the Hook policy precedent.
3. **No product record in a universal scope without composition.** Generic eligibility/exclusion/status code must not directly query `Hook`, `HookTonightState`, a brand option key, or another optional capability.
4. **Configuration must be authoritative.** Enabled profile fields must control accepted writes and serialized fields, not only frontend rendering.
5. **One eligibility predicate per purpose.** Define and test named viewer, visibility, reciprocal-pair, and interaction-exclusion primitives; surfaces compose them rather than restating them.
6. **Strategy must not import another product's policy.** Compatibility, Likes, Discovery, and Find should consume an explicit shared context/policy value.
7. **Surface-specific decoration.** Hook state belongs in an enabled HookUs/Hook surface serializer decorator, not the generic profile contract.
8. **Generic capability tests plus brand contract tests.** Never clone complete controller suites per brand. Run shared behavior against neutral policies and small per-brand enablement/leakage contracts.
9. **New-brand launch gate.** Verify host, sessions, profile catalogue, matching surfaces, interaction policy, media storage/visibility, provider sender readiness, notifications, safety, account closure, and every disabled route.
10. **Entitlements before premium conditionals.** Product policies may ask one shared entitlement service; payment code must not be copied into Find/Hooks/Likes.
11. **Migration compatibility stays narrow and expires deliberately.** Existing HookUs R2/email fallbacks are acceptable precedents only when exact-brand and exact-environment guarded.
12. **Date9ja remains a migration target, not an architecture template.** Extend shared typed capabilities after product/privacy decisions; do not import a second user/profile/matching architecture.

## 26. Prioritized remediation plan

### 1. Establish and test one brand capability contract

**Impact:** Highest. Prevents partial brand launches and further scattered conditionals.  
**Classification:** C/B.  
**Scope:** Reference existing auth/profile/matching/Find/Hook/media/notification/verification policies rather than replacing them. Add a reusable contract test that enumerates enabled and disabled surfaces.  
**Why first:** Every later remediation needs an authoritative home for its choice.

### 2. Remove optional Hook capability knowledge from generic Discovery/profile output

**Impact:** High privacy/API correctness.  
**Classification:** C.  
**Scope:** Make vibes/420 a HookUs-configured facet, make Hook exclusions capability-contributed, and move Hook/Hook Tonight response fields to an enabled surface decorator. Replace the HookUs location constant in generic status.  
**Evidence:** `Matching::FacetFilter`, `Matching::ExclusionsScope`, `DiscoveryController`, `ProfilesController`, `Profiles::StatusFields`.

### 3. Consolidate eligibility and interaction-policy inputs

**Impact:** High correctness across Discovery, Find, Likes, Passes, Hooks, compatibility, public profiles, matches, and chat.  
**Classification:** D/C.  
**Scope:** One discoverable viewer predicate; explicit universal versus capability exclusions; one surface policy input for location freshness/verification. Preserve existing SQL and safety semantics.  
**Why before DateZA Discovery:** Prevents the daily product from copying a third eligibility variant.

### 4. Make profile capability configuration authoritative on writes and serialization

**Impact:** High multi-brand integrity and frontend contract clarity.  
**Classification:** C.  
**Scope:** Consume existing enabled field lists in owner write/public serialization paths; add negative brand-leakage tests. Do not split the profile table or create brand controllers.  
**Evidence:** `ProfileController#profile_params`, `Profiles::CurrentProfile`, `OwnerSerializer`, `PublicSerializer`, `Profiles::Configuration`.

### 5. Build a reusable curated daily-selection layer, then configure DateZA Discovery

**Impact:** High product impact without architectural fork.  
**Classification:** E then B.  
**Scope:** Reuse shared eligibility/blocks/exclusions/serialization and lessons from `FindProfileExposure`; add persisted stable batch, daily policy/rollover, 10-profile DateZA allowance, and DateZA ranking strategy. Register DateZA only after generic and brand contract tests pass.  
**Explicit non-goal:** No DateZA-specific Discovery controller or duplicate eligibility engine.

### Follow-on work after the top five

- add join/rejoin brand-membership lifecycle;
- complete photo moderation decision operations or explicitly approve each brand's visibility policy;
- make SMS/provider readiness brand-aware;
- unify notification event/type/template registration and add dating events;
- introduce entitlements before premium limits;
- define verification portability and badge semantics; and
- build platform-wide erasure/export, trust verification, billing, and realtime/media messaging as independent shared capabilities.

## Audit evidence and verification

The audit traced production paths through `config/routes.rb`, controllers in `app/controllers/api/v1`, models in `app/models`, domain objects in `domains`, jobs in `app/jobs`, current `db/schema.rb`, brand/runtime configuration, and the test suite structure.

The architectural conclusions do not rely on product documentation alone. ADRs and architecture documents were used to compare intended boundaries with runtime behavior, notably:

- `docs/adr/0002-brand-tenancy-model.md`
- `docs/adr/0003-separate-user-identity-from-brand-profiles.md`
- `docs/adr/0007-brand-scoped-d8n-sessions.md`
- `docs/adr/0008-compose-brand-profile-capabilities.md`
- `docs/adr/0009-tenant-safe-discovery-and-matching.md`
- `docs/adr/0010-match-gated-private-messaging.md`
- `docs/adr/0017-reusable-profile-capabilities.md`
- `docs/architecture/profile-capabilities.md`
- `docs/architecture/matching.md`

A focused existing test suite covering brand resolution/isolation, HookUs and DateZA profile catalogues, reusable profile capabilities, Discovery, Find, eligibility and strategy contracts, Likes/Passes, Hook capability gating, conversations/messages, photos, generic reports/admin suspension, DateZA notifications, and account closure completed successfully: **191 runs, 1,002 assertions, 0 failures, 0 errors, 0 skips**. The first sandboxed attempt could not access the local PostgreSQL socket; the same command was rerun with approved local-database access.

No runtime code, migration, route, test, existing documentation, database data, deployment, or external system was changed by this audit. The only created artifact is this report.
