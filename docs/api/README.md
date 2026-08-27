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

Use **Authorize** with a brand-bound bearer token, then execute requests directly from the documented operations. Swagger UI is self-hosted, reads the canonical runtime contract, does not use an external validator, and does not persist authorization across page reloads. Product web applications should use the persistent browser mode below instead of persisting that bearer token themselves.

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
| Identity | Available | Phone/email + password register, login, password and login-email change, recovery, brand-bound session, identifier verification, reversible account deactivation/reactivation, and brand-membership closure. |
| Profiles | Available | Profile, configuration, options, preferences, location, publication. |
| Matching | Available | HookUs cursor Discovery, DateZA stable daily Discovery, and DateZA Find are live on shared eligibility. Both DateZA surfaces use deterministic `dateza_v1` compatibility while retaining separate persistence and budgets. |
| Messaging | Preview | Match-gated plain-text messages and history exist. Client idempotency, receipts, realtime and message media remain future work. |
| Trust | Preview | Blocking, profile/content reporting, brand-scoped report review and suspension exist. DateZA public Trust standing is not implemented. |
| Media | Available foundation | Brand-scoped direct upload, safe re-encoding, short-lived signed owner/public delivery, ordering/primary semantics, limits, deletion/purge, and audited approve/reject transitions are implemented. Provider automation, appeals, and an admin UI remain future work. |
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

### Persistent web authentication

Password registration and login support an explicit browser mode:

```json
{
  "identifier": "member@example.com",
  "password": "secret",
  "device_name": "Web",
  "session_mode": "browser"
}
```

With browser mode, the response sets the host-only HttpOnly
`d8n_web_session` cookie and contains `browser_session.csrf_token`; it does not
contain `token` or `token_type`. The frontend must send `credentials: "include"`
on registration, login, `/me`, logout, and every later cookie-authenticated API
request. Keep the CSRF token in memory and send it as `X-CSRF-Token` on every
non-GET/HEAD/OPTIONS request. After a reload, call `GET /api/v1/me`; a successful
cookie bootstrap returns the same token at `session.csrf_token`.

`GET /api/v1/me` returns 401 `session_expired` or `session_revoked` when a browser
credential reached that lifecycle state and clears it. Missing, malformed, or
wrong-brand credentials return 401 `unauthorized`. Logout is
`DELETE /api/v1/auth/session` with the CSRF header; success revokes the server
session, clears the cookie, and returns 204. A missing/invalid CSRF token returns
403 `csrf_token_invalid` without performing the mutation.

Omitting `session_mode` preserves bearer mode: the response contains `token` and
`token_type: "Bearer"`, sets no cookie, and bearer-authenticated mutations are
CSRF-exempt. Never persist that token in browser-readable storage. The two modes
share the same D8N `Session`, lifecycle checks, and brand authorization.

In production the cookie is `Secure; SameSite=None` so explicitly allowlisted
cross-site frontend/API deployments work over HTTPS. Development uses
`SameSite=Lax`: HookUs ports on `localhost` are same-site, but DateZA's
`localhost` frontend and `dateza.test` API are not. DateZA browser-session work
therefore needs a same-origin dev proxy that preserves `dateza.test` upstream (or
local HTTPS configured for secure cross-site cookies); direct CORS remains usable
for bearer mode.

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

This provisions the tenant and host mapping; it deliberately does not reuse
HookUs profiles. For a tenant-isolated synthetic DateZA population suitable for
local Discover and Find testing, run:

```sh
bin/rails dateza:seed_demo_profiles
```

The task is guarded, idempotent, and uses the repository's existing demo assets.
In the standard setup, DateZA API requests use `http://dateza.test:3000` because
`http://localhost:3000` is mapped to HookUs. CORS origin approval does not change
the request's brand.

No production DateZA domain is assumed by this repository. DateZA Find,
deterministic compatibility v1, and stable daily Discovery are implemented;
RealMe, public Trust standing, AI Matchmaker, notification UI/device enrollment,
and subscriptions/entitlements remain future work. DateZA registration creates
one `dateza.welcome` product notification after commit.

