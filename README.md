# D8N — Global Dating Technology Group

## Developer Reference

- [API integration guide](docs/api/README.md)
- [OpenAPI 3.1 contract](docs/api/openapi.yaml)
- Runtime JSON contract: `GET /api/v1/openapi.json`
- Interactive Swagger UI: `GET /api/docs`
- Architecture decisions: [`docs/adr/`](docs/adr/)

## Company Master Blueprint

**Company:** D8N
**Pronunciation:** “Dating”
**Category:** Dating Technology / Consumer Internet / Social Discovery
**Structure:** Parent Company + Shared Technology Platform + Portfolio of Dating Brands
**Ambition:** Build the infrastructure, brands and experiences powering how people meet around the world.

---

# 1. Executive Summary

D8N is a global dating technology company building a portfolio of dating, matchmaking, social discovery and human-connection products.

The fundamental belief behind D8N is simple:

**There should not be one dating app for everyone.**

People date differently depending on culture, country, religion, age, lifestyle, sexuality, relationship intentions and community.

Instead of forcing all of those people into one generic dating experience, D8N builds focused products designed specifically for them.

Each D8N brand can have its own:

* Identity
* Community
* Personality
* Target market
* Matching philosophy
* Monetization strategy
* Relationship intention
* Cultural experience

But underneath those brands sits one shared technology platform.

That platform provides:

* Identity
* Authentication
* Profiles
* Matching
* Recommendations
* Messaging
* Verification
* Trust & safety
* Fraud detection
* AI
* Payments
* Moderation
* Analytics
* Notifications
* Events
* Administration
* Infrastructure

D8N therefore operates as both:

**1. A portfolio of consumer dating brands**

and

**2. A dating technology platform**

The long-term objective is to build one of the world's most extensive ecosystems for dating and human connection.

---

# 2. Vision

## Our Vision

**To build the world's dating network.**

D8N wants to become the company behind millions of introductions, conversations, relationships, experiences and marriages around the world.

Not through one giant dating application.

Through an ecosystem of products built for the different ways humans choose to connect.

---

# 3. Mission

Our mission is to build trusted technology and culturally relevant products that make meeting the right person easier, safer and more human.

We accomplish this through:

* Specialized dating brands
* Localized dating experiences
* Identity verification
* Better matching technology
* AI-assisted matchmaking
* Community
* Real-world experiences
* Trust and safety infrastructure

---

# 4. Core Philosophy

## One dating app cannot serve everyone well.

A Nigerian professional living in London searching for marriage has fundamentally different needs from:

* A university graduate dating in Johannesburg
* Someone looking for something casual
* A Christian searching specifically for another Christian
* Someone visiting Lagos for December
* A divorced person dating again at 45
* Someone looking for a culturally compatible spouse
* Someone interested primarily in social experiences
* Someone using a professional matchmaking service

Most global dating companies attempt to put everyone inside the same product.

D8N takes the opposite approach.

### Different people.

### Different cultures.

### Different intentions.

### Different products.

### One D8N.

---

# 5. D8N Company Architecture

D8N operates across four major layers.

## Layer 1 — D8N Group

The parent organization.

Responsible for:

* Corporate strategy
* Capital allocation
* Brand portfolio
* Technology
* Data
* Security
* Legal infrastructure
* Trust & safety standards
* Shared operations
* Research
* New market expansion

---

## Layer 2 — D8N Platform

The shared technical infrastructure powering D8N products.

Potential internal platform modules:

* D8N ID
* D8N Profiles
* D8N Verify
* D8N Trust
* D8N Match
* D8N Graph
* D8N Chat
* D8N AI
* D8N Pay
* D8N Notify
* D8N Events
* D8N Insights
* D8N Admin

---

## Layer 3 — Consumer Brands

Independent dating products serving specific markets and intentions.

Initial portfolio:

### Date9ja

Dating for Nigerians and the Nigerian diaspora.

Core positioning:

**Find someone who understands where you come from.**

Primary focus:

* Serious dating
* Relationships
* Marriage
* Nigerian culture
* Diaspora connections
* Trust
* Verification
* Compatibility

---

### HookUs

A more open, attraction-first social and dating product.

Core positioning:

**Meet. Vibe. See where it goes.**

Potential focus:

