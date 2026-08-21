# 🔥 HookUs

> **Meet. Vibe. See where it goes.**

HookUs is a global, adults-only dating and social discovery platform built for people who want to be honest about what they are looking for.

Hookups, casual dating, new experiences, nightlife, 420-friendly connections, travel, couples, group connections, adventures and everything in between.

No pretending everyone is looking for marriage.

No endless compatibility questionnaire before seeing another person.

No pressure to turn every connection into a relationship.

**Find people on your wavelength.**

---

## Repo status (read this before touching code)

This repo is **web-only**. `web/` (Next.js) is the only active codebase — it
consumes `/Users/uchechinwaka/pro/d8n`, a separate, shared, multi-brand Rails
platform that also powers Date9ja and future D8N brands. There is no backend in
this repo anymore.

`api/` (a Rails backend forked from Date9ja) was HookUs's original backend and is
now retired to `deprecated/api/`, along with the docs that described it
(`deprecated/docs/`). Do not build against it, run it, or treat it as current —
it exists only as a reference for porting logic into d8n. See
`deprecated/README.md`.

Active docs, in `docs/`:

- `docs/D8N_MIGRATION_PLAN.md` — why this pivot happened and the phased plan.
- `docs/D8N_API_CONTRACT.md` — the contract `web/` integrates against, including
  local-dev setup (d8n requires a provisioned brand + host mapping to resolve any
  request at all).
- `docs/PROJECT_MEMORY.md` — durable decisions and current-state snapshot.
- `docs/HUMAN_TODO.md` — open founder decisions.

---

## 🌎 What is HookUs?

Most dating platforms force very different intentions into the same experience.

Someone looking for a relationship may be shown someone looking for something casual.

Someone looking for a spontaneous night out may match with someone who wants to text for three weeks.

Couples looking to meet other adults have to awkwardly explain themselves in profiles.

Travellers may want to meet people while visiting a city but have no easy way of signalling that.

HookUs makes **intent, vibe and availability** first-class parts of discovery.

Users decide what they are looking for and can discover adults looking for compatible experiences.

HookUs starts with casual dating and hookups but is designed to grow into a broader adult social discovery network.

---

# ✨ Product Philosophy

HookUs is built around five principles.

### Be real

Say what you're actually looking for.

### Be yourself

Your lifestyle, interests and preferences should help you find compatible people.

### Be respectful

Casual does not mean disrespectful.

### Be safe

Verification, privacy, consent, blocking and reporting are core product infrastructure.

### Have fun

HookUs should feel exciting, spontaneous and social rather than like filling out a relationship application.

---

# 🔥 What Are You Here For?

Users can communicate their current intent directly on their profile.

Examples include:

- 👀 Just looking
- 🔥 Hookups
- 😏 Something casual
- 🥂 Dating & vibes
- 🌿 420 friendly
- 🎉 Party / nightlife
- ✈️ Travel connections
- ❤️ Open to a relationship
- 👫 Couples
- 👥 Group connections
- 🗺️ Adventures
- 🤷 See where it goes

Intent can change.

Someone may normally be open to dating but switch to travel connections while visiting another city.

HookUs should adapt to what someone wants **right now**.

---

# 💘 Hooks

HookUs does not revolve entirely around traditional Likes.

The signature interaction is a **Hook**.

A Like means:

> I'm interested.

A Hook means:

> I definitely want to connect.

Users receive a limited number of free Hooks, with additional Hooks available through premium plans or Hook packs.

When two users connect:

> 🔥 **You're Hooked!**

This gives HookUs its own social vocabulary:

- Hook
- Hook Back
- Hooks
- Hooked
- New Hook
- Unhook
- Hook Tonight

---

# 🌙 Hook Tonight

Hook Tonight is HookUs' temporary availability mode.

Users can indicate that they are open to doing something tonight.

Examples:

- 🥂 Drinks
- 🍽️ Dinner
- 🎉 Party
- 🎬 Movie
- 🌿 Chill
- 🎵 Event
- 👀 Something spontaneous