For DateZA, `GET /api/v1/discovery` returns the current Johannesburg-calendar-day
curated selection. The first request finalizes up to 10 profiles, and repeated
requests return the same persisted order. A later higher-ranked profile does not
replace an allocation member. Current shared eligibility is rechecked on every
delivery, so blocked, unpublished, closed/suspended, liked, passed, or matched
candidates are omitted without refill. The response contains no cursor and adds:

```json
{
  "profiles": [],
  "next_cursor": null,
  "selection": {
    "allocation_date": "2026-08-24",
    "daily_limit": 10,
    "count": 0,
    "finalized": true,
    "refreshes_at": "2026-08-25T00:00:00+02:00"
  }
}
```

`count` is the number currently safe to deliver; it may be below the number
originally allocated after invalidation. There is intentionally no `remaining`:
this is a finalized curated allocation, not a per-card consumption allowance.

Discovery facets and optional response fields are surface-configured. HookUs
keeps its `vibe` and `online` facets plus `hook_state` and
`hook_tonight_active` on configured Discovery and profile-detail surfaces.
DateZA instead decorates Discovery/Find/profile-detail with `opener_state`
(same values — `available`/`pending`/`hooked`/`unavailable` — same underlying
engine as `hook_state`, just labeled for its D8N Opener product name). A brand
without either capability receives neither field.

Optional product routes are globally present but authorized through the resolved
brand's D8N capability contract after authentication. Route presence therefore
does not enable a product. An active database brand and domain without a
registered production contract receives the stable 404 response
`{"error":"brand_not_configured"}` before product rate limits, domain policy or
strategy selection, resource lookup, or mutation.

For a registered production brand, capabilities intentionally disabled by its
contract retain their surface-specific 404 errors:

```text
Discovery / Likes / Passes / Matches   matching_not_configured
Find                                   find_not_configured
Conversations / Messages               messaging_not_configured
Hook                                   hook_not_configured
Hook Tonight                           hook_tonight_not_configured
D8N Opener                             opener_not_configured
```

HookUs and DateZA both enable current text conversations/messages. Hook Tonight
deactivation is deliberately exempt from the Hook Tonight capability check so a
registered production brand can clear stale or legacy availability state, but it
still requires a valid production brand contract.

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

### DateZA verification-gated interactions

DateZA deliberately uses **browse first, verify before interacting**. A member
whose current login identifier is still unverified may call `GET /api/v1/find`
and consume the normal Find exposure allowance. The server requires verification
before full profile detail, Like, Pass, match/conversation access, message
history/send, conversation initiation, or sending/replying to a D8N Opener.
Hook and Hook Tonight are not DateZA capabilities and fail earlier with their
product-specific 404 errors.

The verification source is the identifier attached to the current brand-bound
session credential. A different verified phone/email on the same D8N identity
does not unlock a session created through an unverified identifier. A blocked
request returns:

```http
HTTP/1.1 403 Forbidden
Content-Type: application/json

{"error":"identifier_verification_required"}
```

Treat this separately from `401 unauthorized`, profile/lifecycle errors, and
normal validation failures. Send the member through the existing
`POST/PATCH /api/v1/auth/verification` flow, then retry the intended action.
HookUs is not subject to this DateZA rule. Account/profile editing and safety
controls (block, unblock, and report) remain available because they are not
dating interactions.

### Hook brand capabilities

Hook and Hook Tonight are currently enabled only for HookUs. Route presence does
not imply enablement. Authenticated requests under DateZA receive:

```json
{"error":"hook_not_configured"}
```

for Hook send/inbox/reply/decline, or:

```json
{"error":"hook_tonight_not_configured"}
```

for Hook Tonight state, activation, and reciprocal discovery. Both use HTTP 404
and are evaluated before DateZA's identifier-verification interaction rule.
`DELETE /api/v1/hook_tonight` intentionally remains available to authenticated
members of any brand so legacy availability state can always be deactivated.

### D8N Opener

