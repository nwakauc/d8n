# ADR 0032: Brand-scoped D8N AI with a provider boundary

## Status

Accepted on 2026-09-12 for the initial D8N AI foundation.

## Context

Date9ja has a useful but single-brand OpenAI-backed assistant. D8N needs a
platform capability that can serve multiple brands without a backend fork or a
client dependency on one AI vendor. Dating prompts are sensitive: a provider
integration must not become an implicit export of profiles, private member
messages, media, precise location, identifiers, or verification evidence.

## Decision

D8N owns the `ai.dating_assistant` capability, private brand-scoped
conversation records, private message records, usage accounting, safety
triage, API contract, and rate limit. The initial endpoints are:

```txt
GET  /api/v1/ai/assistants/:assistant_key/conversation
POST /api/v1/ai/assistants/:assistant_key/messages
```

The current assistant key is `dating_assistant`. A conversation belongs to one
`BrandMembership` and has a database brand foreign key; it is never shared with
another profile, membership, or brand. It is soft-deleted during brand closure.

Providers implement one internal `#complete(system_prompt:, messages:)` contract.
`D8N_AI_PROVIDER` selects the process-wide provider; initial supported values
are `disabled` and `openai`. OpenAI credentials and model selection are
deployment environment configuration (`D8N_AI_OPENAI_API_KEY` and
`D8N_AI_OPENAI_MODEL`), never client input or brand content. A provider failure,
bad response, or unsupported configuration maps to the stable, non-diagnostic
`503 assistant_unavailable` response.

The Date9ja assistant receives a safe request-time snapshot of the member's own
profile/preferences and today's already-allocated introductions with their public
compatibility payloads. This lets it help with real app decisions. It never
accesses member-to-member messages, media URLs, identifiers, precise location,
hidden fields, verification evidence, admin data, or Trust records. Other brands
receive no automatic context until their own reviewed policy is added.

Immediate-safety language receives a local safety response without a provider
call. This is guidance only: it is not automated moderation, escalation, or a
promise of human contact. D8N Report/Block remains the actual product safety
path until a reviewed AI-to-Trust escalation workflow exists.

## Consequences

- Date9ja’s proven bounded input, idempotency, transcript persistence, usage
  accounting, provider timeout behavior, and safety redirection are reusable
  without importing its OpenAI-specific service or user-owned tables.
- Clients use a D8N endpoint and stable assistant key; changing provider/model
  does not require a client deployment or data migration.
- The capability is explicitly enabled by each brand contract. Route presence
  does not enable it for an unconfigured brand.
- Prompt text and replies are private content: they are not logged, emitted as
  analytics/security-event metadata, or returned from generic serializers.
- Subscription/entitlement limits, matchmaker profile context, human escalation,
  moderation assistance, legacy Aunty Phobie history import, and legal retention
  policy are intentionally deferred.
