# ADR 0005: Use Flexible Credential Strategy For Authentication

## Status

Accepted for direction after initial spike.

## Context

D8N brands may need different authentication flows. HookUs may support phone-first OTP. Date9ja may require stronger verification. Future brands may need email/password, OAuth, invite-only access, WebAuthn, or MFA.

Devise is mature but assumes a more fixed account credential model. D8N needs flexibility without writing fragile custom authentication security from scratch.

## Decision

D8N will use a flexible credential and authentication strategy model.

Rodauth/Rodauth-Rails is the preferred mature Ruby/Rails authentication engine to evaluate first because it supports many security-oriented features and JSON/API usage.

All auth strategies must produce the same D8N session model.

The initial spike on `spike/rodauth-phone-otp` showed:

- Rodauth-Rails works with Rails 8 API-only.
- Rodauth JSON/JWT routes can be mounted successfully.
- Rodauth's generated default is email/password centered.
- Rodauth's `sms_codes` feature is primarily a multifactor/backup SMS-code feature, not a complete phone-first signup/login flow by itself.

D8N should therefore use Rodauth/Rodauth-Rails where it cleanly provides mature account/session/security primitives, while implementing HookUs-style phone-first OTP as a D8N authentication strategy around or alongside those primitives.

## Consequences

- Brands can choose different auth policies without separate identity systems.
- D8N avoids custom crypto, password hashing, and session security.
- Phone-only auth can be supported for brands where appropriate, with rate limiting, lockout, OTP expiry, device tracking, and step-up verification.
- Rodauth should not be forced into a shape that hides D8N's identity, credential, and brand-policy requirements.
- A final implementation design is still required before production auth code is merged.

## Alternatives Considered

- Devise as the sole auth framework.
- Fully custom authentication.
- Separate authentication systems per brand.
