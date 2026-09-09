# Date9ja Privacy-Safe Preservation — Completion Report

**Slice 10, 2026-09-09.** Governing rule: Date9ja is authoritative; sensitivity
governs *how* a value is stored and exposed, not *whether* D8N represents it.
"Awaiting Uchechi" is not an acceptable state for a concept Date9ja already
defines.

## Group A — previously redacted arrays

| Field | D8N destination | Storage | Visibility | Sanitizer | Source vocabulary authority | Migration status |
|---|---|---|---|---|---|---|
| `preferred_countries` | `profile_preferences.preferred_country_codes` | jsonb list, ISO-3166 α-2 | owner-only | REDACT `{}` | closed ISO allowlist (`CountryMapping`) | **MIGRATED** (importer wired, slice 8; element values switch on when R2 clears) |
| `relocation_preferences` | `profiles.relocation_preferences` | string array | owner-only | REDACT `{}` | free text, normalized | **MIGRATED** (importer wired, slice 8) |
| `interests` | `interests` option group | multi-select | public | REDACT `{}` | `InterestMapping` (explicit, quarantine unknown) | **DESTINATION READY + IMPORTER WIRED**; element import blocked by R2/R3 |
| `relationship_values` | new `relationship_values` option group | multi-select | owner-only | REDACT `{}` | `RelationshipValueMapping` | **DESTINATION READY + IMPORTER WIRED**; element import blocked by R2/R3 |
| `dealbreakers` | new `dealbreakers` option group (lossless) | multi-select | owner-only | REDACT `{}` | `DealbreakerMapping` | **DESTINATION READY + IMPORTER WIRED**; element import blocked by R2/R3 |

## Group B — sensitive identity / culture / health fields

| Field | D8N destination | Storage | Visibility | Sanitizer | Source vocabulary authority | Migration status |
|---|---|---|---|---|---|---|
| `is_nigerian` | `profiles.is_nigerian` | boolean | owner-only | DESTROY → NULL | boolean, no vocabulary | **DESTINATION READY + IMPORTER WIRED** (gap-fill); needs pristine run (census 320) |
| `state_of_origin` | `profiles.state_of_origin` | string(80) | owner-only | DESTROY → NULL | closed 36-states-+-FCT allowlist (`NigerianStateMapping`) | **DESTINATION READY + IMPORTER WIRED**; census 321 on pristine |
| `nationality` | `profiles.nationality` | string(2) | owner-only | DESTROY → NULL | closed ISO α-2 (`CountryMapping`) | **DESTINATION READY + IMPORTER WIRED**; census 322 on pristine |
| `tribe` | `tribe` option group | single-select | owner-only | DESTROY → NULL | `SensitiveVocabularies::TRIBE` (D8N codes + synonyms; Date9ja source enum extends) | **DESTINATION READY + IMPORTER WIRED**; census 323 on pristine + R1 review |
| `ethnicity` | new `ethnicity` option group | single-select | owner-only | DESTROY → NULL | `SensitiveVocabularies::ETHNICITY` | **DESTINATION READY + IMPORTER WIRED**; census 324 + R1 review |
| `religion` | `religion` option group | single-select | owner-only | DESTROY → NULL | `SensitiveVocabularies::RELIGION` | **DESTINATION READY + IMPORTER WIRED**; census 325 + R1 review |
| `denomination` | new `denomination` option group (flat) | single-select | owner-only | DESTROY → NULL | `SensitiveVocabularies::DENOMINATION` | **DESTINATION READY + IMPORTER WIRED**; census 326 + R1 review |
| `genotype` | `genotype` option group | single-select | owner-only, never public, not in matching, never logged with identity | DESTROY → NULL | `SensitiveVocabularies::GENOTYPE` (haemoglobin genotypes) | **DESTINATION READY + IMPORTER WIRED**; census 327 + **security/DPIA sign-off on genotype at rest** |
| `intertribal_marriage_openness` | new option group | single-select | owner-only | DESTROY → NULL | `open/not_open/depends` tri-state | **DESTINATION READY + IMPORTER WIRED**; census 328 |
| `polygamy_openness` | new option group | single-select | owner-only | DESTROY → NULL | same tri-state | **DESTINATION READY + IMPORTER WIRED**; census 328 |
| `interest_in_nigerian_culture` | `profiles.interest_in_nigerian_culture` | text(1000) | owner-only | REDACT `[redacted]` | free text | **DESTINATION READY + IMPORTER WIRED**; census 329 (shape) + free-text privacy review |
| `preferred_religion` / `preferred_tribes` / `preferred_ethnicity` / `preferred_genotype` | `profile_preferences.preferred_attributes` (keyed) | jsonb `{key: [codes]}` | owner-only | DESTROY → `{}` | reuses the profile-side vocabulary per key | **DESTINATION READY + IMPORTER WIRED**; census 330 + R1 review |

## Architecture

- **Firewall preserved.** The ordinary import path (`UserSource` / `UserRecord` /
  `FieldMapping`) still reads none of these columns — the firewall test is
  unchanged. Sensitive columns are read only by the dedicated
  `Snapshot::SensitiveUserSource` → `SensitiveUserRecord` →
  `Import::SensitiveProfileImport`.
- **Ownership.** Identity spine → `IdentityImport`. Ordinary profile values →
  the profile/preference/readiness passes. Sensitive values → `SensitiveProfileImport`.
- **Non-destructive.** Gap-fill only: a member/operator/earlier value is never
  overwritten; a group with any kept selection is left alone. Reruns write
  nothing new (idempotent by construction, no marker needed).
- **Fail closed.** Every vocabulary is an explicit allowlist; an unrecognised
  value is quarantined and noted (`*_unmapped`), never approximated.
- **No exposure widening.** Every destination is owner-only. `genotype` is never
  placed in a public field and never logged alongside member identity.
- **Privacy-safe classification.** `source_census.sql` measures 320-330 emit only
  aggregate counts — a per-column allowlist-hit vs OTHER split — with no
  member-entered string ever emitted. This is the review input that decides
  whether each column can be reclassified REDACT/DESTROY → PRESERVE.

## Discovery / publication invariant

Unchanged. None of these fields is a completion, publication, or discovery gate
(they are all in `OPTIONAL_*` / not in `REQUIRED_*` for Date9ja). **534 source
discoverable → 534 D8N published/visible** is unaffected.

## Blocker

**BLOCKED — PRIVACY-SAFE SOURCE CLASSIFICATION REMAINS.**

Not blocked by absence of D8N support — every concept now has a live destination
and a wired importer. The exact data that cannot yet be safely classified:

1. The **element values** of every Group A/B column: the sanitizer redacts or
   destroys them, so the rehearsal cannot see them. The unblock is running
   `source_census.sql` measures 280-282 and 320-330 against a **pristine**
   snapshot and reviewing the allowlist-hit vs OTHER split (`SANITIZATION-CONTRACT`
   R1/R2/R3, E-4/E-5). This is a privacy-safe extraction step.
2. **Genotype at rest**: additionally needs a security/DPIA sign-off on whether
   an owner-only column is sufficient or encryption-at-rest is required. This is
   a security review, not a product-scope decision.

Once (1) lands, `SensitiveProfileImport` migrates every reviewed value with no
further code change.
