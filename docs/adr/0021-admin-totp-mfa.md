# ADR 0021: Administrative TOTP MFA and Session Step-Up

## Status

Accepted for the D8N HQ Phase 1/2 launch gate on 2026-08-29.

## Context

ADR 0013 intentionally reused D8N's ordinary brand-scoped `Session` for
administrators and left MFA as a required pre-launch gate. Member 360 and
Trust & Safety now expose sensitive identity and operational data, so an
ordinary authenticated session is no longer sufficient for those
surfaces.

Email security questions and frontend-only flags are not acceptable
second factors. Creating a parallel admin password/session system would
contradict ADR 0013.

## Decision

Admins continue to authenticate through the ordinary brand-scoped
session. A kept, active admin assignment then permits access only to the
current-operator and MFA bootstrap/challenge endpoints until that exact
session completes a second-factor challenge.

The second factor is RFC 6238 TOTP:

- a random secret is encrypted at rest with the existing mandatory Active
  Record Encryption keys;
- enrollment is pending until a valid TOTP confirms possession;
- successful confirmation/challenge records the credential used on the
  current session;
- session step-up is invalid immediately when that MFA credential is
  rotated, disabled, or soft-deleted;
- recovery codes are random, displayed once, stored only as keyed
  digests, and consumed atomically once used;
- failures are throttled and audited without recording codes or secrets;
- reset/rotation requires a currently verified session plus a fresh TOTP
  or recovery-code proof.

The stable API distinction is:

- `401 unauthorized` — no valid ordinary session;
- `403 forbidden` — no active assignment or required capability;
- `403 admin_mfa_required` — valid admin assignment, but this session has
  not completed MFA.

A deliberately confirmed offline task is the break-glass recovery path
when every factor and recovery code is lost. It disables the credential,
invalidates all existing admin step-up state through credential identity,
and writes a security event. It never creates or prints a credential.

## Consequences

- MFA is per administrative identity, while verification is per session.
- The current-operator response is available before step-up so clients can
  route honestly into enrollment or challenge.
- All current HQ and moderation surfaces are MFA-gated by the backend.
- TOTP clock synchronization becomes an operational dependency; a narrow
  adjacent-window tolerance is used.