D8N Opener is the brand-configurable generalization of the same one-shot-opener
/ reply-unlocks-conversation engine (`Hook` model, `Hooks::SendHook` et al.) —
HookUs and DateZA share every implementation class; only the brand's policy
differs (`BrandContract::OpenerConfiguration`). DateZA enables `match.opener`
(distinct from `match.hook`, which stays HookUs-only) under its own routes:

```txt
POST   /api/v1/profiles/:profile_id/opener
GET    /api/v1/openers
POST   /api/v1/openers/:opener_id/reply
POST   /api/v1/openers/:opener_id/decline
```

Unlike HookUs's Hook, DateZA's opener policy is `catalog_required: true` — the
sender must select `opener_key` from the brand's curated catalog (`GET
/api/v1/profile/configuration` → `openers`, each `{key, text}`) rather than
write freeform text to a stranger; the server resolves and stores the catalog's
`text` server-side, and an unknown/retired key returns `422 invalid_opener`. A
brand may edit its catalog copy any time (`Profiles::CapabilityCatalog.install_opener!`)
without a data migration or rewriting history, because past sends keep their
already-resolved message. The recipient's reply remains freeform, exactly like
Hook: replying IS acceptance, and the reply becomes a normal message in the
newly unlocked Match + Conversation. Rate limiting (`hook_rate_limited`, 429,
`Retry-After`), one-opener-per-pair-ever (`already_hooked`, 409), and
block/report enforcement are all unchanged from Hook — same engine, same rules.

HookUs does not currently enable `match.opener` (it uses `match.hook` instead);
a future brand — or HookUs itself later — can enable `match.opener` with either
policy without any new engine code, purely through its brand contract.

The allowance model has two separate DateZA surfaces: Find exposes up to 10
unique profiles per Johannesburg day through `find_profile_exposures`; Discover
persists a separate curated allocation of up to 10. Calling either endpoint does
not consume or mutate the other's accounting.

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

Phone and email contact-verification codes remain valid for one hour. The
successful request, registration/session, and `/me` payloads expose the
server-authoritative `verification.expires_at` (or `null` when no usable code was
dispatched). Password-recovery and email-change codes deliberately retain their
shorter, separate security lifetimes.

Authenticated verification clients branch on stable lifecycle codes:

- `verification_code_invalid`: the current code does not match;
- `verification_code_expired`: the current challenge expired;
- `verification_code_used`: the challenge was already consumed;
- `verification_attempts_exhausted`: the challenge locked after its bounded attempts;
- `verification_resend_too_soon`: the per-identifier resend cooldown is active;
- `verification_rate_limited`: a broader verification request window is exhausted;
- `delivery_unavailable`: the configured delivery channel cannot accept the request.

Both resend throttle errors use `429` and an authoritative `Retry-After` header.
A successful verification-code request returns `resend_available_in` and
`expires_at`. Password
registration/session and `/api/v1/me` responses expose only a masked destination,
whether a usable challenge was dispatched, and the server-owned resend delay—never
the raw identifier. Signed-out password recovery keeps unknown identifiers and
wrong guesses indistinguishable; expired/used lifecycle is returned only when the
submitted secret matches the corresponding prior recovery challenge.

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

### Account deactivation, reactivation, and closure

Password change, deactivation, and closure are shared D8N ID capabilities — the
same implementation for every brand, gated only by brand policy. A client should
read `account_controls` off `GET /api/v1/me` before rendering Settings actions
rather than assuming all three are always available:

```json
{
  "account_status": "active",
  "account_controls": { "password_change": true, "deactivation": true, "deletion": true }
}
```

Deactivation is reversible and brand-scoped: it revokes this brand's sessions and
devices and removes the member from discovery/find/matching/messaging, but
leaves profile, photos, matches, and conversations untouched.

```sh
curl -i -X POST https://hookus.example.com/api/v1/account/deactivation \
  -H 'Authorization: Bearer REPLACE_WITH_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"confirmation":"deactivate"}'
```

Because deactivation revokes sessions, restoring access means proving the
password again rather than calling an authenticated "undo" endpoint. A login
attempt against a deactivated account returns `409 account_deactivated` (only
after the password has matched, so this cannot be used to enumerate account
state); reactivate with the same identifier/password shape as login:

```sh
curl -i -X POST https://hookus.example.com/api/v1/auth/password/reactivation \
  -H 'Content-Type: application/json' \
  -d '{"identifier":"+27821234567","password":"secret"}'