* Casual dating
* Social discovery
* Experiences
* Dating intentions
* Travel connections
* Events
* Adult relationship exploration
* P2P marketplace/community features

HookUs remains clearly separated from marriage-oriented brands such as Date9ja.

---

### DateSA

Dating designed around South Africa.

Potential localization:

* Provinces
* Cities
* Languages
* Cultural communities
* Lifestyle
* Relationship intentions
* Local events

---

### DateAussie

Dating focused on Australia.

Potential audience:

* Australians
* Immigrants
* International professionals
* Diaspora communities
* Serious dating
* Local social discovery

---

## Layer 4 — Experiences

D8N eventually extends beyond swiping.

Products can include:

* Singles events
* Matchmaking
* Dating communities
* Travel experiences
* Dating concierge
* Relationship coaching
* Introductions
* Speed dating
* Social activities
* Group experiences
* Premium clubs

---

# 6. D8N Platform

The D8N Platform is one of the company's most important long-term assets.

Instead of every new D8N brand rebuilding dating technology, common capabilities are built once and reused.

---

# 7. D8N ID

Universal identity infrastructure.

Responsibilities:

* Account creation
* Authentication
* Email
* Phone numbers
* Social login
* Device management
* Account recovery
* Session management
* Security
* Age eligibility
* Account status

A user may eventually maintain a D8N identity while participating in different D8N products.

However, cross-product identity must respect privacy and user consent.

Being on one D8N platform should never automatically expose participation on another.

---

# 8. D8N Profiles

Shared profile infrastructure.

Supports:

* Photos
* Videos
* Bios
* Interests
* Location
* Languages
* Culture
* Education
* Career
* Lifestyle
* Religion
* Relationship intentions
* Dating preferences
* Compatibility questions

Individual brands determine which fields they use.

Date9ja might emphasize:

* Ethnicity
* Nigerian state
* Religion
* Diaspora status
* Marriage intentions

HookUs may emphasize:

* Attraction
* Availability
* Experiences
* Dating intentions
* Lifestyle

The infrastructure remains shared while the experience remains unique.

---

# 9. D8N Verify

Identity and authenticity infrastructure.

Potential verification ladder:

### Level 1

Email verification

### Level 2

Phone verification

### Level 3

Selfie verification

### Level 4

Video/liveness verification

### Level 5

Government ID verification

Optional additional checks:

* Social account verification
* Professional verification
* Address verification
* Background checks
* References

Verification status becomes an important trust signal throughout D8N.

---

# 10. D8N Trust

Trust and safety should become a major competitive advantage.

D8N Trust manages:

* User reports
* Blocking
* Harassment detection
* Scam detection
* Fake profile detection
* Duplicate accounts
* Romance scam patterns
* Suspicious messaging
* Account takeovers
* Photo moderation
* Sexual content moderation
* Spam
* Financial solicitation
* Underage protection
* Moderation cases
* Appeals
* Safety history

Every interaction can generate safety signals.

Example:

A newly created account that immediately messages 70 people with nearly identical text should automatically receive additional scrutiny.

---

# 11. D8N Trust Score

Internally, D8N can maintain a dynamic risk/reputation model.

Signals could include:

* Account age
* Verification
* Reports
* Blocks
* Messaging patterns
* Login anomalies
* Device history
* Spam behavior
* Successful dates
* Community participation
* Moderator decisions

The internal score should primarily inform risk controls rather than publicly labeling people as “good” or “bad.”

---

# 12. D8N Match

Shared matching infrastructure.

The matching engine should support multiple strategies.

Examples:

### Attraction Matching

Used for fast discovery.

### Compatibility Matching

Based on:

* Values
* Lifestyle
* Religion
* Family goals
* Children
* Finances
* Personality
* Relationship expectations

### Cultural Matching

Important for products such as Date9ja.

### Intent Matching

Matches users based on what they actually want.

Examples:

* Marriage
* Long-term relationship
* Dating
* Casual
* Friendship
* Travel companion
* Social activities

### Behavioral Matching

Recommendations improve based on actual behavior.

---

# 13. D8N Graph

Over time D8N can develop a proprietary relationship graph.

It can understand patterns such as:

* Who attracts whom
* Which conversations become meaningful
* Which matches produce replies
* Which matches survive beyond initial contact
* Which recommendations result in dates
* Which compatibility factors predict successful connections

The objective is not maximizing swipes.

