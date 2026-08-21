# DateZA

## Executive Product Specification

**Product:** DateZA
**Parent Platform:** D8N
**Market:** South Africa
**Category:** Online Dating
**Status:** MVP / Initial Build
**Architecture:** DateZA Frontend → D8N Core API

---

# 1. Executive Summary

DateZA is a modern dating platform built for South Africa and for people genuinely interested in dating people in South Africa.

At its core, DateZA is intentionally a **standard, easy-to-understand dating application**:

**Discover → Like → Match → Chat → Meet**

Its differentiation is not hundreds of unusual dating features.

DateZA differentiates itself through three major problems that mainstream dating applications still struggle with:

1. **Trust** — Is this person actually who they claim to be?
2. **Behaviour** — Is this a genuine member who behaves appropriately on the platform?
3. **Compatibility** — Beyond appearance, are these two people actually likely to suit one another?

DateZA addresses these through D8N's:

* **RealMe Verification**
* **Trust & Reputation System**
* **Compatibility Engine**
* **AI Matchmaker**

The goal is simple:

> **Make online dating be real the problem we are solving is trust and to become the go to place when you are looking for serious relationship in South Africa.**

---

# 2. Product Vision

DateZA should become a trusted place to meet genuine people across South Africa.

The platform should bring together people across:

* cities
* provinces
* cultures
* languages
* races
* backgrounds
* lifestyles
* sexual orientations
* relationship intentions

It should also welcome people outside South Africa who genuinely want to meet and date people in South Africa.

DateZA should feel unmistakably South African without becoming overloaded with cultural gimmicks.

The product remains dating first.

---

# 3. Core Product Promise

## Real people. Better matches.

DateZA combines normal online dating with identity verification, reputation signals and intelligent matchmaking.

Every major product decision should strengthen at least one of:

### Identity

**Is this person real?**

Powered by RealMe.

### Trust

**Does this account behave like a genuine member?**

Powered by D8N Trust.

### Compatibility

**How well might these two people fit?**

Powered by D8N Compatibility.

### Discovery

**Who should this person meet next?**

Powered by the DateZA discovery system and AI Matchmaker.

---

# 4. Core Dating Loop

DateZA must first succeed as a normal dating product.

The primary loop is:

**Create account**

↓

**Build profile**

↓

**Complete RealMe verification**

↓

**Discover people**

↓

**Like or pass**

↓

**Mutual like creates match**

↓

**Conversation**

↓

**Meet**

↓

**Return to DateZA**

AI, trust scoring and verification should improve this loop rather than complicate it.

---

# 5. Account & Authentication

Users must be able to:

* register
* sign in
* sign out
* reset password
* verify email
* verify phone
* manage sessions
* deactivate account
* permanently delete account

Authentication is provided by D8N Core.

A D8N account must support brand membership so DateZA does not require an entirely independent authentication architecture.

---

# 6. Onboarding

Onboarding should be attractive, quick and progressive.

Do not ask 40 questions before allowing someone to see the product.

## Required onboarding

### Identity

* display name
* date of birth
* gender
* interested in
* location

### Dating

* relationship intention
* preferred age range
* preferred distance/location

### Profile

* profile photos
* short bio

### Basic compatibility

A small number of high-value questions covering:

* children
* smoking
* drinking
* religion/faith importance
* lifestyle
* relationship goals

Additional information can be collected after onboarding through profile completion prompts.

---

# 7. Profiles

Profiles should feel rich without becoming CVs.

## Core profile

* profile photos
* display name
* age
* approximate location
* bio
* occupation
* relationship intention
* interests
* languages
* lifestyle
* children
* wants children
* smoking
* drinking
* religion/faith — optional
* education — optional
* height — optional
* profile prompts
* RealMe status
* compatibility score where applicable

Users control appropriate optional fields and visibility.

Exact residential location must never be publicly displayed.

---

# 8. Photos & Media

Photos are central to dating discovery.

Users should be able to:

* upload multiple photos
* choose a primary photo
* reorder photos
* delete photos
* replace photos

D8N handles:

* storage
* safe delivery
* metadata removal
* moderation
* image processing
* access control

DateZA should encourage clear photographs showing the actual person.

---

# 9. RealMe

RealMe is DateZA's identity and authenticity system.

It answers:

> **Is there evidence that this account belongs to a real person who matches the identity being presented?**

