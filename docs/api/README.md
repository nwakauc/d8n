# D8N API Integration Guide

## Canonical Contract

The canonical machine-readable API contract is [`openapi.yaml`](openapi.yaml).

For a step-by-step local workflow using Swagger UI, Apidog, or the HookUs
frontend, see [`LOCAL_TESTING.md`](LOCAL_TESTING.md).

When D8N is running, the same contract is available as JSON:

```txt
GET /api/v1/openapi.json
```

Interactive Swagger UI is available at:

```txt
GET /api/docs
```

Use **Authorize** with a brand-bound bearer token, then execute requests directly from the documented operations. Swagger UI is self-hosted, reads the canonical runtime contract, does not use an external validator, and does not persist authorization across page reloads.

The repository contract is authoritative for the deployed commit. Clients may generate types or API clients from it, but should keep generated output in their own repositories.

`GET /up` is the Rails boot/liveness probe. `GET /api/v1/health` is the public
readiness probe: it returns `200` only when the primary and Solid Queue PostgreSQL
connections respond, otherwise a bounded `503` without connection details. The
readiness route does not require a recognized brand host.

The JSON URL can be imported directly into Postman, Insomnia, Bruno, Swagger Editor, or an OpenAPI code generator. For local development, start Rails and import `http://localhost:3000/api/v1/openapi.json`; configure requests to use the required brand host as described below.

Every task that changes an API route, input, output, authentication rule, status code, or stable error code must update `openapi.yaml`, the integration guidance, and endpoint tests in the same change. `OpenapiContractTest` enforces route coverage, unique operation IDs, valid local references, and runtime publication.

## Implementation Status

Use this to plan frontend integration. It mirrors the machine-readable status at
the API root (`GET /`) and the summary at the top of `openapi.yaml`.

| Domain | Status | Notes |
| --- | --- | --- |
| Identity | Available | Phone/email + password register, login, password change/recovery, brand-bound session, identifier verification. |
| Profiles | Available | Profile, configuration, options, preferences, location, publication. |
| Matching | Available | HookUs Discovery and DateZA Find are live on shared eligibility. DateZA Find includes deterministic `dateza_v1` compatibility; DateZA Discovery remains unimplemented. |
| Messaging | Preview | Match-gated plain-text messages and history exist. Client idempotency, receipts, realtime and message media remain future work. |
| Trust | Preview | Blocking, profile/content reporting, brand-scoped report review and suspension exist. DateZA public Trust standing is not implemented. |
| Media | Preview | Owner-scoped profile-photo upload/retrieval is live on private R2 (direct-to-R2 intent → attach → short-lived signed GET → delete/purge). Public/other-user delivery, re-encode, EXIF removal, and moderation enforcement remain gated. Endpoints require R2, so they return `404` when R2 is disabled. |
| Verification | Planned | RealMe identity/selfie verification has no endpoints yet. Identifier verification is an Identity capability, not RealMe. |
| Admin | Preview | Brand-scoped report review and suspension endpoints exist; stronger admin auth/RBAC and a complete admin product remain gated. |
| Product Notifications | Available | Brand-scoped inbox/read API and DateZA registration welcome email. Device storage/push boundary exists; device enrollment API and production push provider are deferred. Identity challenge delivery remains separate. |
| Billing / Analytics | Planned | No consumer product endpoints yet. |

Every path in `openapi.yaml` is implemented; the "Preview" and "In development"
notes above describe deliberate scope limits, not missing documentation. Do not
build UI against a domain marked Planned — those endpoints do not exist yet.

## Brand And Tenant Context

D8N resolves the brand from the request host. Client applications do not send `brand_id`.

```txt
hookus.example.com  -> HookUs
date9ja.example.com -> Date9ja, once its production strategy is approved
dateza.test         -> DateZA development tenant after local provisioning
```

In local tests, set the host explicitly:

```sh
curl --resolve hookus.test:3000:127.0.0.1 \
  http://hookus.test:3000/api/v1/health
```

Authentication tokens are brand-bound. A token issued through HookUs cannot
authenticate DateZA (or another brand), and a DateZA token cannot authenticate
HookUs. Each frontend should configure one brand API origin and must not allow
end users to override the host or tenant context.

