# D8N — The Portfolio Operating System (Marketing, Social & SEO)

**Version:** 1.0 draft
**Status:** Operating document — open this every morning
**Source of truth:** repo README.md, `docs/hookus/README.md`, ADR 0015–0018, migration/cutover docs
**Scope:** D8N as a Dating Technology Group, and each brand running on it — Date9ja, HookUs, DateZA, (DateAussie — concept-stage)
**Stage:** pre-public-launch. Date9ja: mid-migration, cutover-ready. DateZA: private-beta MVP. HookUs: re-platforming onto shared D8N core. **Dates/targets below are placeholders** — swap in real cutover/launch dates.

Companion docs (same operating-system format, different categories): `docs/WELOID_MARKETING_OS.md` (Weloid) and `docs/JUSTJAPA_MARKETING_OS.md` (JustJapa) if colocated in this workspace.

---

## 0. How to use this document

This is not one content calendar — **D8N has no single audience.** A 24-year-old on HookUs looking for tonight and a 34-year-old on Date9ja looking for a spouse must never see the same brand voice, the same account, or in most cases the same ad. This document has two layers on purpose:

- **§1–§4: the portfolio layer.** What's true about D8N as a company, and the one story that's honest to tell across every brand at once (trust, safety, verification infrastructure) — this is investor/press/recruiting content, not consumer content.
- **§5 onward: per-brand playbooks.** Each brand gets its own thesis, doors, franchises, and calendar, run by people who understand that specific audience. Never let one social lead run all three brands' voices — that's how Date9ja starts sounding like HookUs, which is a trust failure, not a tone slip.

**Non-negotiables**

1. Never post a real user's profile, photo, message, or match — not even blurred, not even "with permission" without a signed, renewable release specific to the post (§9.2). Dating apps lose users the instant they suspect their data is content.
2. HookUs content is **18+ by construction** — every platform's ad and content policy for dating/adult-adjacent apps applies from day one, not as an afterthought (§9.3).
3. No brand's marketing implies or jokes about infidelity, brand-hopping between D8N properties, or "which app should I cheat on my partner with" framing. The brands are audience-separated by *intent*, not a wink-wink menu.
4. Every post has one CTA. On a dating app the highest-value CTA is usually "download" or "verify," not "match now" — you cannot manufacture urgency around another person's attention.

---

## 1. The portfolio thesis

Every dating app claims "find real connections." Almost none can credibly claim **who's actually behind the profile** — and that credibility gap is where every dating-app horror story lives: catfishing, romance scams, ghost accounts, people who turn out to be married, married people who turn out to be scammers. D8N's actual structural advantage is that verification, trust, and safety are built once, shared across every brand, and enforced identically — which means the story we're allowed to tell is not "swipe more," it's:

> **We built the dating infrastructure company first, and the apps second.**

That's unusual enough to be a real trade press / investor narrative, separate from any single brand's consumer marketing. Say it to press, recruiters, and partners. Never say it to a HookUs or Date9ja user — they don't care about your infrastructure, they care that the person in the next chat is real.

### 1.1 What's shared vs. what's separate

| Shared (D8N core, invisible to users but provable to press/investors) | Separate per brand (all user-facing marketing) |
| --- | --- |
| D8N Verify — email → phone → selfie/liveness → government ID, optional social/professional/address/background checks | Brand name, voice, visual identity |
| D8N Trust — reporting, blocking, scam/fake-profile/duplicate detection | Target audience & intent (marriage vs. casual vs. local) |
| CapabilityCatalog — rich, brand-configurable profile taxonomy (ADR 0017) | Feature set exposed (e.g. Hook is HookUs-only) |
| Match/Chat/Pay core | Social accounts, ad accounts, App Store listings |
| Discovery/status infra (verified, online, last-active, distance) | Content calendar, franchises, tone |

### 1.2 Why now

- **Verification anxiety is the #1 unmet need in African and diaspora dating apps.** Scam and catfishing stories circulate constantly (WhatsApp groups, Twitter threads, "I got scammed on [app]" content already exists organically) — nobody has made verification the headline feature instead of a settings-page checkbox.
- **Casual and serious intent are being forced onto the same apps everywhere else**, producing exactly the mismatch that makes both audiences distrust the platform. D8N's actual answer — separate brands, same safety spine — is a structurally honest response to a real complaint people already make.
- **Diaspora-specific dating (Date9ja, and eventually DateAussie) is underserved** by apps built for a default-Western user; culture, language, and family-context matter in ways generic apps ignore.

### 1.3 Positioning ladder — portfolio level only

