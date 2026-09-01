# D8N HQ — Security, RBAC, Audit & Privacy

Status as of 2026-09-01: **IMPLEMENTED FOUNDATION; OPERATIONAL GATES
OUTSTANDING.** ADR 0020 and ADR 0021 are authoritative for the current
authorization and MFA design. Staging verification, founder upgrade/MFA
enrollment, and frontend acceptance must still occur before real HQ use.

## 1. Administrative identity and session boundary

Admins remain ordinary D8N `User` identities authenticated through an
ordinary brand-scoped `Session` (ADR 0013). There is no admin password,
admin session, or parallel identity universe.

Administrative authorization additionally requires:

1. a kept, active `AdminUser` linked to the authenticated `User`;
2. exactly one kept, active `AdminAssignment` for the host-resolved brand;
3. the action's explicit capability in that assignment's role;
4. a valid TOTP/recovery-code step-up on this exact session, except for
   current-operator discovery and MFA enrollment/challenge.

Stable failure semantics:

- `401 unauthorized`: no valid ordinary brand session;
- `403 forbidden`: no active current-brand assignment, unknown role,
  revoked/disabled admin, or missing capability;
- `403 admin_mfa_required`: valid assignment/capability, but this session
  has not completed admin MFA.

The server is authoritative. Frontend visibility is never authorization.

## 2. Brand authorization and "All D8N"

HQ V1 implements the canonical **Option A** boundary: every authorization
is an explicit per-brand `AdminAssignment`. Founder and Super Admin are
not platform grants and never bypass tenant isolation.

"All D8N" is a view/scope that fans out into independently authorized
brand requests. An operator receives data only from brands where they
have an active assignment. Cross-brand member/report identifiers remain
neutral 404s. A true platform grant remains deferred and requires a new
ADR.

## 3. Central capability model

`Admin::Capabilities` is the one capability vocabulary and role mapping.
`Admin::AuthorizationContext` resolves the current assignment and
capabilities. Controllers declare required capabilities; they do not
inspect role names.

Current capabilities:

- `hq.member.sensitive_read`
- `hq.member.security_read`
- `hq.discovery_diagnostics.read`
- `hq.trust_safety.read`
- `admin.reports.read`
- `admin.reports.moderate`
- `admin.enforcements.manage` (legacy compatibility)
- `admin.enforcements.read`
- `admin.enforcements.create`
- `admin.enforcements.reinstate`
- `admin.enforcements.override`
- `hq.security_alerts.read`
- `admin.profile_photos.moderate`
- `admin.operators.read`
- `admin.operators.manage`
- `admin.brand_operations.manage`
- `hq.system.read` (reserved for the existing later phase)
- `hq.analytics.read` (derivable Operations overview; event-pipeline analytics remain future)

Capability changes are security-sensitive code changes. Seed rows provide
role vocabulary/descriptions only and cannot silently change authority.

## 4. Role semantics

- **Founder:** bootstrap-only root operator for each explicitly assigned
  brand. May grant Super Admin and lower roles. Cannot be created or
  changed through the operator API.
- **Super Admin:** full current operational capabilities for an explicitly
  assigned brand. May manage only non-Founder/non-Super-Admin roles.
- **Operations:** Member 360/security/discovery and Trust & Safety reads,
  operator read, and brand-operations capability; no moderation mutation.
- **Trust & Safety:** sensitive Member 360/security reads, Trust & Safety,
  report decisions, enforcement, and profile-photo moderation.
- **Support:** Member 360 and discovery diagnostics only.
- **Engineering:** discovery diagnostics and the future System read
  capability; no Member 360 identity or moderation access.
- **Marketing:** future Analytics read only; no Phase 1/2 sensitive access.
- **Analyst:** future Analytics read only; no Phase 1/2 sensitive access.
- **Moderator:** compatibility role preserving the previously shipped
  Member 360, Trust & Safety, reports, enforcement, and photo-moderation
  surface. It cannot manage operators.

Founder and Super Admin have the same current data/action capabilities.
Their meaningful difference is delegation: only Founder can create or
manage Super Admin. Founder itself remains offline-bootstrap-only. Neither
has cross-brand authority without explicit assignments.

## 5. Endpoint capability requirements

| Surface | Capability |
| --- | --- |
| Member 360 summary | `hq.member.sensitive_read` |
| Member security/auth/enforcement history | `hq.member.security_read` |
| Discovery diagnostic | `hq.discovery_diagnostics.read` |
| Trust & Safety overview/repeat offenders/history | `hq.trust_safety.read` |
| Report queue/detail | `admin.reports.read` |
| Report transition | `admin.reports.moderate` |
| Suspend/reinstate | `admin.enforcements.manage` |
| Profile-photo queue/decision | `admin.profile_photos.moderate` |
| Operator list | `admin.operators.read` |
| Operator assignment/change/revocation | `admin.operators.manage` plus centralized grant rules |

