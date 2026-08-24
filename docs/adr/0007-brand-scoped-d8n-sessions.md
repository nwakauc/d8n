# ADR 0007: Use Brand-Scoped D8N Sessions

## Status

Accepted; transport amended by ADR 0019.

## Context

D8N has one platform `User` identity that may belong to multiple brands through `BrandMembership`.

That does not mean a session token issued in one brand should automatically authenticate requests in every brand. Users may expect Date9ja, HookUs, DateZA, and future third-party brands to behave as separate dating contexts even when D8N powers them underneath.

Future auth strategies, including Rodauth-backed email/password, must converge into the same D8N session mechanism rather than creating a parallel session system.

## Decision

D8N sessions are scoped to one `brand_id`.

`SessionAuthenticator` accepts a D8N session credential, whether transported as
an explicit bearer token or an HttpOnly browser cookie under ADR 0019, only when:

- The token digest matches a stored `Session`.
- The session belongs to the current resolved brand.
- The session is not expired.
- The session is not revoked.

All auth strategies must issue D8N `Session` records and be validated through `SessionAuthenticator`.

## Consequences

- A HookUs session credential cannot authenticate Date9ja requests.
- Brand privacy and tenant isolation stay simple.
- Each brand can apply its own auth and session policy later.
- Users may need separate sessions when intentionally using multiple D8N brands.
- If D8N later needs platform-wide SSO, it must be introduced explicitly rather than assumed from shared identity.

## Alternatives Considered

- One platform-wide session valid across all brands.
- Separate unrelated session systems per auth strategy.
- Rodauth-owned sessions running in parallel with D8N sessions.
