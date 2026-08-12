# ADR 0005: Use Flexible Credential Strategy For Authentication

## Status

Accepted for direction, implementation spike required.

## Context

D8N brands may need different authentication flows. HookUs may support phone-first OTP. Date9ja may require stronger verification. Future brands may need email/password, OAuth, invite-only access, WebAuthn, or MFA.

Devise is mature but assumes a more fixed account credential model. D8N needs flexibility without writing fragile custom authentication security from scratch.

## Decision

D8N will use a flexible credential and authentication strategy model.

Rodauth/Rodauth-Rails is the preferred mature Ruby/Rails authentication engine to evaluate first because it supports many security-oriented features and JSON/API usage.

All auth strategies must produce the same D8N session model.

## Consequences

- Brands can choose different auth policies without separate identity systems.
- D8N avoids custom crypto, password hashing, and session security.
- Phone-only auth can be supported for brands where appropriate, with rate limiting, lockout, OTP expiry, device tracking, and step-up verification.
- An implementation spike is required to confirm the cleanest Rodauth/Rodauth-Rails design for phone-first OTP in an API-only Rails platform.

## Alternatives Considered

- Devise as the sole auth framework.
- Fully custom authentication.
- Separate authentication systems per brand.
