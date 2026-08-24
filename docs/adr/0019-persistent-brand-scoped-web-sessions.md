# ADR 0019: Persistent Brand-Scoped Web Sessions

## Status

Accepted.

This ADR amends the bearer-only transport described by ADR 0007 while preserving
its brand-scoped D8N session authority. It also clarifies, rather than reverses,
ADR 0012: Rodauth does not own consumer sessions.

## Context

D8N originally exposed only an opaque bearer credential. Frontends deliberately
kept it in JavaScript memory instead of localStorage, sessionStorage, IndexedDB,
or a JavaScript-readable cookie. This reduced persistence of a bearer secret that
an XSS payload could read. It also meant a full page reload destroyed the only
client copy and appeared to log the member out even though the server `Session`
record remained active.

That threat model still applies. Persisting the bearer in browser-readable
storage would solve reloads by weakening the original XSS boundary. A
platform-wide parent-domain cookie would additionally violate D8N's separation
between global identity and brand membership/session context.

## Decision

D8N ID supports two transports over the same brand-bound `Session` model and
`SessionAuthenticator`:

1. **Bearer mode** remains the default for native, API, Swagger, and existing
   clients. Registration/login returns the opaque token and sets no cookie.
2. **Browser mode** is explicitly requested with `session_mode: "browser"`.
   Registration/login sets the opaque credential in a host-only HttpOnly cookie
   and does not include the bearer secret in JSON.

Both modes use the same token digest, expiry, revocation, credential binding,
user lifecycle, and brand-membership checks. There is no second identity or
session system. DateZA and HookUs opt into the reusable
`id.session.browser_persistence` capability; unknown brands fail closed.

## Cookie Policy

- Name: `d8n_web_session`
- `HttpOnly`: always
- `Secure`: always in production
- `SameSite`: `None` in production, because an explicitly allowlisted frontend
  may be cross-site to its API; `Lax` in development/test
- Path: `/api/v1`
- Domain: omitted, making the cookie host-only; a parent D8N/brand domain is
  never used
- Expiry and max-age: the existing server session's absolute expiry, currently
  30 days from issuance

There is currently no idle timeout. Authentication updates `last_used_at` for
observability but never extends the absolute expiry. A new registration/login
creates a new random session credential and overwrites that browser's cookie;
there is no rolling per-request rotation, which avoids invalidating concurrent
tabs. Logout revokes the server session and deletes the cookie using the same
path and attributes. A copied old cookie remains rejected after revocation.

## CSRF And Origin Model

Automatically attached cookies introduce CSRF risk. Every cookie-authenticated
non-GET/HEAD/OPTIONS API request must include `X-CSRF-Token`. The value is a
purpose-separated HMAC derived from server-held session state, is compared in
constant time, and is returned only in the successful browser auth response and
cookie-authenticated `GET /api/v1/me`. It is not an authentication credential.

Login and registration establish a new browser session and therefore cannot
depend on an existing session CSRF token. Browser mode is instead accepted only
from the same API origin or an exact configured CORS origin; an absent `Origin`
with `Sec-Fetch-Site: cross-site` is rejected. Unapproved origins receive 403
before credentials are checked or a session is created. Bearer-authenticated
unsafe requests remain CSRF-exempt because browsers do not attach the
Authorization header automatically.

CORS permits credentials only for exact `D8N_CORS_ORIGINS` entries and permits
`X-CSRF-Token`; wildcard origins are rejected at boot. Production has no implicit
origin allowlist. Frontends must use credentialed requests deliberately.

## Brand And Identity Boundary

The cookie is host-only, but host isolation is defense in depth rather than the
authorization boundary. Every request resolves the brand from its host and the
authenticator requires `session.brand_id` to match. Replaying a DateZA cookie on
HookUs therefore fails even if a caller manually copies it. A shared `User` and
memberships in both brands do not create SSO; the member authenticates separately
and receives a separate session for each brand.

Wrong-brand, malformed, missing, and otherwise invalid credentials return the
generic `unauthorized` error to avoid a tenant/session oracle. A browser bootstrap
may distinguish its own expired or revoked session as `session_expired` or
`session_revoked`; the rejected cookie is cleared.

## Sensitive Events

Existing D8N policy remains authoritative:

- logout revokes the current session;
- password change and verified login-email replacement keep the requesting
  session and revoke other sessions backed by the affected credential;
- password recovery revokes all sessions backed by that credential across brands;
- brand account closure or security suspension revokes sessions for that brand;
- inactive/deleted user, brand, membership, or credential state fails at every
  authentication attempt.

This ADR does not introduce device management, platform-wide logout, automatic
cross-brand login, or an idle-session policy.

## Consequences

- Web applications can bootstrap after reload with `GET /api/v1/me` without
  storing a bearer token in JavaScript-readable persistent storage.
- Browser clients must opt in, send credentials, retain the CSRF token in memory,
  and refresh that token from `/me` after a page reload.
- Existing bearer consumers remain compatible.
- XSS can still act as the user while it runs and can read the CSRF token, but it
  cannot directly read the persistent authentication cookie for later replay.
- Exact origin operations and HTTPS are deployment requirements for cross-site
  production frontends.
- A local frontend on `localhost` and a DateZA API on `dateza.test` are cross-site;
  because insecure `SameSite=None` cookies are rejected by modern browsers,
  persistent DateZA development needs a same-origin proxy preserving the API Host
  (or local HTTPS). Bearer-mode direct CORS remains available.

## Alternatives Considered

- Persisting the bearer in localStorage, sessionStorage, IndexedDB, or a readable
  cookie: rejected because arbitrary frontend JavaScript could extract it.
- Setting a cookie while also returning the same secret in JSON: rejected because
  it defeats the HttpOnly boundary at issuance.
- A platform-wide parent-domain identity cookie or implicit cross-brand SSO:
  rejected because global identity does not imply shared brand session context.
- Replacing bearer support entirely: rejected because native/API clients still
  benefit from explicit credentials.
- A second Rails/Rodauth cookie-session authority: rejected because it would
  duplicate revocation, lifecycle, and tenant enforcement.
