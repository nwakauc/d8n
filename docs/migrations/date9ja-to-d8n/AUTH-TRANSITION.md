# Migrated-account authentication transition (Wave A Step 3 — closeout)

Status: **IMPLEMENTED / SELF_VERIFIED (2026-09-04)** — NOT independently reviewed,
NOT `PARITY_ACCEPTED`, NOT cutover-ready. Linked from `STATUS.md`.

This document is the durable reference for how an **already-migrated** Date9ja
member signs in, recovers, and reactivates on D8N. It completes Wave A Step 3
("prove bcrypt hash compatibility; implement identifier/session transition and
recovery"). Byte-level digest compatibility was VERIFIED separately on 2026-09-02
(`scripts/date9ja/bcrypt_proof.rb`, `$2a$ 12 PASS`); this closeout proves the
**migrated account shape** works end to end through the shared D8N Identity
services.

## Principle

No Date9ja-specific authentication infrastructure was built. The migrated account
is an ordinary D8N identity and drives the same shared primitives every brand
uses:

| Journey | Shared D8N service | Date9ja input |
|---|---|---|
| First sign-in | `Identity::PasswordLogin` → `Session.issue!` (brand-scoped, opaque, HMAC-digested) | `brand.auth_methods` = `email_password`, `phone_password`; `phone_country_calling_code` `234` |
| Session isolation | `Identity::SessionAuthenticator` (`:wrong_brand`) | — |
| Sign-out | brand session destroy / `Identity::SessionRevoker` | — |
| Password reset (signed-out) | `Identity::RecoveryRequester` → `RecoveryVerifier` → `PasswordReset` | code delivered via the brand's configured email/SMS channel |
| Reactivation | `Accounts::DeactivateAccount` ↔ `Identity::AccountReactivation` | — |

Date9ja's legacy password-reset was a Devise `:recoverable` email + 6-digit code
flow with a generic response (`Api::V1::Auth::PasswordsController`). D8N's
`RecoveryRequester`/`RecoveryVerifier`/`PasswordReset` is behaviourally
equivalent: code-based, generic/anti-enumerating response, expiring
(`CODE_EXPIRES_IN` 10 min / reset token 15 min), attempt-capped, and
session-revoking on completion (D8N-wide for the affected password credential).

## Identity importer — credential outcomes

`Date9ja::Import::IdentityImport` copies the legacy bcrypt digest **verbatim**
into `credential_password_hashes.password_hash` (never `PasswordEngine.set!`).
Three outcomes per source row:

| Source `encrypted_password` | Outcome | Reconciliation |
|---|---|---|
| Well-formed 60-char bcrypt (`$2[aby]$NN$…`) | Password credential with the verbatim digest | `imported`, `password_hashes_created += 1` |
| Missing / malformed **and** the row has a **verified email** | **Recovery-required** credential — `kind: password`, `status: active`, **no `CredentialPasswordHash`**. No password can match; first access is the signed-out recovery flow. | `imported`, `credentials_recovery_required += 1`, reason `credential_recovery_required` |
| Missing / malformed **and no operable recovery channel** (unverified email — a verified phone alone does **not** count, see below) | **Fail closed** — no account is created (an unreachable account is exactly what `AUTHENTICATION.md` forbids). Operator-actionable. | `failed`, reason `credential_hash_unusable`; `malformed_rows` anomaly when the digest was non-empty |

The sanitized-snapshot census (2026-09-02) found **all 288 hashed accounts in a
single `$2a$` cost-12 bucket, 0 malformed, 0 empty** — the recovery-required and
fail-closed paths are cutover robustness, exercised only by synthetic fixtures
and re-asserted against the final production snapshot.

**Why a verified phone alone is not enough.** The password `Credential` is bound
to the **email** `IdentityIdentifier`, and the shared `Identity::RecoveryRequester`
/ `PasswordReset` resolve the credential *through the requested identifier*
(`identity_identifier.credentials.find_by(kind: :password)`). The shared runtime
has no cross-identifier fallback, so a recovery request through a phone
identifier that carries no password credential cannot complete. Rather than
invent Date9ja-specific cross-identifier recovery (which would be new
authentication infrastructure), an unusable-digest account is recovery-required
**only when its email is verified** — the channel the runtime can actually
complete end to end. A verified-phone-only account fails closed
(`credential_hash_unusable`). This is `FieldMapping.operable_recovery_channel?`.

**Destination credential completeness (`IdentityImport#credential_completeness`).**
On a re-run, the destination password credential is judged (not drift-detected):

| Source digest | Persisted destination hash | Verdict |
|---|---|---|
| usable legacy bcrypt | absent | `:incomplete` → `incomplete_binding` (fail closed) |
| any | present but not a supported bcrypt string | `:corrupt_credential` → `credential_hash_corrupt` (fail closed, `malformed_rows` anomaly) |
| usable legacy bcrypt | supported bcrypt (verbatim legacy copy **or** a valid replacement the member set via recovery) | `:complete` |
| unusable (recovery-required) | absent | `:complete` |
| unusable (recovery-required) | supported bcrypt (member recovered) | `:complete` |

"Supported bcrypt" = matches the importer's `BCRYPT_RE` **and** parses through
`BCrypt::Password.new`. A bulk re-run therefore never restores the old Date9ja
digest over a password the member has since reset.

## Lifecycle mapping (auth-relevant)

| Date9ja state | Importer treatment | Sign-in behaviour |
|---|---|---|
| active | `BrandMembership` + `Profile` active (profile draft/hidden until later slices) | normal login |
| `suspended_at` present | membership + profile `suspended` | `PasswordLogin` → `:invalid_credentials` after a correct password (moderation state; not self-clearable — HQ lifts it) |
| `banned_at` present | **skipped** (`source_banned`) — an enforcement tombstone, no D8N account | n/a |
| `deleted_at` present (self-deletion) | **skipped** (`source_soft_deleted`) | n/a — see below |

**Self-deleted accounts / "recovery behavior".** Date9ja's `DELETE /api/v1/account`
is password-confirmed soft deletion followed by `AccountHardDeleteJob`
anonymisation after a 30-day grace period; `User#active_for_authentication?`
returns **false** for a deleted account, and there is **no consumer
undelete/reactivation route**. Date9ja "account recovery" is therefore *password
reset only* (Devise `:recoverable`), which D8N's recovery flow preserves. The
importer skipping `deleted_at` rows is parity-correct: a deleted Date9ja member
could not sign in to Date9ja either. `Identity::AccountReactivation` restores a
**D8N-native self-deactivation** (`Accounts::DeactivateAccount`) — additive
capability Date9ja never had, available to migrated members who later deactivate
on D8N.

Open cutover-delta edge (not a blocker): an account soft-deleted in production but
still inside its 30-day grace window at snapshot time is dropped with no D8N
presence. Handled by the established media-delta rule — auto-flag/reconcile, never
auto-create or auto-delete destination data, final authoritative snapshot governs.

## Evidence

### When there is no operable recovery channel

An unverified email (Devise `confirmed_at` NULL — census: 79 / 288, and a
verified phone does not substitute) means:

- if the account has a **usable legacy digest**: it still **authenticates with
  its password** post-migration (ADR 0012), but is **not** a signed-out
  password-reset channel — D8N's `RecoveryRequester` requires a verified
  identifier, whereas Date9ja's Devise `:recoverable` did not. Accepted ADR-0012
  posture, not a regression: the member keeps their password and gains
  self-serve reset once they verify the email. `AuthTransitionCheck` models this
  with `recovery_expected: false` (asserts reset fails closed, password still
  works).
- if the account has an **unusable legacy digest**: the importer **fails it
  closed** (`credential_hash_unusable`) — no account, because there is no way in.

Whether Date9ja's product owner wants to soften the reset restriction for the
unconfirmed cohort at cutover is a **Phase-5 parity-acceptance question**, not an
implementation blocker.

### L1 — synthetic rehearsal (`test/domains/date9ja/import/auth_transition_rehearsal_test.rb`)

Imports synthetic `users` rows through the real `IdentityImport`, then runs
`Date9ja::Import::AuthTransitionCheck` over every migrated account:

- **active** (×2): first login succeeds + brand-scoped session persisted (user /
  brand / credential match); wrong password → `:invalid_credentials`; legacy
  digest byte-identical after login; session rejected by
  `SessionAuthenticator` for another brand (`:wrong_brand`); sign-out
  (`SessionRevoker`) makes the token unauthenticable (`:revoked_session`);
  `Accounts::DeactivateAccount` → login `:account_deactivated` →
  `AccountReactivation` restores an active session; full recovery
  (`RecoveryRequester` → delivered code → `RecoveryVerifier` → `PasswordReset`)
  revokes prior sessions (`revoked_session_count > 0`), the old password stops
  working, the new password logs in.
- **recovery-required** (×1): every password guess → `:invalid_credentials`;
  recovery round-trip sets a password and then logs in.
- **suspended** (×1): correct password → `:invalid_credentials`; no active
  session exists.

`AuthTransitionCheck#to_h` is deterministic and PII-free (aggregate pass/fail
counts per check + distinct `{check:reason}` pairs — no email, phone, digest,
code, or token). A dedicated test asserts the dump contains no secret material.

bcrypt cost in the rehearsal is `BCrypt::Engine::MIN_COST` (synthetic values
only). Real cost-12 compatibility remains proven by `bcrypt_proof.rb`.

### L2 — scaled synthetic rehearsal (`test/domains/date9ja/import/auth_transition_l2_rehearsal_test.rb`)

The in-process analogue of a full operator L2 run (which needs operator-owned
real seed accounts + out-of-band plaintexts and stays an operator task). A 19-row
synthetic `users` cohort — 12 active (10 with a verified recovery channel, 2 with
an unconfirmed email), 2 recovery-required (one blank digest, one malformed),
2 suspended, 1 banned, 1 self-deleted, 1 unusable-digest-no-channel — is imported
through the **real** `IdentityImport`, then:

1. reconciliation balances (`source_users_considered == Σ dispositions`);
   `imported 16 / skipped 2 / failed 1`; `credentials_recovery_required 2`;
   `password_hashes_created 14`.
2. a clean re-run **before any sign-in** → 16 `already_imported`, zero rows
   created or destroyed.
3. `AuthTransitionCheck` over all 16 migrated accounts → **0 failures** across
   every check (login, brand-scoped session, cross-brand rejection, wrong
   password, legacy hash preserved, recovery→reset with session revocation,
   reactivation, suspended lock-out, recovery-unavailable-fails-closed).
4. a re-run **after** members have reset passwords via recovery → still 16
   `already_imported`, **zero rows changed** — the bulk importer never clobbers a
   member-set password (`credential_completeness` is a completeness check, not drift detection).

### L2 — operator check (`rake date9ja:verify_auth_transition`)

Broad companion to `bcrypt_proof.rb`. Run **last**, against a throwaway rehearsal
DB, after `date9ja:import_identity` — it mutates the accounts it exercises
(recovery changes passwords, reactivation toggles membership).

- **Database fence** — reuses `Date9ja::Snapshot::Connection.assert_runtime_safe!`
  (the accepted disposable-DB contract: `RAILS_ENV=test` alone is insufficient —
  the primary DB name must match `d8n_date9ja_rehearsal*`). A non-approved target
  is refused **before any check runs**, with a clear non-secret message.
- **Manifest** (`DATE9JA_AUTH_MANIFEST`, absolute TSV):
  `identifier<TAB>password<TAB>lifecycle[<TAB>no_recovery]`, parsed by
  `AuthTransitionCheck.parse_manifest`. An **empty** manifest and an **unknown
  lifecycle** (allowlist = `AuthTransitionCheck::LIFECYCLES`) are rejected before
  any check, non-zero exit, error names the line and bad token only — never an
  identifier or password.
- Output is JSON with manifest secrets scrubbed; non-zero exit on any failed
  check. `AuthTransitionCheck` also records `lifecycle_supported` per subject and
  a zero-subject run is **not** a pass.

**Tool proven (2026-09-04)** against a compliant throwaway DB
(`d8n_date9ja_rehearsal_authtx`) with 3 synthetic imported accounts (active /
suspended / recovery-required): all checks pass, exit 0, JSON PII-free; unknown
lifecycle → `manifest: line 1: unknown lifecycle :god_mode …` abort; empty
manifest → `manifest contains no subject rows` abort; `DATABASE_URL` pointed at
`d8n_development` (with `RAILS_ENV=test`) → `refusing to run …` abort **before any
mutation**. **The real-seed-account operator L2 (real cost-12 digests + real
plaintexts) is NOT yet run** — operator task, same class as `bcrypt_proof.rb`.

## Not done here (later phases)

Frontend/mobile auth adapters, Devise error-envelope mapping, opaque-ID handling,
the API contract surface, and the parity-acceptance journey are **Phase 5**.
Registration/welcome-flow parity, email-confirmation and phone-OTP Date9ja policy
tuning, and notification-preference migration are their own slices. This closeout
does not move any capability to `PARITY_ACCEPTED`.
