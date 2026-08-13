# ADR 0012: Add Password And Google Authentication Alongside Phone OTP

## Status

Accepted through Phase 2 Slice 2 on 2026-08-13. The Rodauth integration proof,
dedicated brand authentication policy, and zero-friction phone/email password
registration and login are approved. Recovery, identifier verification,
credential linking, brand joining, and Google remain behind their documented
slice and human gates.

## Context

D8N currently implements phone OTP as both registration and login. The intended
HookUs product is broader:

- a person may register with a phone number and password;
- a person may register with an email address and password;
- a person may choose phone OTP instead of a password when the brand offers it;
- a person may choose Google when the brand offers it;
- after explicit linking, the same D8N identity may sign in with any of its
  password credentials;
- every login still enters one resolved brand and issues a brand-bound D8N
  session.

Date9ja should support phone/password and email/password on the shared D8N auth
architecture. Importing existing Date9ja password hashes remains a separate
migration decision: source algorithms, reset requirements, and reconciliation
must be inventoried before any production migration.

The schema anticipated multiple strategies, but only phone OTP is implemented.
`Credential` currently has no dedicated password digest, lockout, reset-token, or
confirmation storage. Renaming an enum does not by itself integrate Rodauth with
these records.

## Decision

### Registration, Login, Brand Join, And Credential Linking Are Distinct

The API must not overload one endpoint with four different security operations.

- **Register** creates a new D8N identity, current-brand membership, password
  credential, and session immediately after accepting the current brand's signup
  terms. Identifier control may be verified later.
- **Login** authenticates an existing credential and may issue a session only for
  an existing active membership in the resolved brand.
- **Join brand** lets an authenticated existing D8N identity explicitly create a
  membership in another brand after that brand's consent/onboarding step. Login
  alone must not silently enroll the user in a new dating brand.
- **Link credential** adds another verified login method to the currently
  authenticated identity after recent reauthentication.

Public failures remain generic so signup and login cannot be used to enumerate
whether a phone, email, Google identity, user, or brand membership already exists.

### One Password Strategy Uses Either A Phone Or Email Identifier

Password authentication is one credential strategy, not separate implementations
for phone and email. A password credential attaches to exactly one
`IdentityIdentifier`, whose kind determines phone or email normalization and the
verification/recovery channel.

`Credential#kind: :email_password` may be renamed to `:password` while preserving
its stored integer value, but the matching `AuthAttempt` vocabulary and every
serializer/query must change in the same reviewed slice. No deployed or imported
row may be reinterpreted without a data audit.

Password digests, reset secrets, and lockout state must use dedicated
security-owned storage designed for Rodauth integration. They must not be placed
in general-purpose JSON metadata. Plaintext passwords and reset tokens are never
stored or logged.

### Registration Is Immediate; Verification Remains Truthful

Phone/password and email/password registration do not require an OTP or email
challenge before the account can enter the product. The identifier and password
credential are created with `verified_at: nil`; successful password login proves
knowledge of the D8N password, not control of the phone number or email inbox.

The platform must never stamp `verified_at` merely because an identifier was
provided. Later verification challenges are single-use, expiring,
attempt-limited, rate-limited, and purpose-bound. Only successful control proof
sets `verified_at`.

Unverified users may onboard, create their current-brand profile, and use normal
password authentication. Password reset through an identifier, public
verification badges, sensitive trust actions, credential linking, and any other
control-dependent capability require actual verification. Clients should nudge
verification without representing an unverified identifier as trusted.

An unverified identifier still occupies the platform-wide unique identifier.
Future verified recovery must let the genuine controller recover that existing
identity safely; it must not create or merge a second user automatically.

Google's verified provider subject proves control of that Google credential. A
Google email claim is not permission to attach Google to an existing D8N user
that happens to have the same email.

A Google-created identity does not receive a D8N password automatically. The user
may add phone/password or email/password later through the verified linking flow.