The user becomes discoverable inside the local Hook Tonight feed.

Availability automatically expires after the selected period.

Example:

> 🔥 84 people are up for something tonight near you.

Hook Tonight creates urgency without turning the entire application into a "meet now" service.

---

# 🌈 Vibes

Profiles should communicate personality quickly.

Users can select lifestyle signals such as:

- 🌿 420 Friendly
- 🥂 Drinks
- 🎉 Nightlife
- 🎧 Raves
- 🎵 Music
- ✈️ Travel
- 🏖️ Beach
- 🎮 Gaming
- 🏋️ Fitness
- 🐶 Pets
- 🎨 Creative
- 🌙 Night Owl
- 🧘 Chill
- 🚭 Smoke Free

Vibes become both profile information and discovery signals.

---

# 🔎 Discovery

HookUs discovery should go beyond an endless swipe queue.

Possible discovery spaces include:

### 📍 Nearby

People around your current area.

### 🟢 Online Now

People currently active.

### 🔥 Hook Tonight

People available tonight.

### 🌿 420 Friendly

People who have selected the 420-friendly lifestyle preference.

### 🎉 Nightlife

People interested in parties, clubs, concerts and nightlife.

### ✈️ Travellers

Visitors and people travelling soon.

### 🆕 New Here

Recently joined users.

### ✓ Verified

Verified profiles.

### 🌙 Night Owls

People active and open to late-night connections.

---

# 🗺️ Adventures

A future HookUs feature will allow users to post something they want to do and find adults interested in joining them.

Instead of only posting a profile, someone could post an **Adventure**.

Examples:

> 🎉 Going clubbing Friday — looking for company.

> 🎵 Festival this weekend — who else is going?

> 🏖️ Beach day Saturday.

> ✈️ Ibiza next month — looking to meet people there.

> 🌿 Chill night — looking for people with the same vibe.

> 🍷 Wine tasting this weekend.

Adventures can include:

- title
- description
- location
- date/time
- number of people wanted
- who can respond
- vibe
- visibility
- verification requirements

Users can request to join and the creator decides who gets invited.

---

# 👥 Couples & Group Connections

HookUs should eventually support more than one-person-to-one-person discovery.

Users may create:

- individual profiles
- linked couple profiles
- temporary groups

Couples can link their individual accounts while maintaining their own identities and privacy.

Discovery can then support combinations such as:

- person → person
- couple → person
- person → couple
- couple → couple
- group → people

Users should explicitly control which types of profiles can discover or contact them.

---

# 🧭 Experiences

A future **Experiences** system can allow adults to communicate the kinds of consensual social or intimate experiences they are interested in without having to awkwardly put everything into their bio.

Experience preferences can be:

- Public
- Matches only
- Private
- Ask me
- Hidden

Users control exactly what appears on their profile.

Compatibility can then help surface people whose interests overlap.

This should always operate through explicit opt-in preferences rather than assumptions based on user behaviour.

---

# 🚪 Rooms

Rooms turn HookUs from only a dating application into a live social environment.

A Room is a temporary or persistent space built around a topic, city, event or vibe.

Examples:

### 🌃 Cape Town After Dark

### 🎉 Lagos Nightlife

### 🌿 420 & Chill

### ✈️ Travellers in Barcelona

### 🎵 Festival Weekend

### 👫 Couples Lounge

### 🏳️‍🌈 LGBTQ+ Lounge

### 👋 New in London

Rooms may eventually support:

- text chat
- reactions
- polls
- photos
- voice rooms
- moderated discussions
- events
- private rooms
- invite-only rooms
- verified-only rooms

Users can meet through a Room and privately Hook each other afterward.

---

# ✈️ Travel Mode

Users can discover people before arriving somewhere.

Example:

> **Barcelona**
>
> Visiting Aug 21–27

Their profile can display:

> ✈️ Visiting Barcelona

Users can optionally browse:

> Visitors arriving soon

Travel Mode can eventually connect with Adventures, Rooms and Events.