1. **Category (press/investor only):** a dating infrastructure company running multiple purpose-built consumer brands, not a single app trying to be everything to everyone.
2. **Proof:** the verification ladder, the trust/reporting system, and — where true — real fraud/catfish-prevention numbers once live.
3. **Brand layer:** each brand is marketed independently from here down. See §5–§7.

---

## 2. The brand portfolio

| Brand | Audience | Intent | Geography | Stage | Distinct mechanic |
| --- | --- | --- | --- | --- | --- |
| **Date9ja** | Nigerians + diaspora | Serious, marriage-oriented | Nigeria + global diaspora | Mid-migration, cutover-ready | Culture/trust-forward profile depth |
| **HookUs** | Verified adults, 18+ | Casual, attraction-first (hookups, nightlife, travel, couples/groups) | Broad, urban-skewed | Re-platforming onto D8N core | **Hook** + **Hook Tonight** (§6) |
| **DateZA** | South Africans | General dating, locality-aware (provinces, cities, languages, cultural communities) | South Africa | Private-beta MVP | Local-market depth (in progress) |
| **DateAussie** | Australians + immigrants/diaspora | General dating | Australia | **Concept-stage — not yet built.** Do not market. | — |

> **DateAussie is a portfolio placeholder, not a product.** It appears in internal roadmap docs with an audience line and nothing else. Do not create social accounts, landing pages, or any public content for it until product work starts — a dormant, unmaintained brand account is worse than none.

---

## 3. Cross-cutting trust & safety — the portfolio's real moat

This is the one asset every brand can borrow from without diluting its own voice, because it's infrastructure, not personality.

- **D8N Verify ladder** — email, phone, selfie/liveness, government ID, and optional social/professional/address/background checks. Marketable claim once numbers exist: *"X% of profiles on [brand] are ID-verified"* — publish this per brand, not blended, since verification rates will differ by audience risk-tolerance.
- **D8N Trust** — reporting, blocking, and detection for harassment, scams, fake profiles, and duplicates.
- **Discovery status fields** — real verified/online/last-active/distance signals, not decorative badges — a genuine content hook ("how we tell you someone's actually online right now" is a legitimate ELI5-style explainer).

**Use this to build trust content per brand** (see franchises below), never as a standalone "D8N the company is safe" campaign aimed at consumers — consumers choose a brand, not a holding company.

---

## 4. Guardrails that apply to every brand, before anything else

### 4.1 User content is never marketing content by default

1. No real profile, photo, bio, chat excerpt, or match outcome is used in any public post without a signed, dated, renewable release naming the specific use (a blog post permission is not an ad permission).
2. Screenshots used for product demos use seeded/sample accounts built for that purpose, clearly not real users.
3. Never publish anything that could re-identify a user even anonymized (unique bio details, rare job/location combos, a screenshot with a visible partial username).

### 4.2 HookUs-specific: this is an adults-only brand, market it like one from day one

- Every ad platform (Meta, TikTok, Google, X) has separate, stricter policies for dating apps with casual/adult-adjacent positioning — confirm current ad-account category and creative restrictions *before* the first paid post, not after a rejection.
- App store listing must carry the correct age rating; marketing screenshots and store copy must match what the reviewed app actually shows, or risk delisting.
- Content can be playful and frank about casual intent without being sexually explicit in public/organic posts — explicit content pushes brands off mainstream platforms entirely and this brand needs mainstream reach to grow.
- Never target or imply a minor-adjacent framing (no "teen," "college freshman," school-uniform aesthetics, etc.) — this is both a platform-policy and legal bright line.

### 4.3 Date9ja-specific: cultural respect, not cultural costume

- Content made *by* Nigerian/diaspora team members and creators, reviewed by them — not written from outside the culture and translated into slang.
- Marriage/family-oriented messaging must never read as pressuring or shaming single users — same emotional-shame trap as any dating brand, handled with warmth.

### 4.4 Cross-brand firewall

- No shared social accounts, no "check out our other app" cross-promotion between HookUs and Date9ja/DateZA — the audiences chose different intents on purpose, and a visible link between "the hookup app" and "the marriage app" from the same company damages trust in both.
- The parent-company/portfolio story (§1) can appear in press, investor decks, and careers content, never in consumer-facing brand content.

### 4.5 Crisis protocol (dating-specific)

If a safety incident is reported publicly (a bad date, a scam, an assault allegation): never respond defensively or minimize; acknowledge, direct to the in-app reporting/support channel, and only comment publicly on process ("here's what our Trust & Safety flow does when a report comes in"), never on the specific incident. Legal and Trust & Safety review before any public statement — this overrides the "respond within 2 hours" engagement rule everywhere else in this doc.

---

## 5. Date9ja — brand playbook