The objective is improving the probability of a valuable connection.

---

# 14. D8N Chat

Shared communication infrastructure.

Capabilities:

* Text
* Images
* Video
* Voice notes
* Reactions
* Read receipts
* Typing indicators
* Message requests
* Blocking
* Reporting
* Safety prompts
* Moderation
* Spam detection

Future:

* Voice calls
* Video calls
* AI conversation assistance
* Translation
* Date planning

---

# 15. D8N AI

AI can eventually operate throughout the ecosystem.

Potential products include:

### AI Matchmaker

Instead of endless swiping:

> “Find me someone compatible.”

The system can recommend a small number of high-quality introductions.

### Profile Assistant

Helps users improve:

* Photos
* Bios
* Prompts
* Profile completeness

### Dating Assistant

Can help with:

* Conversation ideas
* Date planning
* Compatibility questions
* Relationship communication

### Safety AI

Detects:

* Romance scams
* Manipulation
* Spam
* Harassment
* Suspicious requests
* Fraud patterns

### Moderator AI

Assists human moderators by prioritizing risky cases.

AI should assist safety decisions rather than blindly making irreversible high-impact moderation decisions.

---

# 16. D8N Pay

Shared commerce infrastructure.

Supports:

* Subscriptions
* Premium membership
* Profile boosts
* Super likes
* Matchmaking
* Event tickets
* Marketplace transactions
* Gifts
* Concierge services

Payment providers can vary by market.

The D8N abstraction should allow brands to use appropriate regional processors without rebuilding billing logic.

---

# 17. D8N Events

Digital dating should lead to real-world connections.

D8N Events can power:

* Singles nights
* Speed dating
* Cultural events
* Dinner experiences
* Travel experiences
* Group activities
* Professional singles events
* Faith-based events
* Premium matchmaking events

Events can operate across multiple D8N brands.

---

# 18. D8N Insights

Shared analytics infrastructure.

Every brand should understand its marketplace.

Core metrics:

### Acquisition

* Visitors
* Registrations
* Cost per registration
* Acquisition channel

### Activation

* Profile completion
* Photo uploaded
* Verification completed
* First like
* First match
* First conversation

### Engagement

* DAU
* WAU
* MAU
* Messages
* Likes
* Matches
* Conversations

### Marketplace Health

Dating platforms are two-sided marketplaces.

Measure:

* Gender distribution
* Orientation distribution
* Geographic liquidity
* Active users per city
* Match availability
* Response rates
* Match rates

### Retention

Track:

* D1
* D7
* D30
* D90

### Safety

Track:

* Reports
* Blocks
* Scam detections
* Suspensions
* Appeals
* Verification rates

### Revenue

Track:

* MRR
* ARR
* ARPU
* Conversion
* Churn
* LTV
* CAC

---

# 19. D8N Admin

One operating console should eventually manage the entire portfolio.

Possible structure:

**D8N Command Center**

Select brand:

Date9ja
HookUs
DateSA
DateAussie
Future brands

Administrators can view:

* Users
* Moderation
* Verification
* Reports
* Revenue
* Growth
* Engagement
* Infrastructure
* Fraud
* Events
* Customer support

Permissions must be role-based.

A DateSA moderator should not automatically receive access to Date9ja users.

---

# 20. Brand Factory

One of D8N's major advantages should eventually become its ability to launch new dating products quickly.

Instead of:

**Idea → 12 months engineering → launch**

D8N should aim toward:

**Market → Brand → Configuration → Localization → Launch**

A new product chooses:

* Brand
* Domain
* Market
* Languages
* Matching strategy
* Profile questions
* Verification requirements
* Pricing
* Features
* Community rules

The D8N Platform handles the rest.

---

# 21. Market Expansion Model

D8N should not launch everywhere simultaneously.

New markets should meet specific criteria.

Evaluate:

### Market size

How many potential users?

### Dating behavior

Are dating apps culturally accepted?

### Existing competition

What problem remains unsolved?

### Community

Can D8N reach the first several thousand users?

### Monetization

What are users willing to pay for?

### Localization

Does the market require unique cultural understanding?

### Network effects

Can sufficient local dating liquidity be created?

---

# 22. Portfolio Strategy

Not every idea requires another brand.

Create a new D8N brand when there is a genuinely distinct:

* Audience
* Culture
* Relationship intention
* Community
* Experience
* Brand promise