---

# 🛍️ HookUs Marketplace

HookUs includes a community P2P marketplace.

The marketplace allows verified adults to discover legitimate products, tickets and services offered by other community members.

Example categories:

- 👕 Fashion
- 👟 Lifestyle
- 🎟️ Tickets
- 🎵 Events
- ✈️ Travel
- 📸 Creative services
- 💇 Beauty
- 📱 Electronics
- 🏠 Local services

Marketplace listings may include:

- photos
- title
- description
- price
- location
- seller profile
- verification status
- seller reputation
- availability
- delivery / collection options

Users can contact sellers through HookUs.

The marketplace should have separate moderation, prohibited-item rules and transaction-safety systems.

HookUs should not permit marketplace listings for illegal drugs, sexual services, weapons, stolen goods or other prohibited products/services.

---

# 💬 Messaging

Messaging becomes available after compatible connection rules are satisfied.

Potential features:

- text
- photos
- videos
- voice notes
- GIFs
- reactions
- disappearing media
- reply-to-message
- block
- report
- unhook

Users should have granular controls over who can send media and what kinds of messages they accept.

---

# ✓ Verification

HookUs should make authenticity visible without turning profiles into security dashboards.

Verification levels may include:

### Email ✓

### Phone ✓

### Selfie ✓

### ID ✓

The primary profile presentation can simply show:

> ✓ Verified

Users who want more information can inspect what verification was completed.

Discovery can optionally support:

> Verified profiles only.

---

# 🛡️ Trust, Safety & Consent

HookUs is casual, but safety is not casual.

Core safety infrastructure includes:

- Adults only (18+)
- Age controls
- Selfie verification
- Optional identity verification
- Block
- Unhook
- Report
- Photo moderation
- Spam detection
- Scam detection
- Harassment detection
- Suspicious account monitoring
- Rate limiting
- Privacy controls
- Approximate location
- Screenshot/privacy protections where technically possible
- Moderator/admin review tools

HookUs should never treat a previous match, Hook or conversation as ongoing consent.

Users can leave, block or Unhook at any time.

---

# 🔐 Privacy

HookUs should expose as little sensitive information as necessary.

Users control visibility of:

- distance
- exact age
- online status
- last active
- intentions
- interests
- travel plans
- profile visibility
- experience preferences

Exact real-time location should never be exposed to other users.

Distances should be approximate.

---

# 💎 HookUs+

HookUs can eventually monetize through premium discovery rather than making basic connection impossible without paying.

Potential HookUs+ features:

- Unlimited Likes
- More Hooks
- See who liked you
- Advanced filters
- Travel Mode
- Incognito Mode
- Undo
- Verified-only discovery
- Priority visibility
- Additional privacy controls

---

# 🔥 Hook Packs

Users receive some Hooks for free.

Additional Hooks can be purchased separately.

Possible packs:

- 5 Hooks
- 15 Hooks
- 50 Hooks

Pricing should be localized by country.

---

# ⚡ Boost

Users can temporarily increase their visibility.

Examples:

### Profile Boost

Higher placement in local discovery.

### Hook Tonight Boost

Higher placement inside tonight's feed.

### Adventure Boost

Increase visibility of an Adventure.

Marketplace sellers may eventually have separate promoted-listing functionality.

---

# 🌍 Global by Design

HookUs is not tied to one country or culture.

The platform should support:

- multiple countries
- multiple currencies
- multiple languages
- localized pricing
- regional moderation
- local safety information
- city-based discovery
- regional age/legal requirements

The product can launch city-by-city while the underlying architecture remains global.

---

# 📱 Platforms

HookUs should ultimately support:

- Responsive Web
- Progressive Web App
- iOS
- Android

The web experience should be treated as a first-class product rather than simply a stretched mobile interface.

---

# 🖥️ Desktop Experience

Desktop HookUs uses a multi-column social discovery layout.

Primary navigation:

Discover  
Hook Tonight  
Likes  
Hooks  
Chats  
Marketplace  
Travel  
Rooms  
Adventures  
Notifications  
Profile