## Verification ladder

Possible verification signals:

**Email Verified**

**Phone Verified**

**Selfie Verified**

**Photo Verified**

**Video/Liveness Verified**

**ID Verified**

Not every verification level must be required to use DateZA.

Higher verification creates greater confidence.

---

# 10. RealMe Verified

Users who meet the required RealMe threshold receive:

## RealMe Verified ✓

This should be visually prominent across DateZA.

It can appear on:

* discovery cards
* profiles
* likes
* matches
* conversations

Users should be able to tap the badge and understand what has actually been verified.

RealMe must never claim that a verified person is automatically trustworthy or safe.

Verification establishes identity signals, not character.

---

# 11. Trust System

Identity verification alone does not solve dating fraud.

A real person can still behave badly.

D8N therefore maintains a separate Trust system.

It answers:

> **How trustworthy does this account appear based on its activity and behaviour on D8N?**

Potential signals include:

* verification level
* account age
* profile completeness
* suspicious messaging patterns
* spam behaviour
* mass messaging
* repeated reports
* moderation outcomes
* suspicious links
* financial solicitation
* impersonation indicators
* repeated account creation
* abnormal account behaviour
* enforcement history

---

# 12. Trust Score

D8N may maintain detailed internal risk and trust scores.

DateZA should NOT expose raw fraud models or sensitive moderation logic.

The frontend can instead present understandable trust indicators such as:

**New Member**

**Building Trust**

**Good Standing**

**Strong Standing**

**RealMe Verified**

The exact model can evolve as D8N obtains real behavioural data.

The Trust system must not become a popularity contest.

Users should not receive higher trust merely because they receive many likes or are considered attractive.

---

# 13. Compatibility

Compatibility is separate from Trust.

Trust evaluates an account.

Compatibility evaluates a **pair of users**.

Example:

## 91% Match

Another person viewing the same profile may receive:

## 73% Match

Compatibility may consider:

* relationship intention
* age preferences
* location
* children
* desire for children
* smoking
* drinking
* religion/faith importance
* lifestyle
* interests
* languages
* communication preferences
* personality/profile questions
* user-defined dealbreakers

Hard incompatibilities should matter more than superficial similarities.

---

# 14. Explainable Compatibility

DateZA should not display unexplained AI-generated percentages.

Users should be able to select:

## Why 91%?

And receive useful explanations such as:

**You both want a long-term relationship.**

**You both want children.**

**Neither of you smokes.**

**You share 6 interests.**

**Your preferred lifestyles are similar.**

**You both prefer meeting rather than chatting indefinitely.**

Compatibility should help people make decisions.

It should not pretend to predict love.

---

# 15. AI Matchmaker

AI Matchmaker is the intelligent layer above DateZA discovery.

Instead of requiring endless swiping, DateZA can periodically present particularly promising people.

## Your Matches for Today

For example:

**Naledi, 29**

**94% compatible**

> You both want something serious, share similar family goals and lifestyles, and have several common interests.

**See why we matched you →**

The AI Matchmaker uses structured D8N compatibility data rather than inventing compatibility from profile text alone.

---

# 16. Conversational Matchmaker

A later evolution can allow natural-language discovery.

Example:

> Show me verified women around Cape Town between 27 and 35 who want something serious and want children.

Or:

> I'm open to Johannesburg too. Show me people with high compatibility.

AI translates the request into authorised discovery criteria.

The model must never bypass privacy settings, discovery eligibility or platform safety rules.

---

# 17. Discovery

The default discovery experience should remain extremely simple.

## For You

Primary personalised feed.

Uses:

* preference eligibility
* compatibility
* activity
* location
* profile quality
* trust
* freshness

## New Here

Recently joined eligible users.

## Nearby

People geographically relevant to the user.

## Verified

RealMe Verified members.

Additional discovery modes should only be introduced when user behaviour justifies them.

---

# 18. Discovery Card

A discovery card should communicate enough information to make a decision quickly.

Include:

* primary photo
* display name
* age
* approximate location/distance
* RealMe badge
* compatibility percentage
* relationship intention
* selected interests
* short bio
* online/recent activity where appropriate

Primary actions:

**Pass**

**Like**

**View Profile**

---

# 19. Likes

Users can like eligible profiles.

A like does not automatically create a conversation.

Users can:

* like
* pass
* see appropriate incoming likes based on entitlement
* remove a like where supported