Otherwise, build the capability inside an existing brand.

This prevents D8N from becoming a graveyard of tiny dating applications.

---

# 23. Cross-Brand Network

Long-term, users could optionally discover compatible people elsewhere in the D8N network.

Example:

A Date9ja user living in Johannesburg may opt into:

**Expand discovery to compatible D8N members.**

They could potentially meet someone from another appropriate D8N community.

This should always be:

* Explicit
* Opt-in
* Privacy-preserving
* Appropriate to both users' intentions

This turns independent apps into a much larger dating network without destroying their individual identities.

---

# 24. D8N Passport

A future concept worth exploring.

**D8N Passport** could represent a portable verified identity across participating D8N products.

Potentially carries:

* Age verification
* Phone verification
* Selfie verification
* ID verification
* Safety eligibility

It should not automatically carry private dating activity or expose which brands someone uses.

The principle:

**Verify once. Date safely across the network.**

---

# 25. Business Model

D8N should eventually generate revenue from multiple sources.

## Consumer Subscriptions

Premium dating memberships.

## Microtransactions

* Boosts
* Super likes
* Priority discovery
* Profile enhancements

## Matchmaking

Premium human-assisted matchmaking.

## Events

Ticketed singles experiences.

## Concierge

High-end dating assistance.

## Marketplace

Commission from appropriate marketplace transactions.

## B2B Technology

Long-term D8N infrastructure can potentially be licensed externally.

Possible offerings:

* Verification API
* Trust API
* Chat infrastructure
* Matching API
* Moderation platform
* White-label dating platform

---

# 26. D8N Platform as a Service

The eventual opportunity extends beyond D8N-owned products.

Imagine:

**Build your dating community with D8N.**

A church, university alumni network, cultural association, media company or entrepreneur could launch a dating community powered by D8N.

D8N supplies:

* Accounts
* Profiles
* Matching
* Chat
* Verification
* Moderation
* Payments
* Mobile infrastructure
* Analytics

The partner supplies:

* Brand
* Community
* Audience

D8N becomes infrastructure for the broader dating industry.

---

# 27. Competitive Moat

The defensibility of D8N should eventually come from several layers.

### Technology

Years of specialized dating infrastructure.

### Trust Network

Identity and risk intelligence.

### Matching Intelligence

Understanding what produces meaningful connections.

### Portfolio

Multiple brands sharing technology.

### Localization

Deep understanding of individual markets.

### Distribution

Existing dating communities make subsequent launches easier.

### Data

Aggregated, privacy-conscious learning improves matching and safety systems.

### Operating Knowledge

D8N learns how to launch and operate dating marketplaces repeatedly.

---

# 28. Privacy Principles

Because D8N operates intimate social products, privacy must be foundational.

Principles:

1. Collect only information needed for a defined purpose.
2. Protect sensitive dating information.
3. Never expose cross-brand participation without consent.
4. Separate internal access by role.
5. Encrypt sensitive information.
6. Maintain auditable administrative access.
7. Give users meaningful privacy controls.
8. Provide account deletion and data-management capabilities.
9. Clearly explain how recommendations work where practical.
10. Build safety without creating unnecessary surveillance.

---

# 29. Security Architecture

Eventually:

### Authentication

Centralized identity with secure tokens and session management.

### Authorization

Role-based and service-level permissions.

### Encryption

TLS everywhere.

Sensitive information encrypted at rest where appropriate.

### Secrets

Dedicated secret-management infrastructure.

### Audit Logs

Administrative actions recorded.

### Rate Limiting

Protect:

* Login
* Registration
* Messaging
* Likes
* Verification
* Password reset

### Abuse Protection

Device and behavioral risk analysis.

### Backups

Automated database backups with tested restoration procedures.

---

# 30. Suggested Technical Architecture

D8N should not prematurely become a giant microservice architecture.

Early architecture should remain practical.

A strong initial approach:

### Backend

Ruby on Rails

### Database

PostgreSQL

### Cache / Fast State

Redis where required

### Background Processing

Dedicated job workers

### Realtime

WebSockets / Action Cable or dedicated realtime infrastructure as scale requires

### Web

React / Next.js where appropriate

### Mobile

React Native

### Object Storage

S3-compatible object storage such as R2

### Containers

Docker

### Deployment

Kamal initially

