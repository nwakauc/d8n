# ADR 0020: Brand-Scoped Administrative Capabilities

## Status

Accepted for the D8N HQ Phase 1/2 foundation gate on 2026-08-29. This
supersedes only ADR 0013's temporary role-name-blind authorization rule;
ADR 0013's ordinary-session, host-derived-brand, and brand-level
enforcement decisions remain in force.

## Context

ADR 0013 deliberately deferred differentiated administration until real
operator roles existed. D8N HQ now exposes Member 360, security history,
discovery diagnostics, Trust & Safety reads, and existing moderation
mutations. Founder, Super Admin, Operations, Trust & Safety, Support,
Engineering, Marketing, and Analyst are now concrete operator identities,
so an assignment can no longer truthfully mean "all admin power."

The HQ plan selects per-brand fan-out (SECURITY-AND-RBAC.md Option A) for
V1. It does not authorize a platform-wide grant.

## Decision

Authorization is expressed through a central, server-owned capability
catalog. `AdminRole` names map to immutable capability sets in code;
controllers declare the capability required for each action and never
branch on role names. The active `AdminAssignment` for the host-resolved
brand supplies the role. At most one active assignment exists per
admin/brand.

Roles have these security meanings:

- **Founder:** bootstrap-only root operator for an explicitly assigned
  brand. May manage Super Admin and lower roles. It has no implicit access
  to another brand.
- **Super Admin:** may manage non-Founder, non-Super-Admin operators for
  its assigned brand. It cannot create peers or founders.
- **Operations, Trust & Safety, Support, Engineering, Marketing,
  Analyst:** least-privilege operational roles defined by the capability
  catalog. A role may have no currently usable product surface when its
  roadmap phase has not shipped.
- **Moderator:** compatibility role preserving the previously shipped
  report, enforcement, photo-moderation, Member 360, and Trust & Safety
  access. It cannot manage operators.

Founder creation remains an offline, explicit bootstrap operation.
Super Admin creation is permitted only to a Founder with a current,
MFA-verified session. Every assignment change is brand-scoped and
audited. An actor cannot alter their own assignment, grant a role outside
their grantable set, or affect an operator absent from the current brand.

"All D8N" is a frontend/query scope implemented as independently
authorized per-brand requests. It is never an authorization bypass.

## Consequences

- Existing moderator assignments remain functional but now have explicit
  capabilities.
- Revoking the current-brand assignment immediately removes authorization
  for that brand; disabling an `AdminUser` remains a global emergency
  control and is not exposed to ordinary brand-scoped management.
- Adding or changing a role/capability mapping is a security review, not a
  seed-data edit.
- A future platform-wide grant still requires its own ADR.

