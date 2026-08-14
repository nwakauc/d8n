# Later, When Justified

These ideas are intentionally outside the controlled HookUs private-beta gate.
They should move into an active milestone only when product requirements, user
volume, incidents, measured bottlenecks, legal advice, or a second implementation
create evidence for them.

## Do Not Build Before Beta Without New Evidence

- [ ] Enterprise or highly generic RBAC. Beta needs narrowly scoped admin roles,
  explicit brand authorization, MFA, and audited sensitive actions.
- [ ] A formal in-product appeals case-management system. Support can handle the
  initial appeal path.
- [ ] Sophisticated evidence-retention infrastructure or a generic legal-hold
  engine. Use an approved, bounded beta retention policy first.
- [ ] Mandatory MFA for ordinary dating users. Admin MFA is required because
  administrators can access sensitive dating data.
- [ ] Microservices, Kubernetes, event streaming, or a platform-wide event/outbox
  architecture. Add a transactional handoff only where a concrete workflow proves
  it is needed.
- [ ] WebSocket chat, presence, typing indicators, reactions, replies, message
  search, or attachments. Polling and text-only messages are the beta product.
- [ ] A general-purpose image/media platform, video, or many generated variants.
  Private R2, safe re-encoding, EXIF removal, moderation state, authorized delivery,
  and durable deletion are enough initially.
- [ ] Infrastructure sized for 10,000 concurrent users or purchased before a
  measured need. Begin with the small web/worker/PostgreSQL/R2 topology in the
  scaling guide.
- [ ] PostGIS, precomputed recommendations, read replicas, or matching-service
  extraction before query plans and load tests demonstrate a bottleneck.
- [ ] Google login, WebAuthn, user MFA, payments, identity-document verification,
  Date9ja migration, another D8N brand, or external operator access before the
  HookUs beta loop is stable unless product strategy explicitly reprioritizes it.
- [ ] More architecture documents that merely restate accepted ADRs or this TODO
  tracker. Prefer deleting stale duplication and recording only real decisions.

## Promotion Rule

When promoting an item, record:

1. the evidence that changed;
2. the smallest useful scope;
3. the milestone and owner;
4. the acceptance evidence;
5. any ADR or founder decision required before implementation.

