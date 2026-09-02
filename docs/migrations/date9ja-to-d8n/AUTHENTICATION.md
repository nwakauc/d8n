# Authentication Compatibility

Date9ja uses Devise database authentication and `devise-jwt`; the source stores `users.encrypted_password`. The source lock contains bcrypt 3.1.22. D8N has bcrypt ~> 3.1 and stores the hash in `credential_password_hashes.password_hash` behind a password `Credential` and email `IdentityIdentifier`.

This is a likely direct hash migration, but must be proven using a sanitized snapshot and representative bcrypt prefixes/costs. Never print or log hashes.

## Mapping

1. Apply the approved D8N email normalization once; do not merge source accounts on collision.
2. Create one D8N user per source user through the legacy-ID map.
3. Create one email identifier; derive `verified_at` from Devise `confirmed_at`.
4. Create an active password credential and copy the bcrypt string without rehashing/truncating.
5. Create the Date9ja membership/profile; issue a D8N session only after successful login.
6. Discard source confirmation/reset tokens, OTP digests/codes, JWTs, JTI state, and Action Cable tokens.

Source JWTs cannot authenticate D8N: they use a different secret and session model. D8N sessions are brand-scoped, opaque-token records. Users need a fresh D8N session after first login, but should retain their password.

If a hash fails verification, preserve the mapping and use a one-time secure recovery flow through confirmed email or verified phone. Do not bulk-reset passwords or create unusable accounts. Recovery must be rate-limited, expiring, non-enumerating, and session-revoking.

Acceptance tests: all observed hash formats verify; wrong passwords fail; email collisions quarantine; confirmed/unconfirmed states map; sessions cannot cross brands; repeated imports create zero duplicate identity/credential/profile rows; no secrets/tokens/hashes appear in artifacts.