Daily limits can be used for abuse prevention and monetisation.

---

# 20. Matches

A mutual like creates a match.

When a match occurs:

> **It's a Match!**

Users can then:

* open the profile
* start conversation
* unmatch
* block
* report

Matching should feel celebratory and emotionally rewarding.

---

# 21. Messaging

Messaging becomes available after matching.

## MVP

* text
* emoji
* image sharing
* delivery state
* read state where appropriate
* block
* report
* unmatch

Later:

* voice notes
* short video
* richer media

Messaging safety systems should monitor obvious scam and abuse signals without unnecessarily interfering with normal conversations.

---

# 22. Scam & Abuse Protection

D8N should detect or flag patterns associated with:

* financial solicitation
* crypto/investment scams
* suspicious URLs
* mass messaging
* repeated copy/paste messages
* impersonation
* stolen media
* harassment
* threats
* automated accounts
* account farming
* ban evasion

DateZA can provide contextual warnings when appropriate.

Example:

> **Stay safe. Never send money or financial information to someone you haven't established trust with.**

---

# 23. Block, Report & Unmatch

These are mandatory core features.

## Report categories

* Fake profile
* Scam
* Asked for money
* Spam
* Harassment
* Threats
* Sexual misconduct
* Underage user
* Hate/discrimination
* Stolen photos/impersonation
* Other

Serious reports enter D8N moderation workflows.

Safety functionality must never require a paid subscription.

---

# 24. Search & Filters

Basic filters:

* age
* distance/location
* gender/preferences
* relationship intention

Advanced filters may include:

* RealMe Verified
* children
* wants children
* smoking
* drinking
* religion
* languages
* lifestyle
* interests

Avoid creating dozens of filters at launch.

The AI Matchmaker should eventually reduce the need for complicated filter screens.

---

# 25. South African Layer

DateZA should feel South African primarily through its people, language, content, locations and brand—not through unnecessary product complexity.

Support:

* South African provinces
* cities
* local languages
* South African relationship context
* people living in South Africa
* South Africans abroad
* people genuinely open to dating South Africans

Users may optionally express cultural identity where useful.

DateZA should not infer race, ethnicity, religion or cultural background.

---

# 26. Notifications

Users should receive useful notifications for:

* new like
* new match
* new message
* verification updates
* profile moderation
* important account/security events
* subscription events

Channels can include:

* in-app
* email
* push
* SMS only where justified

Avoid notification spam.

---

# 27. Monetisation

Do not over-engineer subscriptions before product-market validation.

## Free

* create profile
* discovery
* limited likes
* matches
* messaging
* basic filters
* RealMe verification
* block/report
* privacy controls

## DateZA+

Potential features:

* increased/unlimited likes
* see who likes you
* advanced filters
* rewind
* travel/change location
* incognito controls
* enhanced discovery

Later premium features can be tested from actual user behaviour.

Never paywall basic safety.

---

# 28. Admin & Moderation

D8N Admin must support DateZA.

Administrators need:

* DateZA user management
* profile review
* photo/media moderation
* verification review
* reports
* suspensions
* bans
* appeals where supported
* Trust signals
* risk flags
* user search
* audit history
* platform metrics

Cross-brand D8N information should only be exposed to authorised administrators.

---

# 29. Analytics

DateZA should measure the dating funnel rather than vanity metrics alone.

Important metrics:

* registrations
* onboarding completion
* profile completion
* verification completion
* active users
* discovery sessions
* likes sent
* mutual matches
* match rate
* conversations started
* reply rate
* conversations reaching meaningful depth
* reports
* blocks
* retention
* subscription conversion

For RealMe specifically:

**Does verification increase reply and match quality?**

For AI:

**Do AI-recommended matches create better conversations than ordinary discovery?**

Those are important product questions.

---

# 30. D8N Architecture

DateZA must NOT have an independent dating backend.

## Architecture

**DateZA Web / Mobile**

↓

**D8N API**

↓

**D8N Core**

Shared capabilities:

* accounts
* authentication
* brand membership
* profiles
* media
* RealMe
* Trust
* compatibility
* discovery
* likes
* matches
* messaging
* moderation
* reporting
* blocking
* notifications
* subscriptions
* analytics

DateZA provides the brand-specific presentation and configuration.

---

# 31. Brand Isolation

D8N must understand which brand every relevant operation belongs to.

