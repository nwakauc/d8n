# Authentication Compatibility

Date9ja uses Devise database authentication and `devise-jwt`; the source stores `users.encrypted_password`. The source lock contains bcrypt 3.1.22. D8N has bcrypt ~> 3.1 and stores the hash in `credential_password_hashes.password_hash` behind a password `Credential` and email `IdentityIdentifier`.

This is a likely direct hash migration, but must be proven by the operator-only bcrypt compatibility proof in `SNAPSHOT-RUNBOOK.md` §6 — an aggregate `(prefix_family, cost, count)` census of the real hashes, then one operator-owned seed account per bucket whose legacy digest + out-of-band plaintext must verify `true` through `Identity::PasswordEngine` with no rehash/reset. The sanitized rehearsal snapshot cannot prove this: it carries one inert digest, not real hashes. Never print or log hashes.

Format discovery (operator, 2026-09-02, pristine restore): all 288 hashed accounts are a **single bucket — `$2a$` cost 12**, zero malformed; Devise **pepper not configured**. The proof is implemented as `scripts/date9ja/bcrypt_proof.rb` (synthetic-value tests `test/scripts/date9ja/bcrypt_proof_test.rb`); it exercises `Identity::PasswordEngine.matches?` + `Identity::PasswordLogin` against a copied-verbatim digest inside a rolled-back transaction and prints only `<prefix> <cost> PASS|FAIL <reason>`.

**bcrypt compatibility — VERIFIED (2026-09-02).** The operator ran the proof with a real operator-owned `$2a$12$` Date9ja account and reported `$2a$ 12 PASS`: the legacy digest authenticated through the real D8N password path with no rehash, wrong passwords were rejected, `PasswordLogin` issued a D8N session, and the stored hash remained byte-identical to the source digest. The real-account manifest was deleted after the run. Preserving a supported legacy Date9ja bcrypt credential is therefore safe for the identity importer's credential step (`$2a$`, cost 12, 288 accounts, 0 malformed, pepper not configured). This does not unblock any other gated migration (sensitive fields, verification, trust, entitlements, media, cutover).

Import execution model (`DECISIONS.md`, RESOLVED 2026-09-02): the credential step reads from a **restored scratch PostgreSQL database**, not a live production connection. The bcrypt digest is copied verbatim from that restore into `credential_password_hashes.password_hash`.

## Mapping

Implemented by `Date9ja::Import::IdentityImport` (`domains/date9ja/import/`,
Wave A slice 3, SELF_VERIFIED 2026-09-03). Steps 1–4 below are covered; step 5's
profile is created here (non-sensitive fields only), the D8N session is issued at
the user's first real login, not by the importer.

1. Apply the approved D8N email normalization once (`Identity::LoginIdentifier`); do not merge source accounts on collision — a collision fails the row closed (`email_collision`).
2. Create one D8N user per source user through the legacy-ID map.
3. Create one email identifier; derive `verified_at` from Devise `confirmed_at`.
4. Create an active password credential and copy the bcrypt string without rehashing/truncating.
5. Create the Date9ja membership/profile; issue a D8N session only after successful login.
6. Discard source confirmation/reset tokens, OTP digests/codes, JWTs, JTI state, and Action Cable tokens.

Source JWTs cannot authenticate D8N: they use a different secret and session model. D8N sessions are brand-scoped, opaque-token records. Users need a fresh D8N session after first login, but should retain their password.

If a hash fails verification, preserve the mapping and use a one-time secure recovery flow through confirmed email or verified phone. Do not bulk-reset passwords or create unusable accounts. Recovery must be rate-limited, expiring, non-enumerating, and session-revoking.

**Implemented (Wave A Step 3 closeout, 2026-09-04 — `AUTH-TRANSITION.md`).** `Date9ja::Import::IdentityImport` migrates a row whose `encrypted_password` is missing or malformed as a **recovery-required credential** — an active `kind: password` `Credential` with **no `CredentialPasswordHash`** — *only* when the row owns a **verified email** (`FieldMapping.operable_recovery_channel?`; a verified phone alone does not count — the password credential is bound to the email identifier and shared recovery resolves it through the requested identifier). First access is then `Identity::RecoveryRequester` → `RecoveryVerifier` → `PasswordReset` (`PasswordEngine.set!` writes the first hash). With no operable channel the row fails closed (`credential_hash_unusable`) — no unreachable account is created. A rerun's completeness verdict is `IdentityImport#credential_completeness` — a supported bcrypt hash (`BCRYPT_RE` + `BCrypt::Password.new`) is required for a valid-source-digest credential, so a corrupt destination hash fails closed (`credential_hash_corrupt`) and a member's post-migration reset is never clobbered. Reconciliation: `credentials_recovery_required` counter, `credential_recovery_required` reason code. The census bucket is a single `$2a$` cost-12 group with 0 malformed, so this path is cutover robustness, re-asserted against the final snapshot. The whole migrated-account journey (login, brand-scoped session, `SessionAuthenticator` cross-brand rejection, recovery→reset, `Accounts::DeactivateAccount` ↔ `Identity::AccountReactivation`) is exercised by `Date9ja::Import::AuthTransitionCheck` and the L1 synthetic rehearsal; `date9ja:verify_auth_transition` is the operator L2 companion to `bcrypt_proof.rb`.

Self-deleted Date9ja accounts are not consumer-recoverable in the source (no undelete route; `active_for_authentication?` false; 30-day grace → anonymisation), so "account recovery" means password reset only, and the importer's `source_soft_deleted` / `source_banned` skips are parity-correct.

Acceptance tests: all observed hash formats verify; wrong passwords fail; email collisions quarantine; confirmed/unconfirmed states map; sessions cannot cross brands; repeated imports create zero duplicate identity/credential/profile rows; no secrets/tokens/hashes appear in artifacts.