### CDN / Edge

Cloudflare

As D8N grows, high-demand components can gradually become dedicated services.

Potential future services:

* Identity Service
* Matching Service
* Messaging Service
* Verification Service
* Moderation Service
* Recommendation Service
* Notification Service
* Payment Service

Do not build them prematurely.

Extract services when scale, organizational ownership or reliability requires it.

---

# 31. Multi-Tenant Architecture

Eventually D8N Platform should understand the concept of:

**Brand / Tenant**

For example:

```text
D8N Platform

Tenant: DATE9JA
Tenant: HOOKUS
Tenant: DATESA
Tenant: DATEAUSSIE
```

Each tenant can configure:

* Branding
* Domain
* Languages
* Features
* Profile fields
* Matching rules
* Pricing
* Verification
* Notifications
* Moderation policies

This is how D8N becomes capable of launching products rapidly.

---

# 32. Shared vs Brand-Specific Data

Not everything should be centralized.

## Shared

Potentially:

* Identity
* Verification status
* Security
* Infrastructure
* Platform telemetry

## Brand-specific

Generally:

* Dating profile
* Likes
* Matches
* Conversations
* Dating preferences
* Relationship activity

Cross-brand processing must have a legitimate product purpose and appropriate consent/privacy controls.

---

# 33. Internal Developer Platform

Eventually developers working on D8N should be able to create a brand using configuration rather than duplicating applications.

Conceptually:

```bash
d8n create brand
```

Then:

```text
Brand name:
Market:
Domain:
Languages:
Relationship type:
Verification level:
Payments:
Matching engine:
```

The platform generates the necessary configuration.

Long-term objective:

**Launching a dating brand becomes configuration, not reconstruction.**

---

# 34. D8N Design System

D8N should maintain a shared component library.

Examples:

* Profile Card
* Photo Gallery
* Verification Badge
* Match Modal
* Chat
* Report Flow
* Block Flow
* Subscription
* Onboarding
* Discovery
* Safety Center

Brands customize:

* Typography
* Colors
* Photography
* Motion
* Tone
* Layout
* Personality

This maintains engineering efficiency without making every D8N product look identical.

---

# 35. Organization

Long-term organizational structure:

## D8N Group

### CEO / Founder

Vision, strategy, capital and portfolio.

### CTO / Platform Engineering

Shared infrastructure.

### Chief Product

Product strategy.

### Trust & Safety

Safety operations and systems.

### Growth

Acquisition and retention.

### Data / AI

Matching, recommendations and intelligence.

### Brand Teams

Each major product eventually has its own small team.

Example:

**Date9ja**

Product Lead
Engineering
Growth
Community
Moderation

Shared D8N infrastructure reduces the number of people each individual brand requires.

---

# 36. Company Flywheel

The D8N flywheel should become:

**Launch product**

↓

**Acquire community**

↓

**Observe dating behavior**

↓

**Improve matching**

↓

**Improve trust infrastructure**

↓

**Improve platform**

↓

**Launch next product faster**

↓

**More users**

↓

**More learning**

↓

**Better D8N infrastructure**

↓

**Stronger portfolio**

Each successful brand strengthens the next.

---

# 37. Roadmap

## Historical Product Roadmap

The sequence below predates the accepted implementation direction in `PLAN_OF_ACTION.md` and is retained as product-strategy context. The current engineering sequence builds HookUs first and uses Date9ja as the live migration and second-brand proof target.

## Phase 1 — Prove the Model

Primary focus:

**Date9ja**

Objectives:

* Acquire real users
* Improve onboarding
* Improve matching
* Improve retention
* Build verification
* Improve messaging
* Establish safety operations
* Understand marketplace dynamics

Date9ja becomes D8N's laboratory.

---

## Phase 2 — Extract the Platform

Identify reusable Date9ja systems.

Extract:

* Authentication
* Profiles
* Messaging
* Verification
* Moderation
* Notifications
* Analytics

Turn them into reusable D8N components.

---

## Phase 3 — Second Brand Validation

Use HookUs as an important test.

Can the same infrastructure support a completely different dating proposition?

If yes, the platform thesis becomes much stronger.

---

## Phase 4 — Geographic Expansion

Launch selected geographic brands.

Potential examples:

DateSA
DateAussie
Additional African markets
Diaspora-focused products

Expansion should follow demand, not merely available domain names.

