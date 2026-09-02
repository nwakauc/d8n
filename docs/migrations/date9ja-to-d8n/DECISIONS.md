# Date9ja Parity Decision Queue

This is the single queue for unresolved decisions. `CAPABILITY-PARITY.md` is authoritative for retained user capabilities and counts. Durable engineering decisions belong in `docs/adr/`; this queue records the decision needed and its effect.

## Product owner

| Decision | Why it matters | Capability | Blocker | Recommended options | Status |
|---|---|---|---|---|---|
| Retain tribe | Sensitive field may affect display, matching, and migration | Profiles | Yes | Private catalogue; matching-only; archive-only | Awaiting Uchechi |
| Retain ethnicity | Sensitive field may affect display, matching, and migration | Profiles | Yes | Private catalogue; matching-only; archive-only | Awaiting Uchechi |
| Retain denomination | Sensitive field may affect display, matching, and migration | Profiles | Yes | Private catalogue; private-only; archive-only | Awaiting Uchechi |
| Retain preferred tribes | Matching preference affects recommendations | Matching/Profiles | Yes | Typed preference; matching-only; archive-only | Awaiting Uchechi |
| Retain genotype | Sensitive health-adjacent data requires explicit purpose and consent | Profiles/Trust | Yes | Do not migrate; private consented use; archive-only | Awaiting Uchechi |
| Exact verification gates | Determines publication, interaction, and badge behavior | Verification/Trust | Yes | Preserve current gates; staged step-up; approved strengthening | Awaiting Uchechi |
| Approved photo publication | Prevents surprise hiding or re-review loops | Media/Moderation | Yes | Preserve approved state; review exceptions; full re-review | **RESOLVED — preserve legacy behaviour: pending photos visible, rejected excluded (`:immediate` policy). Applies to profile video too (ADR 0023).** |
| Profile video retained | Introduction video is parity | Media | Yes | Retain as shared Media capability | **RESOLVED — retain; ADR 0023; implemented this batch pending review** |
| Verification retained | All shipped/reachable Date9ja verification stays in the bar | Verification/Trust | Yes | Retain all checks/states/badges | **RESOLVED — retain; ADR 0024 defines the architecture; evidence-retention/provider decisions still open (Mixed)** |
| Trust / reputation retained | Existing Trust XP state + history is parity | Trust | Yes | Retain; ledger→derived→presentation | **RESOLVED — retain; ADR 0025; point values migrate verbatim, no new scoring; user-visible presentation still open** |
| Founding/premium access to retain | Prevents loss or accidental grant of paid access | PAY/Entitlements | Yes | Migrate active entitlement; time-bound bridge; exception queue | **RESOLVED — no migrated user loses an existing founding/premium/permanent entitlement; ADR 0026; no new plans/pricing** |
| Historical profile-view visibility | Determines whether and how history is exposed | Engagement/Profile Views | Yes if retained | Full history; recent window; archive-only | Awaiting Uchechi |
| User-visible trust score/history | A raw score may misrepresent safety status | Trust | Yes if visible | Derived badge; score plus explanation; history private | Awaiting Uchechi |
| Material support-chat behavior | Determines whether support appears as a special inbox or ordinary conversation | Messaging/Support | Only if behavior changes | Shared support surface; conversation specialization; approved bridge | Awaiting Uchechi only if behavior changes |
| Active-surface retirement | Only explicit product retirement may remove a reachable feature | All | Yes | Retain all; formally retire named surface | Awaiting Uchechi |

## Engineering / architecture

| Decision | Why it matters | Required before |
|---|---|---|
| D8N AI assistant contract and domain boundary | Defines runtime, provider isolation, tools, safety, and brand configuration | AI implementation `SPECIFIED` |
| AI provider data egress, retention, redaction, logging, credentials, consent, fallback, and cost controls | Aunty Phobie may process sensitive user conversations | AI implementation `SPECIFIED` |
| Verification evidence model and retention | Evidence is sensitive and may have provider dependencies | Verification implementation `SPECIFIED` — **architecture specified in ADR 0024 (Proposed); evidence-retention/provider/portability decisions in "Mixed" below still gate implementation** |
| Profile video / media boundary | Retained parity; must be a shared Media capability, not a Date9ja fork | Profile-video implementation — **ADR 0023 (Proposed); model + pipeline + Date9ja contract implemented this batch pending review** |
| Entitlement preservation model | Existing founding/premium rights must survive cutover without new commercial behaviour | Entitlement implementation `SPECIFIED` — **architecture specified in ADR 0026 (Proposed)** |
| Engagement/profile-view domain boundary | Avoids duplicate history and notification semantics | Engagement implementation `SPECIFIED` |
| Community shared-capability boundary | Community is in parity but must not become a Date9ja fork | Community implementation `SPECIFIED` |
| Dating Hub primitive decomposition and ownership | Prevents copying the legacy monolith | Dating Hub implementation `SPECIFIED` |
| Trust ledger and derived reputation architecture | Separates auditable events from user-visible status | Trust implementation `SPECIFIED` — **architecture specified in ADR 0025 (Proposed); "User-visible trust score/history" product row still gates presentation** |
| Genotype privacy/model architecture | Determines whether data is modelled, encrypted, or excluded | Any genotype modelling/import |
| Legacy operational mapping to D8N HQ | Ensures safe administration before legacy retirement | Legacy admin retirement |
| External legacy reference map (source↔destination binding, immutability, tenant safety) | Deterministic idempotent spine for every importer slice | Wave A slice 2 — **ADR 0022 accepted by independent review; product-owner acknowledgment recorded by normal ADR workflow** |
| bcrypt credential + migrated-account session/recovery compatibility | Authentication-sensitive; needs a sanitized snapshot to prove | Wave A slice 3 `SPECIFIED` |

## Mixed

| Decision | Product question | Engineering question | Status |
|---|---|---|---|
| Entitlements | What legacy/founding/premium access is retained? | How PAY/Entitlements represents and enforces it | Product pending; engineering follows |
| Trust presentation | What do users see? | How ledger/events produce that status | Product pending; architecture required |
| Verification provider use | Which user-visible checks are retained? | Which providers, evidence boundaries, and retention rules are safe? | Product/security pending |

Support-chat ownership is no longer a pure product decision: engineering owns the reusable architecture investigation and returns only material user-visible choices. Founder/admin operations are settled as D8N HQ scope, not Date9ja consumer parity; remaining HQ operational gaps are tracked in the matrix operational register.
