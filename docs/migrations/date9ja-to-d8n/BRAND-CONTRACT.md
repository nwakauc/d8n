# Date9ja Brand Contract

Add `date9ja` as a first-class D8N brand contract and idempotent installer, mirroring `Brands::DatezaInstaller` and `Brands::Dateza` structurally without reusing DateZA behavior. Register it in the brand provisioner/registry, configure trusted Date9ja hosts, install a Date9ja profile catalog, and reject host conflicts.

Date9ja remains Nigeria-first with its own tone, onboarding, relationship intent, and compatibility rules. It must not be aliased to DateZA or HookUs.

Configuration/policy should own the brand name/slug/hosts, Nigerian location catalog, email/password and approved phone auth, minimum age, publication/photo moderation gate, lifecycle, profile capabilities, partner preferences, discovery limits, notification plans, and feature flags. Date9ja capabilities include display name, birthdate, gender, bio, occupation, height/body type, languages, faith/religion, ethnicity/tribe, family/children, genotype if approved, relationship intent, relocation, interests, and compatibility answers.

Code-owned policy should be limited to conditional onboarding (Nigerian vs non-Nigerian and relocation), privacy redaction, compatibility, eligibility, and moderation transitions. Do not store arbitrary executable rules or sensitive fields in unrestricted metadata.

Required decisions: retention/option mapping for tribe, ethnicity, genotype, denomination, and preferred tribes; verification prerequisites; legacy photo publication; premium/entitlement behavior; and visibility of historical views, exposure, trust, and verification history.

This follows the architecture already used by HookUs and DateZA: one installer, one catalog/contract, shared D8N services, no scattered brand branches.
