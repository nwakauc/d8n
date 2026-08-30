# D8N HQ — Foundation and Security Implementation Handoff

Status: **BACKEND BUILT; OPERATIONAL ACCEPTANCE OUTSTANDING.** This is the
stable frontend and rollout handoff for Phase 0 HQ-001, differentiated
brand-scoped RBAC, operator management, and the admin-MFA launch gate. It
does not start Phase 3/HQ-010.

The machine-readable contract is `docs/api/openapi.yaml`. Security policy
is authoritative in `SECURITY-AND-RBAC.md`, ADR 0020, and ADR 0021.

## Routes

| Method | Route | MFA | Capability/purpose |
| --- | --- | --- | --- |
| GET | `/api/v1/version` | No session | Exact non-secret deployment identity |
| GET | `/api/v1/hq/operator` | Not required | Current operator, assignments, capabilities, MFA state |
| GET | `/api/v1/hq/operators` | Required | `admin.operators.read` |
| POST | `/api/v1/hq/operators` | Required | `admin.operators.manage` plus role-grant policy |
| PATCH | `/api/v1/hq/operators/{id}` | Required | `admin.operators.manage` plus role-grant policy |
| POST | `/api/v1/hq/mfa/enrollment` | Not yet | Start/replace pending TOTP enrollment |
| PATCH | `/api/v1/hq/mfa/enrollment` | Not yet | Confirm TOTP; returns recovery codes once |
| POST | `/api/v1/hq/mfa/challenge` | Not yet | Verify TOTP or consume recovery code for this session |
| DELETE | `/api/v1/hq/mfa/enrollment` | Verified + fresh code | Reset/rotate MFA |

All previously documented Phase 1/2 and `/api/v1/admin` endpoints now
require the capability documented in OpenAPI and an MFA-verified session.
Their successful payloads, filters, cursors, privacy restrictions, and
neutral 404 behavior are unchanged.

## Frontend bootstrap flow

1. Authenticate through the existing brand password/session flow. HQ has
   no separate login.
2. Call `GET /api/v1/hq/operator`.
3. On `401`, return to ordinary login. On `403 forbidden`, show revoked or
   unauthorized access and do not retry against other brands implicitly.
4. Read `operator.mfa.state` and `operator.mfa.verified`:
   - `not_enrolled`: start enrollment, render the QR/provisioning URI,
     confirm a TOTP, then force the operator to save the eight recovery
     codes before continuing;
   - `pending`: restart enrollment to obtain a fresh displayable secret,
     then confirm;
   - `active` + `verified: false`: show a TOTP/recovery-code challenge;
   - `active` + `verified: true`: load authorized HQ surfaces.
5. Build navigation/actions only from `effective_capabilities`. Role names
   are display/context, never authorization.
6. For any protected request returning `403 admin_mfa_required`, preserve
   intended navigation, challenge, then retry once. `403 forbidden` is not
   an MFA prompt.

Enrollment secrets, TOTP codes, and recovery codes must never enter logs,
analytics, error telemetry, local storage, or query strings. Recovery
codes are displayed once and stored offline by the operator.

Cookie-authenticated unsafe calls retain the existing `X-CSRF-Token`
requirement. Bearer calls retain existing behavior.

## Current operator response semantics

- `current_brand`: host-resolved authorization context.
- `role`: display/audit context.
- `effective_capabilities`: authoritative current-brand permissions.
- `grantable_roles`: authoritative subset available to operator-management
  UI; never synthesize options from hierarchy assumptions.
- `brand_assignments`: active assignments for switcher display. Switching
  hosts still requires a valid session for that brand.
- `mfa.recovery_codes_remaining`: null before enrollment, otherwise the
  count remaining; warn when low without revealing codes.

## Operator-management behavior

- List is current-brand-only and bounded to 100.
- Creation accepts an existing verified email whose D8N user already has
  active membership on this brand.
- API never creates consumer membership, credentials, or Founder.
- Founder alone can assign/manage Super Admin.
- Super Admin can manage only non-privileged roles.
- No actor can change their own assignment.
- Revocation/suspension takes effect on the next request.
- `admin_status` is visible but global status is not mutable from this
  brand-scoped API.
- Every successful change is audited; unknown/wrong-brand operator IDs are
  neutral `operator_unavailable` 404s.

## MFA errors and recovery

- Invalid/missing proof: `422 admin_mfa_code_invalid` or the relevant
  enrollment-state code.
- Too many failures: `429 admin_mfa_rate_limited` plus `Retry-After`.
- A recovery code is consumed on success and cannot be replayed.
- Normal reset requires a stepped-up session plus a fresh factor, then
  routes back to enrollment.
- If all factors are lost, the offline break-glass task below is the only
  recovery path. It invalidates every session's prior step-up and writes a
  critical audit event.

## Release identity

The Docker build bakes `D8N_GIT_SHA` and `D8N_BUILD_TIMESTAMP`. Kamal
supplies `KAMAL_VERSION` at runtime. `/api/v1/version` returns all three
truthfully plus deployment/Rails environments and process boot time.

Use `git_sha` to prove source identity even if `image_version` was given a
mutable operational alias. A null field is unavailable, never equivalent
to the current local checkout.

## Staging-first rollout procedure (do not run from an exploratory session)

After the reviewed build is deployed to staging and its normal container
boot has run `db:prepare`:

```sh
bundle exec kamal app exec -c config/deploy.staging.yml -p --reuse "bin/rails db:migrate:status"
bundle exec kamal app exec -c config/deploy.staging.yml -p --reuse "bin/rails db:seed"
bundle exec kamal app exec -c config/deploy.staging.yml -p --reuse \
  -e FOUNDER_EMAIL:nwakauc1@gmail.com "bin/rails d8n:bootstrap_founder"
```

Then sign in on the staging brand host, enroll Founder MFA through the API,
store recovery codes offline, and verify `/api/v1/version`, every role,
revocation, wrong-brand isolation, and Phase 1/2 frontend flows.

Only after staging acceptance, repeat against production deliberately:

```sh
bundle exec kamal app exec -c config/deploy.production.yml -p --reuse "bin/rails db:migrate:status"
bundle exec kamal app exec -c config/deploy.production.yml -p --reuse "bin/rails db:seed"
bundle exec kamal app exec -c config/deploy.production.yml -p --reuse \
  -e FOUNDER_EMAIL:nwakauc1@gmail.com "bin/rails d8n:bootstrap_founder"
```

`d8n:bootstrap_founder` is idempotent. It upgrades legacy Moderator
assignments by revoking/tombstoning them and creating one active Founder
assignment per active brand. It does not create an account or password.

Break-glass MFA reset, only after identity verification through the
founder's documented offline operational process:

```sh
bundle exec kamal app exec -c config/deploy.production.yml -p --reuse \
  -e FOUNDER_EMAIL:nwakauc1@gmail.com \
  -e CONFIRM_RESET_ADMIN_MFA:nwakauc1@gmail.com \
  "bin/rails d8n:reset_admin_mfa"
```

After break-glass reset, the founder must immediately sign in and enroll a
new factor. No production command in this document was executed by this
implementation task.

## Remaining operational gates

- Frontend integration and verification for both current slices.
- Staging role/MFA/isolation acceptance.
- Staging `/api/v1/version` must contain the deployed 40-character SHA.
- Production founder upgrade and MFA enrollment by the authorized human.
- Recovery codes stored in the approved offline location.

Stop after these Phase 1/2 gates. Phase 3/HQ-010 remains next but not
started.