### DateZA tenant foundation

DateZA is provisioned as the first-class brand named `DateZA` with slug `dateza`.
For local development, run:

```sh
bin/rails brands:seed_dateza_dev
```

This creates or refreshes the DateZA brand, its v1 shared-capability profile
catalog, phone/email password authentication policy, and the `dateza.test` host
mapping. Override only the development host when needed:

```sh
DATEZA_DEV_HOST=my-dateza.test bin/rails brands:seed_dateza_dev
```

No production DateZA domain is assumed by this repository. DateZA Find and
deterministic compatibility v1 are implemented, while daily Discovery 10,
RealMe, public Trust standing, AI Matchmaker, notification UI/device enrollment,
and subscriptions/entitlements remain future work. DateZA registration now creates
one `dateza.welcome` product notification after commit. `GET /api/v1/discovery` therefore still returns
`matching_not_configured` for DateZA.

### Product notifications

The authenticated polling-first inbox is:

```txt
GET   /api/v1/notifications
PATCH /api/v1/notifications/:id/read
POST  /api/v1/notifications/read_all
```

All three endpoints use the host-resolved brand and brand-bound bearer session.
Clients never send a brand id. The list contains stable semantic `type` values plus
presentation-safe server copy; it never exposes email addresses, device tokens,
provider ids, or delivery failures. DateZA registration currently implements only
`dateza.welcome`. Authentication verification/recovery codes remain Identity
challenges and do not appear in this inbox.

### DateZA Find

Authenticated DateZA members use:

```txt
GET /api/v1/find
```

Optional narrowing filters are `min_age`, `max_age`, `max_distance_km`, and
`relationship_intent`. `limit` is 1–10. The opaque `next_cursor` is bound to the
DateZA membership and exact filter set; never construct or modify it client-side.

The server records a durable exposure the first time a unique candidate is
returned during the current Africa/Johannesburg day. Reloading, replaying from
another client, opening profile detail, liking, or passing does not create an
additional exposure. The response's `allowance` object is authoritative:

```json
{
  "limit": 10,
  "used": 7,
  "remaining": 3,
  "exhausted": false,
  "resets_at": "2026-08-22T00:00:00+02:00"
}
```

Each Find profile also has a `compatibility` property. It is either null when
less than 35% of the versioned weighted inputs are meaningfully comparable, or:

```json
{
  "score": 87,
  "confidence": 0.82,
  "confidence_level": "high",
  "version": "dateza_v1",
  "reasons": ["shared_long_term_intent", "compatible_family_plans"]
}
```

Treat the score as pair-specific, not as a property of the candidate. Map only
the documented reason codes to client-localized copy. Compatibility calculation
does not create a Find exposure and must not be used as Trust, safety, RealMe, or
popularity state. See [`../dateza/COMPATIBILITY_V1.md`](../dateza/COMPATIBILITY_V1.md).

Find returns only safe public profile data. Exact coordinates, owner-only
answers, moderation/risk state, raw media, and other-brand profiles are absent.
The generic HTTP throttle is only abuse protection; it does not implement or
replace the exposure allowance.

## Authentication Flow

Discover the implemented login methods enabled for the request host:

```txt
GET /api/v1/auth/methods
```

Only methods returned by this endpoint should be presented as usable. Planned or
configured methods are withheld until their server-side implementation is
available. HookUs and DateZA currently expose `phone_password` and `email_password`;
Google remains behind ADR 0012's implementation gate.

Register immediately with either a phone number or email address:

```sh
curl -i -X POST http://localhost:3000/api/v1/auth/password/register \
  -H 'Content-Type: application/json' \
  -d '{"identifier":"+27821234567","password":"secret","device_name":"Local Web"}'
```

The response issues a session immediately and reports `identifier.verified` as
`false`. Registration proves knowledge of the new D8N password, not control of
the supplied phone number or email inbox. Verification and recovery are later,
separate capabilities. It also returns an `onboarding` object. Follow its
`next_step` value instead of assuming every brand has the same signup sequence.

Return with the same phone/email and password:

```sh
curl -i -X POST http://localhost:3000/api/v1/auth/password/login \
  -H 'Content-Type: application/json' \
  -d '{"identifier":"+27821234567","password":"secret","device_name":"Local Web"}'
```