### Rodauth Provides Password Security Mechanics Behind D8N Boundaries

Rodauth/Rodauth-Rails remains the preferred password engine from ADR 0005, subject
to an integration spike against the installed Rails, Rack, and database versions.
The spike must prove the exact table adapter and enabled features before an API
schema or production migration is accepted.

D8N owns the public JSON contract, host-resolved brand context, `User`,
`BrandMembership`, credentials, lifecycle policy, security events, and bearer
sessions. Rodauth must not create a parallel consumer identity or make its cookie,
JWT, or session table the API authorization source of truth.

On successful authentication, D8N rechecks the user, credential, identifier, and
current brand membership, then issues the existing `Session` through
`Session.issue!`. Password verification success alone never bypasses those
lifecycle checks.

### Google Is First, But Provider Identity Is Explicit

The first OAuth/OIDC provider is Google. D8N validates the authorization response
server-side, including state, redirect target, issuer/audience, expiry, and nonce
or PKCE requirements appropriate to the final web/mobile flow. The callback must
not trust a client-submitted provider UID or email as proof.

Provider and immutable provider subject form the unique external identity. They
must be represented unambiguously—either with dedicated constrained columns or a
canonical provider-qualified value—and protected by a database uniqueness
constraint. Tokens are minimized, encrypted if retention is required, never
logged, and not retained when D8N does not need ongoing Google API access.

Adding another provider later may reuse this small mapping boundary, but this ADR
does not introduce a speculative universal provider framework.

### Auth Availability Is Brand Policy, Not Profile Configuration

Each brand has a dedicated, validated authentication policy with an allow-list of
supported methods. It follows the validation style of profile requirements but is
not stored inside `profile_requirements`; authentication and profile completion
have separate ownership and review risk.

An unauthenticated host-resolved endpoint may return the current brand's offered
methods so HookUs and Date9ja clients can render supported choices. This is
presentation capability, not authorization: every register, login, link, reset,
and callback path independently rechecks that the method is enabled.

The approved initial choices are:

- HookUs: phone/password and email/password now; Google later. Phone OTP is
  reserved for later verification/recovery and is not required for registration;
- Date9ja: phone/password and email/password, with imported-password behavior
  deferred to the migration inventory;
- other brands: deny methods until explicitly configured.

### Linking Requires Verification And Recent Reauthentication

An authenticated session by itself is insufficient to add a durable login method.
The user must recently reauthenticate an existing active credential and prove
control of the new phone, email, or Google subject.

If the new identifier already belongs to another D8N `User`, linking is denied and
no records move automatically. Account merging is a future support-assisted,
audited workflow; it must never move profiles, memberships, matches, messages,
photos, or trust history as a side effect of signup or OAuth callback.

Password changes, resets, credential disabling, and suspicious linking revoke the
affected sessions according to explicit policy. Self-service removal is deferred
until D8N can prove the user will retain at least one usable recovery path.

## Implementation Sequence

### Slice 0: Rodauth Integration Spike

- Pin and inspect the current Rodauth/Rodauth-Rails versions.
- Prove a dedicated password-security schema can map to D8N `User`,
  `IdentityIdentifier`, and `Credential` without a second account/session model.
- Prove generic public errors, parameter filtering, rate limiting, lockout, reset,
  and D8N session issuance in an isolated branch or proof.
- Decide whether D8N controllers call an internal adapter or whether narrowly
  mounted Rodauth JSON routes can preserve the canonical D8N API contract.

Gate: architecture review accepts the exact schema and feature list. The spike is
not production registration.

Implemented result: Rodauth 2.45.0/Rodauth-Rails 2.2.1 provide password policy,
bcrypt hashing, and internal password verification through a D8N adapter. A
credential-owned password-hash table has database-enforced credential-kind
consistency. No Rodauth routes, middleware, cookie/JWT session, or parallel
account table are enabled.

### Slice 1: Brand Auth Policy And Method Discovery

