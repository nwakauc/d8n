# Date9ja Brand Contract

Add `date9ja` as a first-class D8N brand contract and idempotent installer, mirroring `Brands::DatezaInstaller` and `Brands::Dateza` structurally without reusing DateZA behavior. Register it in the brand provisioner/registry, configure trusted Date9ja hosts, install a Date9ja profile catalog, and reject host conflicts.

Date9ja remains Nigeria-first with its own tone, onboarding, relationship intent, and compatibility rules. It must not be aliased to DateZA or HookUs.

Configuration/policy should own the brand name/slug/hosts, Nigerian location catalog, email/password and approved phone auth, minimum age, publication/photo moderation gate, lifecycle, profile capabilities, partner preferences, discovery limits, notification plans, and feature flags. Date9ja capabilities include display name, birthdate, gender, bio, occupation, height/body type, languages, faith/religion, ethnicity/tribe, family/children, genotype if approved, relationship intent, relocation, interests, and compatibility answers.

Code-owned policy should be limited to conditional onboarding (Nigerian vs non-Nigerian and relocation), privacy redaction, compatibility, eligibility, and moderation transitions. Do not store arbitrary executable rules or sensitive fields in unrestricted metadata.

Required decisions: retention/option mapping for tribe, ethnicity, genotype, denomination, and preferred tribes; verification prerequisites; legacy photo publication; premium/entitlement behavior; and visibility of historical views, exposure, trust, and verification history.

This follows the architecture already used by HookUs and DateZA: one installer, one catalog/contract, shared D8N services, no scattered brand branches.

## Implementation status (Phase 1, Wave A slice 1 — SELF_VERIFIED)

Foundation implemented:

- `Brands::Date9jaInstaller` — idempotent, host-conflict safe, wired into `Brands::Provisioner` (`bin/rails 'brands:provision[date9ja]'`) and `db/seeds.rb`.
- `D8n::Platform::Brands::Date9ja` contract, registered in `D8n::Platform::BrandRegistry`. Slug `date9ja`, display `Date9ja`, auth methods `email_password` + `phone_password`, phone calling code `234`, place countries `["NG"]`.
- `Profiles::Date9jaProfileCatalog` — non-sensitive skeleton (display name, birthdate, gender, country/city, bio, occupation/job/school, height/body type, languages, smoking/drinking/fitness; option groups relationship_intent, has_children, wants_children, meeting_pace, education_level, social_style, communication_style, planning_style, diet, sleep_schedule, travel_frequency; curated interests; prompts). Family fields stay `owner_only`.
- `Geography::NigeriaCatalog` + `bin/rails geography:seed_nigeria` — shared platform geography.

Age requirement: no brand-level primitive exists; the platform-wide `Profile::MINIMUM_AGE` (18) applies unchanged.

Deliberately deferred / left gated in the contract:

- Photo publication: `initial_visibility: :moderate_first` (conservative default) pending the "Approved photo publication" decision.
- Interaction `verification_requirement: nil` pending the verification-gates decision.
- No discovery surface, matching strategy, messaging, or opener capability — these need the discovery/profile-write remediation slices and Date9ja product semantics.
- Sensitive fields (faith/religion, ethnicity, tribe, denomination, preferred tribes, genotype) are not modelled anywhere.

## AI ownership

Date9ja enables a shared `D8N AI` capability and supplies the `Aunty Phobie`
assistant definition: identity, personality, tone, cultural context,
instructions, allowed tools, limits, presentation, and escalation policy. The
runtime owns provider routing, context execution, safety, privacy/egress,
credential isolation, versioning, metering, and failure handling. No
Date9ja-owned AI infrastructure is permitted. The AI contract, provider data
egress, consent, retention, redaction, logging, tool authorization, and cost
controls require an architecture/privacy decision before implementation.