A DateZA request should carry DateZA context.

Brand-scoped concepts include:

* membership
* profile presentation
* discovery
* likes
* matches
* conversations
* subscriptions
* entitlements
* moderation context
* analytics

D8N may share appropriate account-level trust and identity signals across its ecosystem internally.

It must not accidentally expose activity from HookUs, Date9ja or another D8N brand inside DateZA.

---

# 32. What DateZA Owns

The DateZA frontend owns:

* visual identity
* landing page
* registration experience
* onboarding presentation
* discovery UI
* profile UI
* RealMe presentation
* compatibility presentation
* AI Matchmaker UI
* likes UI
* matches UI
* messaging UI
* settings
* subscriptions UI
* South African terminology
* marketing pages

Business logic that should be reusable across brands belongs in D8N Core.

---

# 33. MVP

## P0 — Must Work

1. Registration/login
2. Onboarding
3. Profiles
4. Photo upload
5. Discovery
6. Like/pass
7. Matches
8. Messaging
9. Block
10. Report
11. Account deletion
12. RealMe verification
13. Basic Trust status
14. Compatibility score
15. Compatibility explanation
16. Notifications
17. DateZA admin support

If these are excellent, DateZA is a viable dating product.

---

# 34. P1 — Differentiate

After the standard dating loop works:

1. AI Matchmaker
2. Better compatibility modelling
3. Advanced RealMe
4. Improved Trust engine
5. See who likes you
6. Advanced filters
7. subscriptions
8. push notifications
9. enhanced scam detection
10. richer profile prompts

---

# 35. P2 — Earned Complexity

Do not build these merely because they sound interesting.

Possible future capabilities:

* conversational AI Matchmaker
* date planning/check-in
* voice notes
* video messaging
* events
* curated introductions
* diaspora discovery
* travel mode
* deeper relationship insights

Build them when actual usage demonstrates the need.

---

# 36. Explicitly Out of MVP

DateZA V1 does **not** need:

* stories
* social feeds
* public comments
* rooms
* livestreaming
* marketplace
* gifts
* coins
* complex gamification
* dozens of discovery modes
* personality tests with 100 questions
* AI chat companions
* mandatory ID verification
* complicated cultural scoring
* DateZA-specific duplicate backend services

DateZA should be extremely good at dating before becoming anything else.

---

# 37. Product Moat

The moat is not:

> We have profiles and swiping.

Everyone has those.

The long-term D8N advantage should become:

## Identity Graph

RealMe understands whether accounts correspond to genuine humans.

## Trust Graph

D8N develops signals around how accounts behave.

## Compatibility Graph

D8N learns which combinations of preferences, behaviours and characteristics produce successful interactions.

## Match Intelligence

AI uses those systems to make increasingly useful introductions.

As additional D8N dating brands use the platform, the underlying technology can improve while each brand remains a distinct experience.

---

# 38. Product Principles

### Dating first.

Do not let AI overshadow attraction and human interaction.

### Trust visible.

Users should immediately understand whether someone has completed RealMe.

### AI must be useful.

Do not add AI badges to ordinary filtering and call it artificial intelligence.

### Explain recommendations.

Users deserve to know why someone was recommended.

### Safety is free.

Never monetize basic safety.

### Privacy by default.

Collect only what is necessary and expose only what users expect.

### Progressive complexity.

Launch the smallest product capable of proving DateZA.

### D8N owns reusable intelligence.

DateZA consumes platform capabilities rather than recreating them.

---

# 39. Success Definition

DateZA succeeds when users stop thinking:

> **“Is this profile even real?”**

and start thinking:

> **“I actually want to meet this person.”**

The product should move users through:

**Real person**

↓

**Trustworthy enough to engage**

↓

**Potentially compatible**

↓

**Match**

↓

**Conversation**

↓

**Real-world connection**

That is DateZA.

---

# 40. North Star

# **DATEZA**

## **Date for real. 🇿🇦**

**RealMe Verified.**

**Trust that is earned.**

**Compatibility that makes sense.**

**AI that helps you find your person.**

And underneath all of it:

> **A genuinely good dating app.**


# DateZA Discovery & Find

DateZA has **two primary ways to meet people**:

1. **Discovery — DateZA chooses for you**
2. **Find — you choose for yourself**

They should not be merged into one swipe feed.

---

