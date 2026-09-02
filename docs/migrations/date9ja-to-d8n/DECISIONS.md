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
| Approved photo publication | Prevents surprise hiding or re-review loops | Media/Moderation | Yes | Preserve approved state; review exceptions; full re-review | Awaiting Uchechi |
| Founding/premium access to retain | Prevents loss or accidental grant of paid access | PAY/Entitlements | Yes | Migrate active entitlement; time-bound bridge; exception queue | Awaiting Uchechi |
| Historical profile-view visibility | Determines whether and how history is exposed | Engagement/Profile Views | Yes if retained | Full history; recent window; archive-only | Awaiting Uchechi |
| User-visible trust score/history | A raw score may misrepresent safety status | Trust | Yes if visible | Derived badge; score plus explanation; history private | Awaiting Uchechi |
| Material support-chat behavior | Determines whether support appears as a special inbox or ordinary conversation | Messaging/Support | Only if behavior changes | Shared support surface; conversation specialization; approved bridge | Awaiting Uchechi only if behavior changes |
| Active-surface retirement | Only explicit product retirement may remove a reachable feature | All | Yes | Retain all; formally retire named surface | Awaiting Uchechi |

## Engineering / architecture

| Decision | Why it matters | Required before |
|---|---|---|
| D8N AI assistant contract and domain boundary | Defines runtime, provider isolation, tools, safety, and brand configuration | AI implementation `SPECIFIED` |
| AI provider data egress, retention, redaction, logging, credentials, consent, fallback, and cost controls | Aunty Phobie may process sensitive user conversations | AI implementation `SPECIFIED` |
| Verification evidence model and retention | Evidence is sensitive and may have provider dependencies | Verification implementation `SPECIFIED` |
| Engagement/profile-view domain boundary | Avoids duplicate history and notification semantics | Engagement implementation `SPECIFIED` |
| Community shared-capability boundary | Community is in parity but must not become a Date9ja fork | Community implementation `SPECIFIED` |
| Dating Hub primitive decomposition and ownership | Prevents copying the legacy monolith | Dating Hub implementation `SPECIFIED` |
| Trust ledger and derived reputation architecture | Separates auditable events from user-visible status | Trust implementation `SPECIFIED` |
| Genotype privacy/model architecture | Determines whether data is modelled, encrypted, or excluded | Any genotype modelling/import |
| Legacy operational mapping to D8N HQ | Ensures safe administration before legacy retirement | Legacy admin retirement |

## Mixed

| Decision | Product question | Engineering question | Status |
|---|---|---|---|
| Entitlements | What legacy/founding/premium access is retained? | How PAY/Entitlements represents and enforces it | Product pending; engineering follows |
| Trust presentation | What do users see? | How ledger/events produce that status | Product pending; architecture required |
| Verification provider use | Which user-visible checks are retained? | Which providers, evidence boundaries, and retention rules are safe? | Product/security pending |

Support-chat ownership is no longer a pure product decision: engineering owns the reusable architecture investigation and returns only material user-visible choices. Founder/admin operations are settled as D8N HQ scope, not Date9ja consumer parity; remaining HQ operational gaps are tracked in the matrix operational register.