### 5.1 Thesis

> **Find someone who understands where you come from.**

Date9ja's edge isn't more profiles, it's *legible* profiles — culture, family context, and intent stated plainly instead of guessed at. The honest positioning against generic apps: "you shouldn't have to explain your own culture to the person you're dating."

### 5.2 Doors

| Door | Who | Needs |
| --- | --- | --- |
| D1 "I'm serious about marriage" | Nigerian professional, home or diaspora | Verified, intent-aligned matches |
| D2 "I want someone who gets my background" | Diaspora Nigerian, tired of explaining culture from scratch | Shared-context matching |
| D3 "I've been scammed or catfished before" | Anyone burned by an unverified app | Verification-forward proof |
| D4 "My family will ask about this person" | Marriage-track user | Depth of profile (family, values, intent fields) |

### 5.3 Franchises (weekly, tone: warm, culturally specific, never generic-diaspora)

- **Culture & Compatibility** — what actually matters when dating across Nigerian ethnic/cultural lines, explained by people who live it.
- **Verified Stories** *(with signed release only)* — real (permissioned) success stories, told with the verification badge as part of the story, not incidental.
- **Ask Before You Match** — the questions Date9ja users say they wish they'd asked earlier.
- **Diaspora Diaries** — dating while abroad but rooted at home; homesickness, distance, family expectation.

### 5.4 Launch note

Date9ja is a **migration**, not a cold launch — real prior users exist. The first communication wave is a *"we've upgraded, here's what's better and what's the same"* message to existing users, not top-of-funnel awareness content. Get this sequencing wrong and existing users read silence as the app dying, or a surprise relaunch as a data-privacy scare.

---

## 6. HookUs — brand playbook

### 6.1 Thesis

> **Meet. Vibe. See where it goes.**

HookUs is explicitly casual — hookups, nightlife, 420-friendly, couples/group connections, travel — deliberately separated from the marriage-oriented brands, with its own philosophy: *be real, be yourself, be respectful, be safe.* The marketing thesis: casual doesn't mean careless — verification and consent-forward design apply here as much as anywhere, arguably more.

### 6.2 The flagship mechanic: Hook + Hook Tonight

This is the single most marketable, structurally unique thing in the entire D8N portfolio, and it's HookUs-exclusive:

- **Hook** — a one-shot, high-intent opener. You get exactly one unsolicited message to someone — no spray-and-pray DMs — and you're locked out until they reply. Their first reply is an instant unlock, no mutual double-opt-in friction.
- **Hook Tonight** — a temporary 6-hour "I'm available tonight" broadcast state feeding a *reciprocal-access* discovery pool: you have to be available yourself to browse who else is available right now.

