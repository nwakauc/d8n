# D8N Platform Capabilities and Brand Composition

## Purpose

D8N is one modular dating platform. Capabilities belong to D8N; brands consume
configured capabilities and surfaces. A frontend label such as **Discover**,
**Find**, **Explore**, or **For You** does not create a separate backend engine.

The production composition source is `D8n::Platform::BrandRegistry`. It resolves
one immutable `D8n::Platform::BrandContract` for the request brand. The contract
references focused domain policies, strategies, catalogues, decorators, and
provider configuration; it does not replace those implementations or act as a
plugin framework.

## Canonical namespaces

The capability catalogue uses stable platform-owned keys. Brand slugs are not
valid capability namespaces.

```text
D8N ID        id.*          identity, credentials, memberships, sessions, lifecycle
D8N Profile   profile.*     onboarding, fields, options, preferences, prompts, media relation
D8N Discovery discovery.*   candidate surfaces, facets, exposure, cursors, decoration
D8N Verify    verify.*      contact ownership and future identity verification levels
D8N Match     match.*       likes, passes, compatibility, matches, Hooks
D8N Chat      chat.*        conversations, text messages, future realtime/voice/video
D8N Trust     trust.*       blocks, reports, enforcement, future reputation/fraud signals
D8N Media     media.*       private upload, processing, delivery, visibility policy
D8N Notify    notify.*      events, inbox records, email/SMS/push delivery plans
D8N Pay       pay.*         future plans, entitlements, subscriptions, payments
D8N AI        ai.*          future matchmaker and assistants
D8N Insights  insights.*    future product, safety, and marketplace intelligence
D8N Admin     admin.*       brand-scoped and network operations
```

`D8n::Platform::Catalog` records whether each feature is available, partial, or
planned and names its current implementation. Planned catalogue entries are not
enableable by a brand contract.

## Brand access flow

```text
request host
  -> resolved Brand
  -> D8n::Platform::BrandRegistry
  -> immutable BrandContract
  -> capability/surface authorization
  -> shared domain implementation
  -> configured policy/strategy
  -> optional surface decorators
  -> brand frontend presentation
```

API routes may exist globally. Route presence is not product enablement.
`D8n::Platform::CapabilityAccess` denies an unconfigured capability before
resource lookup, product limits, or mutation and returns the configured stable
error, such as `matching_not_configured`, `find_not_configured`,
`hook_not_configured`, or `messaging_not_configured`.

Unknown brands inherit no HookUs or DateZA defaults. Authentication still runs
before product capability authorization, so an unavailable feature does not
become an authentication oracle.

## Discovery surfaces

`D8n::Platform::DiscoverySurface` composes a use of the shared candidate engine.
A surface may select:

- delivery type (`feed`, `browse`, or `restricted_pool` today);
- eligibility policy;
- ranking or compatibility strategy;
- configured facets;
- capability-specific exclusion contributors;
- bulk response decorators;
- allocation policy; and
- stable unavailable error.

HookUs currently composes `discovery.for_you`, `discovery.new_here`, and
`discovery.hook_tonight`. Its vibes facet, live-Hook exclusion, Hook state, and
Hook Tonight state are contributed by those HookUs surfaces; they are not
universal Discovery concepts.

DateZA composes two independent surfaces. `discovery.find` remains a browse
surface with its existing ten-per-Johannesburg-day exposure policy.
`discovery.curated_daily` is the default `daily_batch` surface for
`GET /api/v1/discovery`; it uses the reusable stable-daily allocation policy
(limit 10, `Africa/Johannesburg`, midnight rollover) and the configured
`dateza_v1` strategy. The same policy object supports another limit, timezone,
or local rollover hour without changing the allocation engine.

Stable daily allocation persists one allocation per brand membership, surface,
and local allocation date, plus ordered candidate membership rows. The member
row is locked during first creation and database uniqueness independently guards
the allocation identity, candidate identity, and position. Allocation is not
exposure: returning the batch does not consume candidates or DateZA Find's
ledger. The list is never reranked or routinely refilled during its period.

Delivery re-applies the surface's shared eligibility and exclusion pipeline.
Candidates that become blocked, unpublished, closed/suspended, cross-tenant, or
excluded by Like, Pass, or active Match are filtered from the response; the
persisted allocation remains unchanged and may be smaller until rollover. This
filter-only behavior prioritizes safety without allowing ordinary ranking changes
to make the curated batch unstable.

Frontend navigation names and presentation are outside the capability key. A
future brand can call a configured D8N Discovery surface “Explore” without a new
controller, candidate engine, or brand namespace.

## Optional capability composition

Universal matching exclusions contain only shared Like, Pass, and active-Match
state. An enabled surface may add exclusions such as live outgoing Hooks through
a small contributor.

Generic profile/status serializers contain reusable platform state. Optional
product fields are bulk-computed by configured response decorators and are added
only when both the brand and current surface enable them. A generic serializer
must not accumulate nullable fields for every future product.

## Profile field authority

`brand.profile_completion_requirements` is the shared source used by
`Profiles::Configuration` and `Profiles::FieldPolicy`.

- `GET /api/v1/profile/configuration` advertises enabled brand scalar fields.
- `PATCH /api/v1/profile` rejects known D8N scalar fields disabled for that brand
  with `invalid_profile_fields` (422).
- owner and public serializers omit disabled scalar fields, including values on
  historical rows;
- audience visibility remains a second independent condition;
- stable envelope fields, controlled options, prompts, completion, and photos
  retain their focused platform contracts; and
- shared storage and controllers remain unchanged.

HookUs currently preserves its broad legacy scalar catalogue. DateZA explicitly
enables its smaller required and optional field set. Neither brand owns a profile
table, onboarding engine, or serializer fork.

## Engineering guardrails

Before adding brand production code, classify the requirement:

- **A — Leave alone:** the shared capability already fits.
- **B — Configure:** enable or configure an existing capability/surface.
- **C — Extract:** reusable behavior is trapped inside product-specific code.
- **D — Consolidate:** parallel implementations duplicate a capability.
- **E — Build platform capability:** the capability genuinely does not exist.

Do not mistake B for E. Brand-specific code is appropriate for catalogues,
copy/templates, policy values, ranking strategies, and genuinely unique product
semantics. It is not appropriate for cloned identity, onboarding, eligibility,
matching, messaging, media, safety, or notification engines.

Every production brand should have small contract/isolation tests proving its
enabled features, surfaces, policies, stable disabled responses, and absence of
optional cross-brand response fields. Shared behavior remains covered by generic
capability tests.