Password login never silently joins an existing D8N identity to another brand.
Registration is the explicit current-brand join for a new identity; a future
existing-identity brand-join flow remains separate.

After signup, an authenticated user may optionally verify the phone or email
already attached to the account:

```sh
curl -i -X POST https://hookus.example.com/api/v1/auth/verification \
  -H 'Authorization: Bearer REPLACE_WITH_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"kind":"phone"}'
```

Verify the delivered code using the same existing session:

```sh
curl -i -X PATCH https://hookus.example.com/api/v1/auth/verification \
  -H 'Authorization: Bearer REPLACE_WITH_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"kind":"phone","code":"123456"}'
```

Verification never creates an account, credential, membership, or session and
never blocks normal onboarding. The former unauthenticated phone-OTP login routes
have been removed; returning users log in with phone/email and password.

Use the existing token on protected endpoints:

```sh
curl https://hookus.example.com/api/v1/me \
  -H 'Authorization: Bearer REPLACE_WITH_TOKEN'
```

The verification request response is intentionally generic. Test and development
codes come from configured delivery adapters; production APIs never return codes.

A signed-in user may change the password used by the current password-backed
session. The current password is checked in the same request, which provides the
required fresh reauthentication:

```sh
curl -i -X PATCH https://hookus.example.com/api/v1/auth/password \
  -H 'Authorization: Bearer REPLACE_WITH_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"current_password":"secret","password":"new-secret","password_confirmation":"new-secret"}'
```

On success the current session remains valid and other active sessions issued
from that password credential are revoked. This settings flow is deliberately
separate from unauthenticated phone/email account recovery, which is not yet an
available API.

## Frontend Bootstrap

After authentication, a brand frontend should:

1. Call `GET /api/v1/me` to confirm the token and resolved brand.
2. Call `GET /api/v1/profile/configuration` to obtain brand-specific fields,
   input types, visibility, controlled choices, option groups, cardinality,
   limits, requiredness, and the server-owned `onboarding`/`next_step` state.
3. Read or create the profile through `GET/PATCH /api/v1/profile`.
4. Update preferences, controlled options, photos, and location through their focused endpoints.
5. Use the profile `completion` object and activate through `POST /api/v1/profile/publication`.
6. Request discovery only after activation, then use returned public profile UUIDs for likes, passes, blocks, and profile detail.
7. Open a profile page from a public profile UUID through `GET /api/v1/profiles/:profile_id`; treat this as the source of truth so refresh, new-tab, and deep-link navigation resolve without a client-side cache.
8. Use a public match UUID with `POST /api/v1/matches/:match_id/conversation`, then list started chats through `GET /api/v1/conversations`.

Frontends should render from `profile/configuration`; they should not hardcode
HookUs or DateZA option codes as a universal D8N schema. An empty field `options`
array means the current API validates the field's shape but does not define a
closed vocabulary. New semantic capabilities still require a D8N backend
contract rather than arbitrary client fields.

Password registration and login, plus `GET/PATCH /api/v1/profile`, return a
resumable `onboarding` state. `profile_required` starts profile creation,
`profile_incomplete` points to the next incomplete domain, `ready_to_publish`
points to publication, and `complete` enters the normal product. A suspended
profile has no next step. The API does not create empty profile rows during
identity registration; the first profile patch creates the current-brand draft.

The owner-scoped profile-photo API is live wherever private R2 storage is
selected (staging today). The flow is direct-to-R2: request an upload intent,
`PUT` the bytes to a short-lived presigned URL, then attach the returned
`signed_id`. D8N — never the client — allocates the object key
(`brands/<slug>/users/<id>/profiles/<uuid>/photos/<uuid>/original.<ext>`), sniffs
the real file signature, and stores an owner-only record. Retrieval is a
short-lived signed GET; delete soft-deletes and asynchronously purges the R2
object. Rails' generic Active Storage routes stay disabled; object identity and
delivery are mediated only by this API. Attached photos begin `pending_review`;
HookUs makes them `visible` immediately and moderates asynchronously, while
brands without an explicit policy stay `hidden` until moderated. Still gated per
ADR 0011: public/other-user delivery, safe re-encode, EXIF/metadata stripping,
and moderation enforcement. When R2 is disabled the endpoints return `404`.