Both mechanics solve a real, nameable frustration with existing hookup-adjacent apps (endless unanswered DMs, matches that go nowhere, no sense of who's actually free tonight) — this is TEACH/BUILD content gold: explain the mechanic plainly, let the product be the hook (no pun avoidable).

### 6.3 Doors

| Door | Who | Needs |
| --- | --- | --- |
| D1 "I want something casual tonight" | Available now, low-friction | Hook Tonight pool |
| D2 "I'm tired of ghosting/unanswered DMs" | Burned by generic swipe apps | One-shot Hook mechanic |
| D3 "I want to be upfront about what I want" | Values honesty over games | Intent-forward profile fields |
| D4 "We're a couple/looking for a group connection" | Non-traditional dating configuration | Group/couple-aware discovery |

### 6.4 Franchises (weekly, tone: playful, frank, never explicit)

- **How Hook Actually Works** — plain explainer series, one mechanic detail per post.
- **Tonight Only** — culture content around spontaneity, nightlife, the "I'm free right now" energy — never explicit, always platform-safe.
- **Be Real / Be Safe** — the brand's own stated philosophy, turned into a recurring safety-and-consent content series (verification, boundaries, reporting).
- **Vibe Check** — light, funny, relatable dating-culture content; the brand's "no shame in wanting what you want" register.

### 6.5 Launch note

HookUs is re-platforming onto the shared D8N core, which likely means an existing (smaller) user base is also mid-transition. Confirm ad-platform account standing and content-policy compliance (§4.2) before any paid spend — this brand's growth ceiling is set by platform policy, not creative quality.

---

## 7. DateZA — brand playbook (early stage)

### 7.1 Thesis (working — refine once positioning copy exists)

DateZA's honest current positioning gap: the product doc frames it as locality-aware (provinces, cities, languages, cultural communities) but there's no polished consumer-facing tagline yet, unlike Date9ja and HookUs. **Do not publish consumer marketing until this exists** — writing brand voice without a settled thesis produces generic "find love in South Africa" copy indistinguishable from every other dating app.

### 7.2 What to do now, pre-thesis

- Reserve handles and set up infrastructure (§ portfolio backlog).
- Recruit South African team members/creators to co-write the actual positioning — the same principle as Date9ja's cultural-respect rule (§4.3) applies from the start here, not as a retrofit.
- Build the local-market depth features (languages, cultural communities, provinces) before promising them publicly.

### 7.3 Doors (draft — validate with SA team before use)

| Door | Who | Needs |
| --- | --- | --- |
| D1 "I want to date locally, not generically" | SA user tired of one-size-fits-all apps | Province/city/language-aware matching |
| D2 "I want my community represented" | User from a specific cultural community | Cultural-community-aware profile fields |
| D3 "I've been scammed before" | Same verification-anxiety door as Date9ja | Verification-forward proof |

---

## 8. Content operations — how the three brands run without colliding

| | Date9ja | HookUs | DateZA |
| --- | --- | --- | --- |
| Owner | Nigerian/diaspora social lead | Separate social lead, adults-only trained on ad policy | Not yet resourced — hold until thesis exists |
| Primary platforms | Instagram, TikTok, WhatsApp-adjacent community, YouTube | TikTok, X, Instagram (policy-compliant only) | TBD |
| Cadence | 5–6/week once launched | 5–6/week, ad-policy-gated | None until §7.2 is done |
| Shared resource | D8N Verify/Trust proof points (§3), design system | same | same |

**Do not build one shared content calendar across brands.** Each brand runs its own §5–§7 playbook on its own cadence. The only shared artifact is the portfolio-level trust story (§1, §3) for press/investor/recruiting use.

---

## 9. Guardrail appendix — permission & proof mechanics

### 9.1 The permission ladder for any real-user content

1. Written, dated, specific-use release (a template, not a verbal "sure, go ahead").
2. Re-ask before reuse in a new format or campaign.
3. Default to fabricated/seeded sample accounts for anything that isn't an explicitly permissioned success story.
4. Store proof of every release alongside the asset it authorizes — Trust & Safety and Legal should be able to audit any published user-derived content on request.

### 9.2 Verification-rate claims

Publish verification-rate or safety-outcome numbers only once they're real, current, and per-brand (not blended across the portfolio) — an inflated or stale trust number is the single fastest way to destroy the entire moat described in §3.

### 9.3 Ad-platform compliance checklist (HookUs, before first paid spend)

- Confirm current Meta/TikTok/Google dating-app ad-category status and creative restrictions.
- Confirm App Store/Play Store age rating matches store copy and screenshots.
- Route every ad creative through a policy review pass before scheduling, not after a rejection notice.

---

## 10. Engineering/ops backlog to support this

| # | Item | Why | Priority |
| --- | --- | --- | --- |
| 1 | Per-brand UTM + attribution on signup/verification funnel | Without it, brand-level performance is guesswork | **P0** |
| 2 | Signed release/permission tracking system for user-derived content | Enforces §9.1 at the process level, not just the editorial one | **P0** |
| 3 | Per-brand verification-rate dashboard, real and current | Backs every §3 trust claim with a live, reviewable number | **P1** |
| 4 | Confirm HookUs ad-account category/policy status across platforms | Blocks §9.3 until resolved | **P0 — before any paid HookUs spend** |
| 5 | Date9ja existing-user migration communication plan (email/push), sequenced ahead of any public relaunch content | Prevents "is the app dying" panic or privacy-scare read on relaunch | **P0 — before Date9ja public content resumes** |
| 6 | DateZA consumer positioning/thesis, co-written with SA team | Blocks all DateZA public content until resolved (§7.1) | **P1** |
| 7 | Separate social/ad accounts per brand, no cross-linking | Enforces §4.4 firewall | **P0 — week 0 of any brand's public launch** |

---

## 11. If you only do five things

1. **Never treat D8N as one brand with three names.** Date9ja, HookUs, and DateZA each need their own voice, their own team member who understands that audience, and their own calendar.
2. **Ship the permission-tracking system before the first user-derived post**, not after the first complaint.
3. **Clear HookUs's ad-platform policy status before spending a cent on it** — this is the one brand where a policy miss can zero out your entire paid channel.
4. **Sequence Date9ja's relaunch as a migration story to existing users first**, awareness content second.
5. **Hold all DateZA public content until the brand has an actual thesis** — a placeholder tagline is worse than silence.

> Every other dating app asks you to trust a stranger.
> D8N asks you to trust the platform first — then lets each brand introduce you to the right stranger.

---

*People are complicated. We verify who they say they are, and let the rest be up to them.*
