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

The JSON URL can be imported directly into Postman, Insomnia, Bruno, Swagger Editor, or an OpenAPI code generator. For local development, start Rails and import `http://localhost:3000/api/v1/openapi.json`; configure requests to use the required brand host as described below.

Every task that changes an API route, input, output, authentication rule, status code, or stable error code must update `openapi.yaml`, the integration guidance, and endpoint tests in the same change. `OpenapiContractTest` enforces route coverage, unique operation IDs, valid local references, and runtime publication.

## Brand And Tenant Context

D8N resolves the brand from the request host. Client applications do not send `brand_id`.

```txt
hookus.example.com  -> HookUs
date9ja.example.com -> Date9ja, once its production strategy is approved
```

In local tests, set the host explicitly:

```sh
curl --resolve hookus.test:3000:127.0.0.1 \
  http://hookus.test:3000/api/v1/health
```

Authentication tokens are brand-bound. A token issued through a HookUs host cannot authenticate a Date9ja request. Each frontend should configure one brand API origin and must not allow end users to override the host or tenant context.

## Authentication Flow

Discover the implemented login methods enabled for the request host:

```txt
GET /api/v1/auth/methods
```

Only methods returned by this endpoint should be presented as usable. Planned or
configured methods are withheld until their server-side implementation is
available. HookUs currently exposes `phone_password` and `email_password`;
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
2. Call `GET /api/v1/profile/configuration` to obtain brand-specific fields, option groups, cardinality, limits, and requiredness.
3. Read or create the profile through `GET/PATCH /api/v1/profile`.
4. Update preferences, controlled options, photos, and location through their focused endpoints.
5. Use the profile `completion` object and activate through `POST /api/v1/profile/publication`.
6. Request discovery only after activation, then use returned public profile UUIDs for likes, passes, and blocks.
7. Use a public match UUID with `POST /api/v1/matches/:match_id/conversation`, then list started chats through `GET /api/v1/conversations`.

Frontends should render from `profile/configuration`; they should not hardcode HookUs option codes as a universal D8N schema. New semantic capabilities still require a D8N backend contract rather than arbitrary client fields.

Password registration and login, plus `GET/PATCH /api/v1/profile`, return a
resumable `onboarding` state. `profile_required` starts profile creation,
`profile_incomplete` points to the next incomplete domain, `ready_to_publish`
points to publication, and `complete` enters the normal product. A suspended
profile has no next step. The API does not create empty profile rows during
identity registration; the first profile patch creates the current-brand draft.

Phase 5 Slice 1 exposes conversation metadata only. No frontend should simulate or persist chat messages against D8N until the documented message-content endpoints ship with block/report and privacy controls.

## Blocking

`POST /api/v1/profiles/:profile_id/block` creates a directional block idempotently. Either block direction removes both profiles from each other's discovery, interaction, match-list, and conversation surfaces. Creating a block soft-deletes existing likes in both directions and ends an active match.

`DELETE /api/v1/profiles/:profile_id/block` removes only the current profile's outgoing block. It is idempotent and returns `204` for absent, unknown, cross-brand, self, and soft-deleted targets without revealing whether the target exists. Unblocking permits future eligible interaction but never restores earlier likes or reactivates an ended match. Existing conversation metadata may become visible again under the ended-match read-only history policy; no message-content API exists yet.

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