The wider viewport can simultaneously surface:

- discovery
- Hook Tonight activity
- marketplace listings
- conversations
- notifications

Mobile simplifies these experiences into focused screens.

---

# 🎨 Design Direction

HookUs should feel:

**Dark. Sexy. Social. Modern. Global. Playful.**

Not pornographic.

Not corporate.

Not marriage-oriented.

Not childish.

The visual system should combine:

- deep black backgrounds
- charcoal surfaces
- neon pink
- magenta
- purple
- occasional contextual accent colours
- large photography
- strong typography
- soft gradients
- subtle glow
- rounded cards
- fast micro-interactions

HookUs should feel somewhere between a dating app, nightlife platform and modern social network.

---

# 🧱 Product Architecture

HookUs should be built around reusable domains rather than individual screens.

Possible domains:

    Identity
    Profiles
    Discovery
    Hooks
    Matches
    Messaging
    Availability
    Vibes
    Verification
    Safety
    Travel
    Adventures
    Groups
    Rooms
    Marketplace
    Payments
    Subscriptions
    Notifications
    Moderation
    Analytics

This allows new experiences to be added without turning the application into one giant dating controller.

---

# 🚀 MVP

Do not build the entire vision before launch.

Version 1 should prove the core HookUs loop:

    Sign up
       ↓
    Create profile
       ↓
    Choose intent + vibes
       ↓
    Add photos
       ↓
    Discover
       ↓
    Like / Hook
       ↓
    Hook back
       ↓
    Chat
       ↓
    Return

Initial MVP:

- Authentication
- Profiles
- Photos
- Intent
- Vibes
- Location
- Discovery
- Likes
- Hooks
- Matching
- Chat
- Selfie verification
- Block/report
- Basic notifications
- Admin moderation

---

# 🗺️ Roadmap

## Phase 1 — Hook

Profiles, discovery, Likes, Hooks, matches and messaging.

## Phase 2 — Tonight

Hook Tonight, availability, improved discovery and notifications.

## Phase 3 — Trust

Verification, moderation, safety infrastructure and advanced privacy.

## Phase 4 — Explore

Travel Mode, city discovery and local experiences.

## Phase 5 — Adventures

User-created plans, activities and experience discovery.

## Phase 6 — Couples & Groups

Linked profiles, group discovery and expanded connection types.

## Phase 7 — Rooms

Live communities around cities, interests, nightlife and experiences.

## Phase 8 — Marketplace

Verified P2P listings, seller reputation, payments and marketplace moderation.

## Phase 9 — Monetization

HookUs+, Hook Packs, Boosts and premium discovery.

---

# 📊 Success Metrics

HookUs should measure more than registrations.

Core funnel:

    Signup
      ↓
    Profile completed
      ↓
    Discovery started
      ↓
    First Like / Hook
      ↓
    Connection
      ↓
    First message
      ↓
    Reply
      ↓
    Conversation
      ↓
    Return visit

Important marketplace metrics:

    Listings created
    Listing views
    Seller conversations
    Successful transactions
    Reports/disputes

Community metrics:

    Adventures created
    Adventure responses
    Rooms joined
    Hooks originating from Rooms
    Travel connections

---

# 🔥 The Vision

HookUs begins with a simple idea:

> **Meet. Vibe. See where it goes.**

But the long-term opportunity is larger than another swipe application.

HookUs can become a global adults-only social discovery network where people can find others who share their intentions, lifestyles, interests and adventures.

Hook.

Chat.

Meet.

Travel.

Explore.

Join a Room.

Plan something.

Buy and sell within the community.

And see where it goes.

---

**HookUs**

🔥 Hookups  
😏 Casual  
🥂 Dating & Vibes  
🌿 420 Friendly  
🎉 Nightlife  
✈️ Travel  
👥 Groups  
🗺️ Adventures  
🚪 Rooms  
🛍️ Marketplace

### Meet. Vibe. See where it goes.