Every row also requires the host-derived current-brand assignment and MFA.

## 6. Admin/operator management

The current phase implements brand-scoped operator management only:

- list at most 100 current-brand assignments;
- assign an existing D8N identity that already has an active membership
  on the current brand;
- change role or assignment status (`active`, `suspended`, `revoked`);
- return effective capabilities and MFA enrollment state;
- audit every successful assignment change.

The API does not create credentials, consumer membership, Founder, or a
platform grant. It does not expose passwords, credential rows, session
tokens, MFA secrets, or recovery codes. An actor cannot change their own
assignment, touch a Founder, manage a Super Admin unless they are Founder,
or grant a role outside `Admin::RolePolicy`.

`AdminUser.status` remains a global emergency control and is deliberately
not mutable through this brand-scoped API. Assignment revocation is the
correct current-brand access removal mechanism and takes effect on the
next request.

## 7. Mandatory admin MFA

ADR 0021 implements RFC 6238 TOTP with the existing mandatory Active
Record Encryption keys:

- secret encrypted at rest;
- enrollment is inactive until a valid TOTP confirmation;
- eight random recovery codes are returned once and stored only as keyed
  digests;
- each recovery code is consumed atomically once;
- verification is per session and bound to the active MFA credential;
- credential reset/rotation immediately invalidates all prior step-up;
- invalid enrollment/challenge/reset proofs are audited and throttled;
- reset requires an already stepped-up session plus a fresh TOTP or
  recovery-code proof;
- offline reset is a deliberately confirmed, audited break-glass task.

No security questions exist. No frontend flag can mark a session verified.

## 8. Audit requirements and implementation

Existing moderation mutations retain their transactional audit records.
Phase 1/2 sensitive reads retain their `SecurityEvent` events. Foundation
events add:

- MFA enrollment started/confirmed/failed;
- MFA challenge succeeded/failed, without the supplied code;
- MFA reset and offline break-glass reset;
- operator assigned and assignment changed, with before/after role/status.

Audit metadata contains internal actor/target IDs and minimal non-sensitive
state. TOTP secrets, recovery codes, passwords, report evidence, message
content, email/phone search text, and session tokens are never copied into
audit metadata.

## 9. PII and minimum necessary access

The Phase 1/2 response restrictions remain unchanged: no credentials or
token digests, no unrestricted message/conversation viewer, no raw media,
and report evidence only through the existing bounded audited report
detail. Role separation now further limits which operators can reach those
responses. Brand isolation and neutral not-found behavior remain
structural.

The Member Directory uses the existing `hq.member.sensitive_read`
capability and returns a deliberately smaller presentation than Member 360:
public/profile identifiers, display name, account and membership state,
profile/publication state, signup time, latest brand-session activity,
boolean email/phone verification state, report/photo queue counts, and an
active-enforcement boolean. It never returns email addresses, phone numbers,
session details, credentials, message content, or verification payloads.

All roles currently granted `hq.member.sensitive_read` receive this same
compact directory shape: Founder, Super Admin, Operations, Trust & Safety,
Support, and the compatibility Moderator role. Engineering, Analyst, and
Marketing do not receive directory access because they do not hold that
capability. This keeps the policy small and capability-based while applying
minimum necessary data to the directory itself; Member 360 remains the more
sensitive, separately authorized read.

## 10. Operational launch gates

Backend implementation alone does not pass the production gate. Before HQ
uses real staging/production member data:

1. deploy/migrate and seed the canonical roles;
2. upgrade the existing founder's legacy Moderator assignments with
   `d8n:bootstrap_founder`;
3. enroll Founder MFA and store recovery codes offline;
4. verify role matrix, wrong-brand denial, revocation, and MFA semantics in
   staging;
5. verify `/api/v1/version` returns the baked 40-character git SHA;
6. complete frontend integration/verification for Phase 1 and Phase 2.

No Phase 3/HQ-010 work is part of this gate.

## 11. Enforcement and security-alert policy

Enforcements are brand-scoped and use one durable record with `kind` set to
`suspension` or `ban`. Creation requires `admin.enforcements.create`; reversal
requires `admin.enforcements.reinstate` (or the Founder/Super Admin override
capability). Ban creation requires a reason; all actions may include an
internal note and are recorded as `SecurityEvent` audit events. Operations and
Trust & Safety can create enforcement, while only Founder and Super Admin can
reverse or override it. `GET /api/v1/hq/security_alerts` provides a bounded,
brand-scoped in-console feed of warning/high/critical security events and is
authorized by `hq.security_alerts.read`.