Phase 5 Slice 1 exposes conversation metadata only. No frontend should simulate or persist chat messages against D8N until the documented message-content endpoints ship with block/report and privacy controls.

## Blocking

`POST /api/v1/profiles/:profile_id/block` creates a directional block idempotently. Either block direction removes both profiles from each other's discovery, interaction, match-list, and conversation surfaces. Creating a block soft-deletes existing likes in both directions and ends an active match.

`DELETE /api/v1/profiles/:profile_id/block` removes only the current profile's outgoing block. It is idempotent and returns `204` for absent, unknown, cross-brand, self, and soft-deleted targets without revealing whether the target exists. Unblocking permits future eligible interaction but never restores earlier likes or reactivates an ended match. Existing conversation metadata may become visible again under the ended-match read-only history policy; no message-content API exists yet.

## Profile Detail

`GET /api/v1/profiles/:profile_id` returns one member's safe public profile from
its public UUID (the `id` discovery already returns), as `{ "profile": { … } }`.
It is the authoritative, refreshable source for a profile page: a browser
refresh, a new tab, and a deep link all resolve independently, so the frontend
must not depend on a client-side Discover cache for correctness.

The body is the same safe public shape as a discovery entry — public id, display
name, derived age, bio, coarse location, occupation, gender, height/body-type,
languages, lifestyle flags, deterministically ordered safe photos, and public
option groups — minus the ranking-only `compatibility` payload. No email, phone,
credentials, internal ids, coordinates, raw media, or storage keys are exposed.

Availability enforces the same fundamental safety rules as discovery (brand
isolation, active/visible lifecycle, suspension, closure, discard, and blocks in
either direction) but deliberately drops the reciprocal age/gender/distance
ranking, so a profile reachable from Discover keeps resolving even after ranking
or dating preferences change. It requires an active, discoverable caller (`403`
`discoverable_profile_required` otherwise). Every unavailable case — unknown,
cross-brand, hidden, inactive, suspended, closed, discarded, or blocked either
way — returns a single neutral `404` `profile_unavailable` and never reveals why.

## Pagination

Discovery and match-list cursors are opaque, signed, brand-bound values. Send `next_cursor` back unchanged as `cursor`. Do not decode it, persist assumptions about its contents, or reuse it across brands.

```sh
curl 'https://hookus.example.com/api/v1/discovery?limit=20&cursor=OPAQUE_CURSOR' \
  -H 'Authorization: Bearer REPLACE_WITH_TOKEN'
```

## Privacy Boundaries

- Public profile IDs are UUIDs. Internal user/profile IDs are not dating-profile identifiers.
- Public discovery returns derived age, never birthdate.
- Precise coordinates are write-only through the profile-location API and are never returned.
- Compatibility reasons are strategy-owned bounded codes. HookUs currently returns `shared_intent`, `similar_vibe`, and `mutual_age_fit` only.
- Date9ja production discovery remains disabled until its migration, matching, and sensitive-data decisions are approved.

## Errors And Retries

Errors use a stable machine-readable `error` code and may include field-level `details`. Clients should branch on the code, not English text.

- `401 unauthorized`: token missing, invalid, expired, revoked, or for another brand.
- `403`: authenticated account lacks the required profile/membership/lifecycle state.
- `404`: resource unavailable, cross-brand, or matching is intentionally not configured.
- `409`: an interaction conflicts with current profile state.
- `422`: invalid input, limit, cursor, or incomplete profile.
- `429 rate_limited`: honor the `Retry-After` header when present.

`POST` like, pass, and block operations are idempotent. Unblock is also idempotent. OTP verification and profile mutations should only be retried according to the documented status and error code.

## Confirming The Contract

Run the route-to-OpenAPI contract test:

```sh
bin/rails test test/contracts/openapi_contract_test.rb
```

Run the request tests for actual endpoint behavior:

```sh
bin/rails test test/controllers/api/v1
```

The contract test fails when a Rails `/api/v1` route is undocumented, a documented operation has no route, operation IDs collide, or a local schema reference is broken.