---

## Phase 5 — D8N Network

Introduce optional cross-brand infrastructure:

* D8N Passport
* Shared verification
* Cross-network discovery
* Shared safety intelligence
* Shared events

---

## Phase 6 — D8N AI

Develop proprietary:

* Matchmaking models
* Safety intelligence
* Recommendation systems
* AI dating assistants
* Moderator tooling

---

## Phase 7 — D8N Platform

Open selected infrastructure to third parties.

**Powered by D8N**

Partners can launch their own dating communities using D8N infrastructure.

---

# 38. What D8N Should NOT Become

D8N should not become a collection of 50 nearly identical dating websites.

Avoid:

* Copying Date9ja and changing the flag
* Launching brands without communities
* Premature microservices
* Chasing every dating niche
* Sacrificing safety for growth
* Collecting unnecessary personal data
* Sharing user activity between brands without consent
* Optimizing purely for addictive swiping
* Building infrastructure before it is required

Every D8N product needs a reason to exist.

---

# 39. Success Metrics

D8N's ultimate success should not be measured simply by registrations.

Important north-star metrics could include:

### Meaningful Conversations

Matches producing sustained two-way communication.

### Successful Introductions

Users reporting meaningful offline connections.

### Safety

Percentage of interactions occurring without safety incidents.

### Dating Liquidity

Probability that a qualified active user can find compatible people nearby.

### Retention

Users returning because there are valuable people to meet.

### Verified Network

Percentage of active users reaching meaningful verification levels.

### Portfolio Efficiency

How much faster and cheaper D8N can launch each subsequent brand.

---

# 40. Brand Architecture

Recommended corporate hierarchy:

```text
                         D8N
               Global Dating Technology

                         │
          ┌──────────────┼──────────────┐
          │              │              │

      CONSUMER        PLATFORM       EXPERIENCES
       BRANDS

          │              │              │
      Date9ja          D8N ID        D8N Events
      HookUs           D8N Match     Matchmaking
      DateSA           D8N Verify    Concierge
      DateAussie       D8N Trust     Communities
      Future Brands    D8N Chat      Travel
                       D8N AI
                       D8N Pay
                       D8N Insights
```

---

# 41. Corporate Positioning

## Short

**D8N is a global dating technology company building products that help people meet, connect and build relationships.**

## Medium

**D8N builds dating products for different cultures, communities and relationship intentions, powered by shared technology for identity, matching, communication, trust and safety.**

## Investor / Corporate

**D8N is building a portfolio of specialized consumer dating brands on top of a shared technology platform for identity, matching, messaging, verification, trust, payments and AI. Rather than forcing every user into a single global dating product, D8N creates focused experiences for distinct communities while leveraging shared infrastructure, intelligence and network effects across the portfolio.**

---

# 42. Tagline System

### Corporate

**Building the world's dating network.**

### Technology

**The infrastructure behind human connection.**

### Portfolio

**Different people. Different ways to date. One D8N.**

### Platform

**Powered by D8N.**

### Vision

**Everyone deserves the right place to meet someone.**

---

# 43. The Long-Term D8N Story

Today D8N may begin with a handful of dating products.

But that is not the destination.

The destination is an ecosystem.

Someone could discover Date9ja because they want to meet another Nigerian.

Their identity is protected by D8N Verify.

Their recommendations are generated by D8N Match.

Their conversations run through D8N Chat.

Potential fraud is detected through D8N Trust.

They attend a D8N-powered singles event.

Another company launches a specialized dating community using D8N Platform.

A completely different D8N brand serves millions of users on another continent.

Users may never need to know how much infrastructure exists underneath their experience.

They simply know that the product understands them.

Behind those experiences sits D8N.

One company.

Multiple brands.

Multiple cultures.

Multiple ways of connecting.

One increasingly intelligent, safe and scalable infrastructure for dating.

---

# 44. Ultimate Ambition

The ambition is not:

**“Build several dating apps.”**

The ambition is:

**Build the company that knows how to build dating companies.**

Build the identity infrastructure.

Build the trust layer.

Build the matching intelligence.

Build the communication network.

Build the communities.

Build the brands.

Build the real-world experiences.

Then make every new D8N company faster and easier to launch than the one before it.

## D8N

**Building the world's dating network.**

**Different people. Different ways to date. One D8N.**
