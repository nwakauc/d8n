# D8N Founder HQ — Operational Acceptance Runbook

Use this runbook after deploying a known version to staging or production. Do
not perform destructive member, moderation, enforcement, or operator actions
as part of acceptance.

## Founder

| Check | Status | Evidence / action |
|---|---|---|
| Login with founder identity | STAGING REQUIRED | Use the approved founder account; confirm the expected identity and brand context. |
| Complete admin MFA | STAGING REQUIRED | Enrol or use the approved TOTP/recovery path; do not record secrets or recovery codes. |
| Open HQ | LOCAL VERIFIED / STAGING REQUIRED | Local HQ request tests pass; repeat against the deployed version. |
| Confirm version identity | STAGING REQUIRED / PRODUCTION REQUIRED | Record the deployed commit or release identifier shown by the approved operational mechanism. |

## Member Operations

| Check | Status | Evidence / action |
|---|---|---|
| Directory search | LOCAL VERIFIED / STAGING REQUIRED | Search only approved test members by supported identifier semantics. |
| Directory filters and pagination | LOCAL VERIFIED / STAGING REQUIRED | Verify status/date filters, bounded sorting, and next-page behavior. |
| Open Member 360 | LOCAL VERIFIED / STAGING REQUIRED | Follow a directory result to the brand-scoped Member 360 view. |

## Trust & Safety

| Check | Status | Evidence / action |
|---|---|---|
| Report queue | LOCAL VERIFIED / STAGING REQUIRED | Read the brand-scoped queue and confirm only expected test data appears. |
| Report detail | LOCAL VERIFIED / STAGING REQUIRED | Open evidence/context without exporting unnecessary sensitive data. |
| Enforcement history | LOCAL VERIFIED / STAGING REQUIRED | Confirm history is brand-scoped and actor-attributed. |
| Security alerts | LOCAL VERIFIED / STAGING REQUIRED | Confirm the assigned capability can read the intended alerts only. |

## Command Centre

| Check | Status | Evidence / action |
|---|---|---|
| Current-brand health snapshot | LOCAL VERIFIED / STAGING REQUIRED | `GET /api/v1/hq/command_centre/health`; verify windows, definitions, real zero, unavailable, and insufficient-data states. |
| Attention signals | LOCAL VERIFIED / STAGING REQUIRED | Verify only deterministic signals for the seeded operational conditions. |
| Brand comparison | LOCAL VERIFIED / STAGING REQUIRED | `GET /api/v1/hq/command_centre/brands`; verify only authorized brands are returned. |

## RBAC

| Check | Status | Evidence / action |
|---|---|---|
| Allowed role/capability | LOCAL VERIFIED / STAGING REQUIRED | Exercise the effective capability, not the role label alone. |
| Denied role/capability | LOCAL VERIFIED / STAGING REQUIRED | Confirm the API returns the documented denial without disclosing data. |
| Revoked assignment | LOCAL VERIFIED / STAGING REQUIRED | Revoke a non-production test assignment and confirm access stops. |
| Production founder/operator review | PRODUCTION REQUIRED | Review assignments and MFA enrollment through the approved change-control process; no changes are required for this read-only check. |

## Evidence and sign-off

Record the environment, deployed version, timestamp, brand, effective
capability, endpoint, response status, and result. Never record passwords,
tokens, TOTP secrets, recovery codes, private message bodies, or unnecessary
member PII. Mark a check complete only after observing the result in that
environment.
