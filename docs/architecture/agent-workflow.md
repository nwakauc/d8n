# Superseded D8N Agent Workflow

This predecessor is retained for history only. The authoritative workflow,
capability lifecycle, ownership rules, handoff protocol, and review rules are
in [docs/engineering/AGENT-WORKFLOW.md](../engineering/AGENT-WORKFLOW.md).

Do not update this document with new process rules.

<!--

## Core Rule

Agents implement bounded changes. Agents do not silently invent architecture.

For high-risk areas, propose a short plan before implementation.

High-risk areas:

- Authentication
- Authorization
- Tenancy
- Identity/profile modeling
- Messaging
- Payments
- Verification
- Trust and safety
- Media upload/deletion
- Admin access
- External operator access
- Migrations
- Data deletion/recovery

## Review Pattern

Use one agent to implement and another to review when practical.

The reviewing agent should inspect the specification and diff, not only the implementing agent's summary.

## Test Integrity

Do not modify existing test expectations only to make tests pass.

If a test is wrong, explain why before changing it.

## Legacy Reference

Date9ja is a behavioral reference, not an architecture template.

Implement D8N behavior according to D8N architecture.
-->