```

Closure (`DELETE /api/v1/me` with `{"confirmation":"close"}`) is the one-way
counterpart: it tombstones the brand membership, discards/anonymizes the profile,
ends matches, and purges media asynchronously. It never touches the D8N identity
itself or other brands' memberships — see ADR 0014.

### Correcting or changing a login email

An authenticated member whose current session was issued from an email/password
credential can replace a mistyped or outdated email without access to the old
inbox. First submit the proposed address and current password:

```sh
curl -i -X POST https://dateza.test/api/v1/auth/email/change \
  -H 'Authorization: Bearer REPLACE_WITH_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"email":"correct@example.com","current_password":"secret"}'
```

D8N keeps the old email active and sends a 10-minute, single-use code only to the
proposed address. Confirm it from the same session:

```sh
curl -i -X PATCH https://dateza.test/api/v1/auth/email/change \
  -H 'Authorization: Bearer REPLACE_WITH_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"email":"correct@example.com","code":"123456"}'
```

Success updates the existing identifier in place, marks the new address verified,
keeps the current session, and revokes other sessions backed by that password
credential. The password hash, user, memberships, profiles, and dating activity do
not move or duplicate. Malformed, unchanged, and already-owned target addresses
share the stable `email_change_unavailable` error. Phone-backed sessions cannot use
this endpoint; adding an email to a phone-only account remains a future explicit
credential-linking flow.

## Frontend Bootstrap

After authentication, a brand frontend should:

1. Call `GET /api/v1/me` to confirm the token and resolved brand.
2. Call `GET /api/v1/profile/configuration` to obtain brand-specific fields,
   input types, visibility, controlled choices, option groups, cardinality,
   limits, requiredness, and the server-owned `onboarding`/`next_step` state.
3. Read or create the profile through `GET/PATCH /api/v1/profile`.
4. Update preferences, controlled options, photos, and location through their focused endpoints.
5. Use `publication_completion` (or its backward-compatible `completion` alias)
   and activate through `POST /api/v1/profile/publication`.
6. Request discovery only after activation, then use returned public profile UUIDs for likes, passes, blocks, and profile detail.
7. Open a profile page from a public profile UUID through `GET /api/v1/profiles/:profile_id`; treat this as the source of truth so refresh, new-tab, and deep-link navigation resolve without a client-side cache.
8. Use a public match UUID with `POST /api/v1/matches/:match_id/conversation`, then list started chats through `GET /api/v1/conversations`.

Frontends should render from `profile/configuration`; they should not hardcode
HookUs or DateZA option codes as a universal D8N schema. An empty field `options`
array means the current API validates the field's shape but does not define a
closed vocabulary. New semantic capabilities still require a D8N backend
contract rather than arbitrary client fields.

The configuration is also the server-enforced scalar-field contract. A known
D8N profile field that is not listed for the resolved brand is rejected by
`PATCH /api/v1/profile` with HTTP 422 and
`{"error":"invalid_profile_fields","details":{"fields":[...]}}`. Owner and
public profile JSON omit disabled fields, including values retained on historical
rows. Stable envelope fields such as profile id, brand/status/visibility where
applicable, options, prompts, completion, and photos are not brand scalars.

For DateZA, the owner response also returns `profile_completion`: a deterministic,
post-onboarding richness score with `level`, `missing`, `suggestions`, and section
progress. It is informational only. Optional enrichment never changes onboarding,
publication, Discover, or Find eligibility. `counts` reports photos, prompts, and
interests; `location.configured`, `publication.published`, and
`verification.contact.verified` are server-authoritative. The existing `counts`
members retain their historical stored/kept-record meaning; clients needing a
renderable prompt/interest count can derive it from the returned active arrays.
Brands that have not composed a richness model return
`profile_completion: null`.

`verification.contact.verified` is the canonical profile-detail/owner contact
verification field and means at least one kept email or phone identifier is
verified. The older top-level public-profile `verified` projection remains for
backward compatibility; new detail consumers should prefer the nested field.
Neither field is RealMe, selfie, liveness, photo, age, or identity verification.

Password registration and login, plus `GET/PATCH /api/v1/profile`, return a
resumable `onboarding` state. `profile_required` starts profile creation,
`profile_incomplete` points to the next incomplete domain, `ready_to_publish`
points to publication, and `complete` enters the normal product. A suspended
profile has no next step. The API does not create empty profile rows during
identity registration; the first profile patch creates the current-brand draft.

DateZA's configuration includes required owner-only `identity_fields` for
`first_name` and `last_name`. Submit them to `PATCH /api/v1/profile` with the
relevant profile step. D8N stores them on the platform `User`, not in local
frontend state or public profile metadata. They remain self-declared until a
future verification workflow proves them. DateZA may derive a new profile's
initial `display_name` from `first_name` when `display_name` is omitted; the
concepts remain independently editable. Public profile, Find, discovery, match,
conversation, and profile-detail JSON never includes the private identity names.

The owner-scoped profile-photo API is live wherever private R2 storage is
selected. The flow is direct-to-R2: request an upload intent,
`PUT` the bytes to a short-lived presigned URL, then attach the returned
`signed_id`. D8N — never the client — allocates the object key
(`brands/<slug>/users/<id>/profiles/<uuid>/photos/<uuid>/original.<ext>`), sniffs
the real file signature, and stores an owner-only record. Retrieval is a
short-lived signed GET; delete soft-deletes and asynchronously purges the R2
object. Rails' generic Active Storage routes stay disabled; object identity and
delivery are mediated only by this API. Attached photos begin `pending_review`;
HookUs and DateZA both make them `visible` immediately and moderate
asynchronously in the background, while a brand without an explicit immediate
policy stays `hidden` until moderation makes it visible. `pending_review` means
moderation has not yet run — it is not verification or approval, and a pending
photo is never labeled as such. Public/other-user delivery positively requires a kept,
visible, successfully processed safe derivative in an allowed moderation state;
rejected media is excluded independently even if visibility is inconsistent.
Raw originals are never returned.

`GET /api/v1/profile/configuration` publishes the server-enforced brand maximum
as the photos collection's `maximum_count`; HookUs and DateZA currently configure
six. Upload intent and final attachment both check capacity, and attachment holds
the profile lock so concurrent completions cannot exceed it. `PUT
/api/v1/profile/photos/order` atomically replaces the full kept-photo order with
`{"photo_ids":[3,1,2]}`. IDs must be the complete owner-library set, unique,
same-profile/current-brand, undeleted integers. The response reassigns positions
to `0...n`.

Primary is derived, not stored: the first owner photo in `(position,id)` order has
`primary: true`; public profile arrays omit non-deliverable media and mark their
first returned photo primary. Deleting an owner primary or hiding/rejecting a
public primary therefore promotes the next valid ordered photo without a second
flag to reconcile.

Publication photo eligibility and public delivery are distinct. Every required
photo must be kept and have a completed safe derivative; rejected, failed,
deleted, or derivative-less records never count. HookUs and DateZA both require
their pending/approved placement to be visible — since both attach photos as
immediately visible, a processed `pending_review + visible` photo already
satisfies onboarding, publication, Discover, and Find; moderation continues in
the background and never blocks any of them. A brand without an explicit
immediate policy stays moderate-first: a safe `pending_review + hidden` photo
still satisfies onboarding so review latency does not block entry, but it
remains absent from every public payload until approval. Approval confirms an
already-visible immediate-policy photo (no visibility change) or, for a
moderate-first brand, changes pending media to `approved + visible`. Rejection
always changes the photo to `rejected + hidden`, can unpublish a profile that
loses its required eligible photo set, and the photo can never be delivered
again regardless of the visibility column's value.

Brand-assigned moderators apply the terminal decision through `PATCH
/api/v1/admin/profile_photos/:photo_uuid` with `{"status":"approved"}` or
`{"status":"rejected"}`. Same-decision retries are idempotent; an opposite
terminal decision returns `409 profile_photo_moderation_conflict`. Real
transitions are audited with actor, brand, opaque photo/profile IDs, decision,
timestamp, and a bounded server reason code—never bytes, keys, URLs, or notes.
Provider automation, appeals, richer reason taxonomies, and admin UI remain open.
When R2 is disabled the owner endpoints return `404`.

Text messaging is live for HookUs and DateZA after an active match. Use
`GET /api/v1/conversations/:conversation_id/messages` for history and
`POST /api/v1/conversations/:conversation_id/messages` to send; both paths
recheck active-match, participant, brand, account, and block access.

## Blocking

`POST /api/v1/profiles/:profile_id/block` creates a directional block idempotently. Either block direction removes both profiles from each other's discovery, interaction, match-list, and conversation surfaces. Creating a block soft-deletes existing likes in both directions and ends an active match.

`DELETE /api/v1/profiles/:profile_id/block` removes only the current profile's outgoing block. It is idempotent and returns `204` for absent, unknown, cross-brand, self, and soft-deleted targets without revealing whether the target exists. Unblocking permits future eligible interaction but never restores earlier likes, reactivates an ended match, or restores access to its ended conversation/history.

## Reporting

`POST /api/v1/reports` is the single shared D8N TRUST reporting endpoint for every
brand and every reportable subject: `{"target_type": "profile"|"message"|
"profile_media"|"hook"|"conversation", "target_id": "...", "reason": "...",
"details": "...", "block": false}`. The reporter is always the authenticated
caller; the responsible profile (message/Hook sender, photo owner, other
conversation participant) is always derived server-side and can never be
supplied by the client. Unknown, inaccessible, self-owned, and cross-brand
targets are indistinguishable — a neutral `404 target_unavailable` — so nothing
about a target's existence is enumerable. Filing a report never blocks,
unmatches, or hides the conversation; those remain separate, explicit actions
(optionally combined via `block: true`, which blocks the responsible profile
after the report is filed).

A **message report** (`target_type: "message"`) requires the reporter to be a
participant of the message's conversation and captures only that one message
(sender, conversation, body, timestamp) as evidence — never surrounding
history. A **conversation report** (`target_type: "conversation"`) is for
pattern-level harm (repeated harassment, a scam pattern, escalating coercion)
that no single message captures, and instead snapshots a bounded window of the
most recent messages (currently 20) that existed at report time — never the
entire history. Both work identically regardless of whether the conversation
originated from a Match or from an accepted D8N Opener (Hook reply), and both
remain reportable after the other participant is blocked, suspended, or
closes their account, because report evidence is retained safety data (see
ADR 0018). Every reportable subject shares one reason taxonomy and one report
lifecycle — there is no message- or conversation-specific moderation system.

```sh
curl -X POST https://hookus.example.com/api/v1/reports \
  -H 'Authorization: Bearer REPLACE_WITH_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"target_type":"conversation","target_id":"CONVERSATION_UUID","reason":"harassment"}'
```

## Profile Detail

`GET /api/v1/profiles/:profile_id` returns one member's safe public profile from
its public UUID (the `id` discovery already returns), as `{ "profile": { … } }`.
It is the authoritative, refreshable source for a profile page: a browser
refresh, a new tab, and a deep link all resolve independently, so the frontend
must not depend on a client-side Discover cache for correctness.

The body extends the same safe public shape as a discovery entry — public id,
display name, derived age, bio, coarse location, work/education, languages,
lifestyle fields, deterministically ordered safe photos, and public option groups
— with prompts, categorized interests, and explicit
`verification.contact.verified`. DateZA detail also includes its existing
compatibility payload; calculating it for detail does not change eligibility or
matching behavior. No email, phone, credentials, internal ids, coordinates, raw
media, storage keys, provider data, or identity-verification assertion is exposed.

DateZA keeps `company_name`, `has_children`, `wants_children`, `religion`, and
`religion_importance` owner-only. `physical_affection` and
`chemistry_importance` are matches-only. Public work presentation may use
`occupation`, `job_title`, `school_or_institution`, and `education_level`.

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
