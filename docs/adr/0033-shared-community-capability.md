# ADR 0033: Shared brand-scoped Community capability

## Status

Accepted for implementation on 2026-09-13. This records the Date9ja Community
parity boundary and creates a reusable D8N capability rather than importing the
legacy application's user-owned tables.

## Context

Community is a moderated member-participation product. Date9ja exposes Ask 9ja
questions and answers, success stories, member-submitted events and RSVPs. The
next product definition also requires approved interest Circles with member
discussion. These are brand experiences, but the ownership, moderation,
reporting, media, and RSVP safety primitives are shared D8N concerns.

The legacy implementation is a behavioural reference only. It is single-brand,
uses legacy users rather than brand profiles, has a separate reporting table,
and returns direct Active Storage paths for story video. Those choices do not
meet D8N tenancy, Trust, or Media constraints.

## Decision

D8N owns a `community.*` capability family. Every Community record is owned by
one `Brand` and its author/participant is a `Profile` from that same brand. A
brand must explicitly enable Community; route presence never enables it.

### Participation and moderation

- Questions, stories, events, and new Circles begin pending and are visible
  only to their creator and authorized moderators until approved.
- A creator may edit or soft-delete their own pending or approved submission;
  a material edit returns an approved public submission to pending review.
- Circles are approved rooms. Only a kept Circle member may create a Circle
  post or comment. Circle membership is brand scoped and idempotent.
- Public read paths return approved, kept content only. Owner and moderator
  read paths are explicit and never piggyback on public list scopes.
- Reports use the existing `Trust::FileReport` target-resolver seam. Community
  content does not create a parallel report table, and reports preserve a
  bounded moderator-only evidence snapshot after public deletion.

### Ask 9ja and D8N AI

A question has a seven-day answer window. The weekly selection worker considers
only approved, kept answers for an approved, due question. D8N AI selects one
existing answer; it does not generate or replace a member answer. The result
stores the answer selected, selection timestamp, provider/model provenance and
an auditable selection status. It never makes a moderation decision.

The selection prompt is a deliberately bounded public-content input. It may
contain the question and eligible answers, but never identity identifiers,
private profiles, report data, or hidden/pending content. If the provider is
unavailable or returns an invalid answer identity, the selection stays pending
for retry. A separate, clearly labelled AI reply is allowed only when a member
explicitly invokes the assistant on a conversation; it is not part of weekly
selection.

### Events and stories

Event RSVP is idempotent and capacity-safe under concurrency. The event
organizer and authorized brand administrators may read its attendee roster;
RSVPs are not a public social graph. Story video is owned by D8N Media and is
delivered with the same private, authorization-checked delivery boundary as
other member media. No controller returns an Active Storage blob path.

### Administration and lifecycle

Community review uses the existing admin MFA and brand-scoped capability
boundary, with separate `admin.community.*` permissions. Admin transitions are
audited. Community operational rows soft-delete by default; account closure
anonymizes/tombstones the author's public attribution while preserving shared
content and Trust evidence according to the D8N retention policy.

## Consequences

- Date9ja can receive its Community experience without a backend fork; future
  brands can configure categories, limits, and enabled Community surfaces.
- The first delivery must add database tenant constraints, API/OpenAPI contract,
  approval and report target policies, admin workflows, owner/edit/delete
  behavior, notification plans, and cross-brand authorization tests together.
- Community video requires a small Media extension before a public upload route
  can be enabled. It must not reuse profile-video rows or bypass Media.
- D8N AI selection is asynchronous and may be delayed while the provider is
  unavailable; a question must never be silently assigned an invented answer.

## Alternatives considered

- Copy the legacy Date9ja tables/controllers: rejected because they are not
  tenant safe and duplicate Trust/Media boundaries.
- Make Community a generic unmoderated social feed: rejected because the
  product requires approval workflows and dating-platform safety controls.
- Have AI generate the week's answer: rejected by product decision; AI selects
  an approved community answer and may only chime in when explicitly invoked.