# 1. Discovery — 10 Matches a Day

## Purpose

Discovery is DateZA's intelligent matchmaking experience.

Every day, DateZA gives each eligible user up to:

# **10 Matches For You**

These are not simply 10 random nearby profiles.

They are selected using D8N's matchmaking and compatibility system.

The objective is:

> **Less endless swiping. More people actually worth meeting.**

## Ranking Signals

Discovery can consider:

* mutual gender/dating eligibility
* age preferences
* location preferences
* relationship intentions
* compatibility
* interests
* lifestyle
* children/family goals
* language preferences
* user dealbreakers
* RealMe status
* Trust standing
* activity/recency
* profile quality

Hard preferences and eligibility rules are applied before ranking.

AI should help rank and explain recommendations rather than invent matches independently.

---

# 2. Discovery Card

Each recommended person should clearly show:

**Photo**

**Name · Age**

**Location**

**RealMe Verified ✓**

**92% Match**

**Looking for: Long-term relationship**

and selected profile information.

Users can:

**Like**

**Pass**

**View Profile**

**Why this match?**

---

# 3. Why This Match?

This is an important DateZA differentiator.

Selecting the compatibility score can explain:

> **92% Match**
>
> You both want a long-term relationship.
>
> You have compatible family plans.
>
> Neither of you smokes.
>
> You share 5 interests.
>
> You're both looking for someone within the same area.

This makes DateZA's matchmaking understandable rather than presenting a mysterious AI number.

---

# 4. Daily Refresh

Discovery refreshes with up to **10 recommendations per day**.

Example:

> **Your 10 for today**
>
> We picked these people for you based on what you're looking for and who we think you're most compatible with.

The limited set is intentional.

Discovery should feel curated rather than infinite.

---

# 5. Find — Explore Yourself

**Find** is different.

Find gives users control over whom they want to explore.

It is the familiar swipe/browse dating experience.

Users can search within their eligible dating pool and swipe through profiles.

## Free users

Free users receive:

# **10 Find profiles/swipes per day**

After reaching the daily allowance:

> **That's your 10 for today.**
>
> Come back tomorrow for more, or upgrade to keep exploring.

The exact paid allowance can be determined when subscriptions are implemented.

---

# 6. Find Filters

Find supports basic user-controlled filters.

Free/basic filters:

* age range
* distance/location
* gender/dating preference
* relationship intention

Potential DateZA+ filters:

* RealMe Verified only
* languages
* children
* wants children
* smoking
* drinking
* religion/faith
* lifestyle
* interests
* additional compatibility preferences

Find should not become a complicated database search interface.

---

# 7. Discovery vs Find

The distinction must remain clear throughout the product.

## Discovery

**DateZA finds people for you.**

* 10 recommendations daily
* compatibility-driven
* personalised
* ranked by D8N
* compatibility score
* match explanation
* quality over quantity

## Find

**You explore for yourself.**

* swipe/browse
* user-controlled
* filter-driven
* 10 free profiles/swipes daily
* upgrade path for additional exploration

This creates two complementary dating behaviours:

> **Don't feel like searching? Check Discovery.**

> **Know what you want? Use Find.**

---

# 8. Navigation

The primary authenticated DateZA navigation should therefore include:

**Discovery**

**Find**

**Likes**

**Matches / Messages**

**Profile**

Discovery should be the default home experience.

---

# 9. AI Matchmaker Relationship

The AI Matchmaker should primarily improve **Discovery**.

It determines which eligible users deserve one of the limited 10 daily recommendation slots.

Over time it learns from signals such as:

* likes
* passes
* matches
* compatibility
* preference changes
* conversations
* user feedback
* successful recommendations

It should **not** learn that attractiveness/popularity automatically means compatibility.

Trust and safety signals can remove or down-rank unsuitable accounts.

---

# 10. The DateZA Daily Loop

The intended behaviour becomes:

**Open DateZA**

↓

### **Discovery**

See my **10 selected matches for today**

↓

Like / Pass / View why we match

↓

### **Find**

Want to explore further?

Swipe through **10 free profiles**

↓

Mutual Like

↓

### **Match**

↓

### **Chat**

↓

### **Meet**

This gives DateZA a very understandable daily product loop:

# **10 we choose for you.**

# **10 you choose for yourself.**

That distinction should be treated as a **core DateZA product rule**, not merely a subscription limitation.