- Add dedicated validated brand auth configuration.
- Publish the host-resolved method-list endpoint and update OpenAPI/client docs.
- Keep every new method disabled until its implementation slice passes.

Implemented result: brands have a dedicated validated allow-list and
`GET /api/v1/auth/methods` returns only the intersection of configured and
implemented methods. Existing brands retain phone OTP during migration; newly
created brands deny all methods until explicitly configured. HookUs provisioning
enables phone OTP only. Password and Google are valid planned policy values but
are not advertised until implemented.

### Slice 2: Zero-Friction Phone/Email Password Registration And Login

- Add separate registration and login commands.
- Normalize and auto-detect phone or email identifiers.
- Create unverified identifiers honestly while allowing immediate password use.
- Add password digest, lifecycle, generic failure, throttling, and security-event
  behavior through the accepted Rodauth adapter.
- Issue only brand-bound D8N sessions.

Gate: tests cover cross-brand sessions, disabled methods, identifier collisions,
concurrency, inactive users/credentials/memberships, enumeration resistance,
secret filtering, password policy, and throttling.

### Slice 3: Password Reset And Change

- Add identifier-appropriate reset delivery without revealing account existence.
- Require recent reauthentication for password change.
- Revoke affected sessions and audit transitions without recording secrets.

### Slice 4: Explicit Credential Linking And Brand Join

- Add recent-reauthenticated linking for a new verified phone/email password.
- Add an explicit authenticated join-brand workflow.
- Deny collisions without automatic merge or cross-brand disclosure.

### Slice 5: Google Sign-In And Linking

- Select the concrete browser/mobile authorization flow and callback ownership.
- Add server-validated Google identity mapping and explicit linking.
- Minimize retained provider claims/tokens and issue D8N sessions only after
  brand-policy and lifecycle checks.

## Human Gates

Before production password recovery or identifier verification ships:

- approve breached-password handling and recovery/support policy;
- select the email delivery provider and approve phone/email verification copy;
- decide verification challenge expiry and resend policy;
- approve session revocation rules after reset, change, or linking;
- complete the Date9ja legacy password-hash inventory before migration behavior.

Before Google ships:

- decide whether the first client is web, mobile, or both and approve redirect
  origins;
- approve Google consent scopes and retained claims/tokens;
- approve the collision UX when Google email matches an existing D8N identifier;
- approve account-linking reauthentication and recovery UX.

## Founder Decisions (Uche, 2026-08-13)

- Signup is zero-friction: phone/password or email/password creates the account,
  current-brand membership, and session without prior OTP/email verification.
- Identifier verification happens later and must not block normal onboarding.
- Password minimum length is six characters with no composition rules. Maximum
  length remains bounded by bcrypt's 72-byte input limit.
- Google remains a later slice and is not bundled into password registration.

## Consequences

- Users can choose phone/password or email/password immediately when their brand
  enables it; Google and verification/recovery follow separately.
- Google users do not need a D8N password unless they explicitly add one later.
- Password and external-provider credentials belong to the platform identity,
  while memberships, profiles, policy, and sessions remain brand-specific.
- An identifier can be linked deliberately without automatic account
  merging.
- Registration, login, joining a brand, and linking remain distinguishable and
  auditable.
- Rodauth and Google integrations add dependencies and attack surface, so they
  ship through separate tested gates rather than one large auth change.
- Immediate email/password signup does not imply verified inbox control or an
  available email recovery path.

## Alternatives Considered

- Keep phone OTP as the only HookUs login.
- Require OTP on every login even after a user chooses a password.
- Implement separate phone-password and email-password engines.
- Hand-build password hashing, reset, and lockout.
- Let Rodauth own a parallel account or API session model.
- Put authentication settings inside profile-completion configuration.
- Auto-link Google when its email matches an existing D8N email.
- Automatically join every D8N brand after a successful platform credential
  login.
- Build every OAuth provider before a second provider is required.
