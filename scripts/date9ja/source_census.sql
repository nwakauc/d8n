-- =============================================================================
-- Date9ja migration-rehearsal snapshot — reconciliation SOURCE census
-- =============================================================================
-- Authority: docs/migrations/date9ja-to-d8n/RECONCILIATION.md
-- Companions: scripts/date9ja/sanitize_snapshot.sql
--             scripts/date9ja/verify_sanitized_snapshot.sql
--
-- WHAT THIS DOES
--   Read-only. Emits the SOURCE-side counts for every measure in
--   RECONCILIATION.md, plus the sub-state breakdowns an importer slice needs
--   to define "equal after documented exclusions" / "equal under approved
--   definition". Deterministic and re-runnable: same snapshot -> same numbers.
--   The output table is pasted into RECONCILIATION.md (Source column) and used
--   as the acceptance baseline for every Wave A/B importer dry-run.
--
--   Sections `source_types`, `profile_values`, `preference_validity`,
--   `gender_compat`, `profile_shape`, `country`, `publication` and `arrays`
--   (ord 200-299) are the profile/preference VALUE census added for Pass 1 of
--   the profile & preference migration. Their output is the evidence base for
--   docs/migrations/date9ja-to-d8n/PROFILE-VALUE-MAPPING.md. They have their own
--   emitter safety contract -- see the block header at ord 200. Two of those
--   sections are PRISTINE-ONLY (see "SNAPSHOT FIDELITY" there); everything else
--   is sanitizer-faithful and correct to run against date9ja_snapshot_sanitized.
--
-- WHAT THIS IS NOT
--   Not an importer. Not a product decision. It writes nothing (runs inside a
--   READ ONLY transaction that is always rolled back), copies no row contents,
--   and reads only aggregate counts — no PII leaves this script.
--
-- SAFE LOCAL EXECUTION (operator only):
--   psql -v ON_ERROR_STOP=1 -d date9ja_snapshot_sanitized \
--        -f scripts/date9ja/source_census.sql
--
--   Row counts are identical in the pristine restore and the sanitized copy
--   (the sanitizer preserves every row — proven by verify_sanitized_snapshot.sql
--   and by the post-restore package test), so running against
--   `date9ja_snapshot_sanitized` gives the true source baseline with no need to
--   touch `date9ja_snapshot_tmp`.
-- =============================================================================

\set ON_ERROR_STOP on

-- Read-only transaction: any accidental write (now or after a careless edit)
-- aborts instead of mutating the snapshot. Always rolled back at the end.
BEGIN;
SET TRANSACTION READ ONLY;

-- -----------------------------------------------------------------------------
-- Schema-drift guard — canonical Date9ja source-schema signature (v3), shared
-- verbatim with sanitize_snapshot.sql and verify_sanitized_snapshot.sql. Any
-- structural drift (type / nullability / ordinal / default / table set) aborts
-- the run before a single count is read.
-- -----------------------------------------------------------------------------
\ir schema_signature.sql

-- -----------------------------------------------------------------------------
-- Census — one row per (section, measure). `note` records the mapping rule the
-- importer must honour so "equal" is unambiguous at reconciliation time.
-- Ordering column `ord` keeps the output stable for diffing between runs.
--
-- GROUPED OUTPUT HARDENING
--   Every `value:count` breakdown emits only ALLOWLISTED buckets; anything else
--   (historical, malformed, adversarial) is folded into `OTHER`. A raw
--   unexpected source value is NEVER echoed. The DB does not constrain these
--   enums (no CHECK constraints), so the allowlists are conservative supersets
--   derived from schema defaults + Date9ja capability docs; refine against
--   Date9ja model source when it is available for review. Widening an allowlist
--   only ever moves a count out of OTHER — it never leaks a value, because
--   non-allowlisted values are already bucketed.
--     verification_tier              : 0 1 2
--     photo/video moderation_status  : 0 1 2
--     likes.kind                     : 0 1
--     messages.kind                  : 0 1 2 3
--     verification_checks.status     : not_started submitted pending approved
--                                       rejected resubmission_required revoked
--     career_applications.status     : submitted reviewing shortlisted rejected hired
--     active_storage_attachments.name : image video (attachment role)
--     active_storage_attachments.record_type : Photo ProfileVideo Message
--                                       VerificationCheck SelfieVerification CommunityStory
--     blob content-type family        : image video audio application text
-- -----------------------------------------------------------------------------
\pset pager off
\pset format aligned

WITH census(ord, section, measure, source_count, note) AS (
  VALUES
  -- ---- identity / accounts ------------------------------------------------
  ( 10, 'accounts', 'users total',
        (SELECT count(*) FROM users), 'every source users row'),
  ( 11, 'accounts', 'users kept (deleted_at IS NULL)',
        (SELECT count(*) FROM users WHERE deleted_at IS NULL), 'maps 1:1 to a D8N User'),
  ( 12, 'accounts', 'users soft-deleted (deleted_at NOT NULL)',
        (SELECT count(*) FROM users WHERE deleted_at IS NOT NULL),
        'documented exclusion or tombstone per AUTHENTICATION.md'),
  ( 13, 'accounts', 'users seed_account = true',
        (SELECT count(*) FROM users WHERE seed_account), 'operator/test accounts — exclude from parity totals'),
  ( 14, 'accounts', 'users admin = true',
        (SELECT count(*) FROM users WHERE admin), 'HQ operators — not consumer parity'),
  ( 15, 'accounts', 'users confirmed (confirmed_at NOT NULL)',
        (SELECT count(*) FROM users WHERE confirmed_at IS NOT NULL),
        'drives IdentityIdentifier(email).verified_at'),
  ( 16, 'accounts', 'users unconfirmed (confirmed_at IS NULL)',
        (SELECT count(*) FROM users WHERE confirmed_at IS NULL), 'email identifier stays unverified'),
  ( 17, 'accounts', 'users phone present',
        (SELECT count(*) FROM users WHERE phone IS NOT NULL AND phone <> ''),
        'candidate IdentityIdentifier(phone)'),
  ( 18, 'accounts', 'users phone_verified_at NOT NULL',
        (SELECT count(*) FROM users WHERE phone_verified_at IS NOT NULL),
        'drives IdentityIdentifier(phone).verified_at'),
  ( 19, 'accounts', 'distinct lower(email)',
        (SELECT count(DISTINCT lower(email)) FROM users),
        'must equal users total — no email collisions to quarantine'),
  ( 20, 'accounts', 'distinct public_id',
        (SELECT count(DISTINCT public_id) FROM users),
        'must equal users total — legacy-ID map key'),
  ( 21, 'accounts', 'migration eligible (not deleted, not banned)',
        (SELECT count(*) FROM users WHERE deleted_at IS NULL AND banned_at IS NULL),
        'current identity importer eligibility rule'),
  ( 22, 'accounts', 'excluded from identity import (deleted OR banned)',
        (SELECT count(*) FROM users WHERE deleted_at IS NOT NULL OR banned_at IS NOT NULL),
        'overlap-safe excluded cohort'),
  ( 23, 'accounts', 'exclusion reason counts', NULL,
        (SELECT 'deleted:' || count(*) FILTER (WHERE deleted_at IS NOT NULL)
             || ' banned:' || count(*) FILTER (WHERE banned_at IS NOT NULL)
             || ' both:' || count(*) FILTER (WHERE deleted_at IS NOT NULL AND banned_at IS NOT NULL)
           FROM users)),

  -- ---- profile / lifecycle state ---------------------------------------
  ( 30, 'profiles', 'onboarding_completed_at NOT NULL',
        (SELECT count(*) FROM users WHERE onboarding_completed_at IS NOT NULL),
        'candidate "published profile" definition — confirm with product'),
  ( 31, 'profiles', 'profile_hidden = true',
        (SELECT count(*) FROM users WHERE profile_hidden), 'maps to Profile.visibility = hidden'),
  ( 32, 'profiles', 'suspended_at NOT NULL',
        (SELECT count(*) FROM users WHERE suspended_at IS NOT NULL), 'BrandMembership/Profile suspended'),
  ( 33, 'profiles', 'banned_at NOT NULL',
        (SELECT count(*) FROM users WHERE banned_at IS NOT NULL), 'enforcement tombstone'),
  ( 34, 'profiles', 'flagged_for_moderation_at NOT NULL',
        (SELECT count(*) FROM users WHERE flagged_for_moderation_at IS NOT NULL), 'moderation queue state'),
  ( 35, 'profiles', 'profile_completeness_score > 0',
        (SELECT count(*) FROM users WHERE profile_completeness_score > 0), 'recomputed target-side; sanity only'),
  ( 36, 'lifecycle', 'discovery_restricted_at NOT NULL',
        (SELECT count(*) FROM users WHERE discovery_restricted_at IS NOT NULL),
        'moderator-owned hard discovery restriction; independent of profile_hidden'),
  ( 37, 'lifecycle', 'discovery restriction reason buckets', NULL,
        (SELECT string_agg(reason || ':' || n, ' ' ORDER BY reason) FROM (
           SELECT CASE
                    WHEN discovery_restriction_reason IS NULL THEN 'NULL'
                    WHEN discovery_restriction_reason IN (
                      'commercial_solicitation','off_platform_promotion','promotional_profile',
                      'suspected_scam','spam','impersonation','inappropriate_content',
                      'safety_concern','other') THEN discovery_restriction_reason
                    ELSE 'OTHER'
                  END reason, count(*) n
             FROM users GROUP BY 1) d)),
  ( 38, 'lifecycle', 'visibility/safety state cross-tab', NULL,
        (SELECT string_agg(state || ':' || n, ' ' ORDER BY state) FROM (
           SELECT 'hidden_' || profile_hidden::int || '/restricted_' ||
                  (discovery_restricted_at IS NOT NULL)::int || '/suspended_' ||
                  (suspended_at IS NOT NULL)::int || '/banned_' ||
                  (banned_at IS NOT NULL)::int || '/deleted_' ||
                  (deleted_at IS NOT NULL)::int state, count(*) n
             FROM users GROUP BY 1) d)),
  ( 39, 'lifecycle', 'discovery restriction referential anomalies',
        (SELECT count(*) FROM users
          WHERE (discovery_restricted_at IS NULL AND
                 (discovery_restriction_reason IS NOT NULL OR discovery_restriction_note IS NOT NULL OR
                  discovery_restricted_by_id IS NOT NULL))
             OR (discovery_restricted_by_id IS NOT NULL AND
                 NOT EXISTS (SELECT 1 FROM users moderator WHERE moderator.id = users.discovery_restricted_by_id))),
        'must be zero; no identifiers emitted'),

  -- ---- verification / trust (state + counts only) ----------------------
  ( 40, 'verification', 'users verification_tier > 0',
        (SELECT count(*) FROM users WHERE verification_tier > 0),
        '"verified users" — equal under the approved verification definition'),
  ( 41, 'verification', 'users by verification_tier',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b)
           FROM (SELECT CASE WHEN verification_tier IN (0, 1, 2)
                             THEN verification_tier::text ELSE 'OTHER' END b,
                        count(*) c FROM users GROUP BY 1) t)),
  ( 42, 'verification', 'verification_checks total',
        (SELECT count(*) FROM verification_checks), 'record count'),
  ( 43, 'verification', 'verification_checks by status',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b)
           FROM (SELECT CASE WHEN status IN ('not_started','submitted','pending',
                                             'approved','rejected','resubmission_required',
                                             'revoked')
                             THEN status ELSE 'OTHER' END b,
                        count(*) c FROM verification_checks GROUP BY 1) t)),
  ( 44, 'verification', 'verification_events total',
        (SELECT count(*) FROM verification_events), 'status-history rows'),
  ( 45, 'verification', 'selfie_verifications total',
        (SELECT count(*) FROM selfie_verifications), 'record count'),
  ( 46, 'verification', 'phone_verifications total',
        (SELECT count(*) FROM phone_verifications), 'phone verification records; OTP material is not exposed'),
  ( 47, 'verification', 'phone_verifications verified (verified_at NOT NULL)',
        (SELECT count(*) FROM phone_verifications WHERE verified_at IS NOT NULL),
        'verified phone state maps to the D8N phone identifier'),
  ( 48, 'trust', 'users trust_xp > 0',
        (SELECT count(*) FROM users WHERE trust_xp > 0), 'derived reputation input'),
  ( 49, 'trust', 'sum(users.trust_xp)',
        (SELECT COALESCE(sum(trust_xp), 0) FROM users), 'must equal target sum — points migrate verbatim (ADR 0025)'),
  ( 50, 'trust', 'trust_events total',
        (SELECT count(*) FROM trust_events), 'ledger rows'),
  ( 51, 'trust', 'sum(trust_events.points)',
        (SELECT COALESCE(sum(points), 0) FROM trust_events), 'ledger integrity check'),
  ( 52, 'trust', 'trust_adjustments total',
        (SELECT count(*) FROM trust_adjustments), 'manual ledger rows'),

  -- ---- entitlements ---------------------------------------------------
  ( 55, 'entitlements', 'users founding_member = true',
        (SELECT count(*) FROM users WHERE founding_member),
        'must equal target — no user loses it (ADR 0026)'),
  ( 56, 'entitlements', 'users subscription_status = premium (1)',
        (SELECT count(*) FROM users WHERE subscription_status = 1),
        'must equal target — no accidental grant/loss'),
  ( 57, 'entitlements', 'users premium_expires_at in future',
        (SELECT count(*) FROM users WHERE premium_expires_at IS NOT NULL AND premium_expires_at > now()),
        'active paid window at snapshot time'),
  ( 58, 'entitlements', 'users premium_expires_at NOT NULL',
        (SELECT count(*) FROM users WHERE premium_expires_at IS NOT NULL), 'ever-premium — carry timestamp verbatim'),

  -- ---- media -------------------------------------------------------
  ( 60, 'media', 'photos total',
        (SELECT count(*) FROM photos), 'one ProfilePhoto per row'),
  ( 61, 'media', 'photos by moderation_status',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b)
           FROM (SELECT CASE WHEN moderation_status IN (0, 1, 2)
                             THEN moderation_status::text ELSE 'OTHER' END b,
                        count(*) c FROM photos GROUP BY 1) t)),
  ( 62, 'media', 'photos is_primary = true',
        (SELECT count(*) FROM photos WHERE is_primary), '<= one per user; maps to primary slot'),
  ( 63, 'media', 'profile_videos total',
        (SELECT count(*) FROM profile_videos), 'one ProfileVideo per row (<= one per user)'),
  ( 64, 'media', 'profile_videos by moderation_status',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b)
           FROM (SELECT CASE WHEN moderation_status IN (0, 1, 2)
                             THEN moderation_status::text ELSE 'OTHER' END b,
                        count(*) c FROM profile_videos GROUP BY 1) t)),
  ( 65, 'media', 'active_storage_attachments total',
        (SELECT count(*) FROM active_storage_attachments), 'blob<->record links'),
  ( 66, 'media', 'active_storage_attachments by record_type',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b)
           FROM (SELECT CASE WHEN record_type IN ('Photo','ProfileVideo','Message',
                                                   'VerificationCheck','SelfieVerification',
                                                   'CommunityStory')
                             THEN record_type ELSE 'OTHER' END b,
                        count(*) c FROM active_storage_attachments GROUP BY 1) t)),
  ( 67, 'media', 'active_storage_blobs total',
        (SELECT count(*) FROM active_storage_blobs), 'source objects to preflight/migrate'),
  ( 68, 'media', 'active_storage_blobs by content_type family',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b)
           FROM (SELECT CASE WHEN split_part(COALESCE(content_type, ''), '/', 1)
                                  IN ('image','video','audio','application','text')
                             THEN split_part(content_type, '/', 1) ELSE 'OTHER' END b,
                        count(*) c FROM active_storage_blobs GROUP BY 1) t)),
  ( 69, 'media', 'active_storage_blobs distinct checksum',
        (SELECT count(DISTINCT checksum) FROM active_storage_blobs),
        'lower than total => exact-duplicate uploads (expected; not an error)'),
  ( 70, 'media', 'active_storage_variant_records total',
        (SELECT count(*) FROM active_storage_variant_records),
        'derived variants — regenerated target-side, not migrated (pass 1)'),

  -- ---- relationship graph -------------------------------------------
  ( 80, 'graph', 'likes total',
        (SELECT count(*) FROM likes), 'directional liker_id -> liked_id'),
  ( 81, 'graph', 'likes self-directed (liker = liked)',
        (SELECT count(*) FROM likes WHERE liker_id = liked_id), 'must be 0 — else data-quality exclusion'),
  ( 82, 'graph', 'likes by kind',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b)
           FROM (SELECT CASE WHEN kind IN (0, 1) THEN kind::text ELSE 'OTHER' END b,
                        count(*) c FROM likes GROUP BY 1) t)),
  ( 84, 'graph', 'profile_passes total',
        (SELECT count(*) FROM profile_passes), 'directional passer_id -> passed_id'),
  ( 85, 'graph', 'matches total',
        (SELECT count(*) FROM matches), 'one Match + one conversation container per row'),
  ( 86, 'graph', 'matches distinct canonical pairs',
        (SELECT count(DISTINCT least(user_a_id, user_b_id) || '-' || greatest(user_a_id, user_b_id))
           FROM matches),
        'must equal matches total — no duplicate pair rows'),
  ( 87, 'graph', 'matches self-paired (a = b)',
        (SELECT count(*) FROM matches WHERE user_a_id = user_b_id), 'must be 0'),
  ( 88, 'graph', 'messages total',
        (SELECT count(*) FROM messages), 'per retention policy'),
  ( 89, 'graph', 'messages kept (deleted_at IS NULL)',
        (SELECT count(*) FROM messages WHERE deleted_at IS NULL), 'live message bodies'),
  ( 90, 'graph', 'messages with reply_to_id',
        (SELECT count(*) FROM messages WHERE reply_to_id IS NOT NULL), 'same-conversation reply integrity'),
  ( 91, 'graph', 'messages by kind',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b)
           FROM (SELECT CASE WHEN kind IN (0, 1, 2, 3) THEN kind::text ELSE 'OTHER' END b,
                        count(*) c FROM messages GROUP BY 1) t)),
  ( 92, 'graph', 'messages read (read_at NOT NULL)',
        (SELECT count(*) FROM messages WHERE read_at IS NOT NULL), 'participant read-state mapping'),
  ( 93, 'graph', 'message_reactions total',
        (SELECT count(*) FROM message_reactions), 'one reaction row each'),
  ( 94, 'graph', 'profile_views total',
        (SELECT count(*) FROM profile_views), 'exposure accounting; retention policy applies'),
  ( 95, 'graph', 'profile_views self-views (viewer = viewed)',
        (SELECT count(*) FROM profile_views WHERE viewer_id = viewed_id), 'must be 0'),
  ( 96, 'graph', 'blocks total',
        (SELECT count(*) FROM blocks), 'directional; same-brand after mapping'),
  ( 97, 'graph', 'reports total',
        (SELECT count(*) FROM reports), 'retained reports'),
  ( 98, 'graph', 'reports resolved (resolved_at NOT NULL)',
        (SELECT count(*) FROM reports WHERE resolved_at IS NOT NULL), 'moderation outcome preserved'),
  ( 99, 'graph', 'daily_introductions total',
        (SELECT count(*) FROM daily_introductions), 'recommendation history — retention TBD'),
  (100, 'graph', 'explore_impressions total',
        (SELECT count(*) FROM explore_impressions), 'discovery telemetry — likely not migrated'),
  (101, 'graph', 'users with rewind_used_on',
        (SELECT count(*) FROM users WHERE rewind_used_on IS NOT NULL),
        'rewind usage marker; date is preserved only if the approved target supports the same daily semantics'),

  -- ---- notifications --------------------------------------------
  (110, 'notifications', 'notifications total',
        (SELECT count(*) FROM notifications), 'history — retention policy applies'),
  (111, 'notifications', 'notifications unread (read_at IS NULL)',
        (SELECT count(*) FROM notifications WHERE read_at IS NULL), 'unread badge continuity'),
  (112, 'notifications', 'notification_deliveries total',
        (SELECT count(*) FROM notification_deliveries), 'delivery-attempt rows'),
  (113, 'notifications', 'push_tokens total',
        (SELECT count(*) FROM push_tokens), 'device registrations'),
  (114, 'notifications', 'push_tokens active (disabled_at IS NULL)',
        (SELECT count(*) FROM push_tokens WHERE disabled_at IS NULL),
        'live device registrations -> DeviceRegistration (token itself dropped)'),
  (115, 'notifications', 'users with non-empty notification_preferences',
        (SELECT count(*) FROM users WHERE notification_preferences <> '{}'::jsonb), 'preference shape to map'),
  (116, 'notifications', 'users with non-empty email_notification_preferences',
        (SELECT count(*) FROM users WHERE email_notification_preferences <> '{}'::jsonb), 'preference shape to map'),

  -- ---- extended capabilities (structural relationship counts) --
  (130, 'community', 'community_questions',
        (SELECT count(*) FROM community_questions), 'shared Community domain (Wave D)'),
  (131, 'community', 'community_answers',
        (SELECT count(*) FROM community_answers), NULL),
  (132, 'community', 'community_remarks',
        (SELECT count(*) FROM community_remarks), NULL),
  (133, 'community', 'community_answer_votes',
        (SELECT count(*) FROM community_answer_votes), NULL),
  (134, 'community', 'community_events',
        (SELECT count(*) FROM community_events), NULL),
  (135, 'community', 'community_event_rsvps',
        (SELECT count(*) FROM community_event_rsvps), NULL),
  (136, 'community', 'community_stories',
        (SELECT count(*) FROM community_stories), NULL),
  (137, 'community', 'community_reports',
        (SELECT count(*) FROM community_reports), NULL),
  (140, 'dating_hub', 'dating_hub_batches',
        (SELECT count(*) FROM dating_hub_batches), 'Dating Hub primitives (Wave D)'),
  (141, 'dating_hub', 'tracked_contacts',
        (SELECT count(*) FROM tracked_contacts), NULL),
  (142, 'dating_hub', 'tracked_contact_notes',
        (SELECT count(*) FROM tracked_contact_notes), NULL),
  (143, 'dating_hub', 'personas',
        (SELECT count(*) FROM personas), NULL),
  (144, 'dating_hub', 'daily_life_entries',
        (SELECT count(*) FROM daily_life_entries), NULL),
  (150, 'aunty_phobie', 'aunty_phobie_conversations',
        (SELECT count(*) FROM aunty_phobie_conversations), 'Aunty Phobie assistant (Wave D)'),
  (151, 'aunty_phobie', 'aunty_phobie_messages',
        (SELECT count(*) FROM aunty_phobie_messages), NULL),
  (152, 'aunty_phobie', 'aunty_phobie_usage_events',
        (SELECT count(*) FROM aunty_phobie_usage_events), NULL),

  -- ---- attribution -------------------------------------------
  (160, 'attribution', 'users with signup_source',
        (SELECT count(*) FROM users WHERE signup_source IS NOT NULL AND signup_source <> ''),
        'attribution continuity — sanitized to buckets, shape only'),
  (161, 'attribution', 'users with attribution_source',
        (SELECT count(*) FROM users WHERE attribution_source IS NOT NULL AND attribution_source <> ''), NULL)
  ,

  -- ---- retained user-facing Careers / Feedback ----------------------
  (170, 'careers', 'career_jobs total',
        (SELECT count(*) FROM career_jobs), 'reachable public Careers records; preserve published/closed semantics'),
  (171, 'careers', 'career_jobs published',
        (SELECT count(*) FROM career_jobs WHERE status = 'published' AND published_at IS NOT NULL),
        'publicly reachable jobs at snapshot time'),
  (172, 'careers', 'career_applications total',
        (SELECT count(*) FROM career_applications), 'user-submitted applications; sensitive fields require approved mapping'),
  (173, 'careers', 'career_applications by status',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b)
           FROM (SELECT CASE WHEN status IN ('submitted','reviewing','shortlisted',
                                             'rejected','hired')
                             THEN status ELSE 'OTHER' END b,
                        count(*) c FROM career_applications GROUP BY 1) t)),
  (174, 'feedback', 'feedback_items total',
        (SELECT count(*) FROM feedback_items), 'user-submitted feedback records'),
  (175, 'feedback', 'feedback_items unreviewed',
        (SELECT count(*) FROM feedback_items WHERE reviewed_at IS NULL), 'review queue continuity'),

  -- ---- 2026-09-08 lifecycle/schema delta ------------------------------
  (176, 'retention', 'exit_attempts total',
        (SELECT count(*) FROM exit_attempts), 'HEAD capability present in authoritative production snapshot'),
  (177, 'retention', 'exit_attempt outcomes', NULL,
        (SELECT string_agg(bucket || ':' || n, ' ' ORDER BY bucket) FROM (
           SELECT CASE WHEN outcome IN ('pending','stayed','paused','deleted') THEN outcome ELSE 'OTHER' END bucket,
                  count(*) n FROM exit_attempts GROUP BY 1) d)),
  (178, 'retention', 'exit_attempt retention actions', NULL,
        (SELECT string_agg(bucket || ':' || n, ' ' ORDER BY bucket) FROM (
           SELECT CASE WHEN retention_action IN (
                    'none','preferences_updated','notifications_updated','feedback_submitted',
                    'problem_reported','safety_concern_reported','success_story_shared',
                    'app_launch_notice_requested') THEN retention_action ELSE 'OTHER' END bucket,
                  count(*) n FROM exit_attempts GROUP BY 1) d)),
  (179, 'retention', 'exit_attempt free-text presence (content never emitted)', NULL,
        (SELECT 'comment:' || count(*) FILTER (WHERE comment IS NOT NULL AND btrim(comment) <> '')
             || ' final_comment:' || count(*) FILTER (WHERE final_comment IS NOT NULL AND btrim(final_comment) <> '')
             || ' context_nonempty:' || count(*) FILTER (WHERE context <> '{}'::jsonb)
           FROM exit_attempts)),
  (180, 'schema_delta', 'HEAD-only identity/app-launch columns present in snapshot',
        (SELECT count(*) FROM information_schema.columns
          WHERE table_schema = current_schema() AND table_name = 'users'
            AND column_name IN ('app_launch_notice_at','app_launch_notice_source',
                                'identity_confirmation_pending','admin_identity_corrected_at',
                                'admin_identity_confirmed_at')),
        'must be 0 for this authoritative production snapshot; these five columns are HEAD-only'),

  -- =========================================================================
  -- PROFILE / PREFERENCE VALUE CENSUS  (Pass 1 evidence)
  -- Authority: docs/migrations/date9ja-to-d8n/PROFILE-VALUE-MAPPING.md
  --
  -- WHY THIS EXISTS
  --   D8N discovery matches RECIPROCALLY and EXACTLY on strings:
  --     Matching::EligibilityScope -> profiles.gender = ANY(preference.interested_in)
  --                                AND preference.interested_in @> [viewer.gender]
  --   `profiles.gender` is an unconstrained string(40) and Date9ja stores its
  --   equivalents as legacy codes. The mapping therefore CANNOT be guessed; it
  --   has to be measured. These measures produce that evidence and nothing else.
  --   They create no rows and decide no mapping.
  --
  -- BOUNDED-VOCABULARY EMITTER (safety contract for every `*_values` measure)
  --   A value:count pair is emitted ONLY when ALL of these hold:
  --     (a) the column has <= 24 distinct non-NULL values -- above that the
  --         column is treated as unbounded/free-text and ONLY the distinct
  --         count and NULL count are emitted, never a value;
  --     (b) the value is a plain integer (^-?[0-9]{1,9}$), OR
  --     (c) the value is <= 40 chars and is at most FOUR space-separated
  --         tokens each of which STARTS WITH A LETTER --
  --         ^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$ (case-insensitive) --
  --         emitted lower-cased with spaces normalised to underscores so the
  --         space-separated `value:count` output stays unambiguous (a legacy
  --         'Non Binary' emits as `non_binary`).
  --         The token rule is what separates an enum LABEL from free text: a
  --         sentence, a date, an address, a height or a phone number all have
  --         either too many tokens or a token that does not start with a
  --         letter, so they fold to OTHER. Proven by the whole-section privacy
  --         sweep in test/scripts/date9ja/profile_value_census_test.rb.
  --   Anything else -- punctuation, emails, URLs, phone numbers, free text,
  --   adversarial input -- folds to OTHER. NULLs are counted as 'NULL'.
  --   This is strictly tighter than echoing a column: it cannot emit an
  --   address, a handle, or a sentence, and it cannot emit anything at all
  --   from a high-cardinality column. Widening the cap only ever moves counts
  --   out of UNBOUNDED; it can never emit a value that fails (b)/(c).
  --
  -- FREE-TEXT COLUMNS ARE EXCLUDED FROM THE BOUNDED EMITTER
  --   The bounded emitter above is only sound for columns whose write path
  --   constrains the value to a vocabulary. `users.body_type` does not: it is
  --   a free-text input, so a short arbitrary phrase can satisfy the label
  --   grammar. Measure 221 therefore uses a CLOSED ALLOWLIST of the six
  --   documented historical suggestions and folds everything else to OTHER.
  --   Any future free-text column must do the same -- do NOT widen the label
  --   grammar to accommodate one.
  --
  -- ARRAY ELEMENT SHAPE
  --   Array measures emit counts only. `label_shaped_elems` uses the SAME
  --   case-insensitive label grammar as the bounded emitter (up to three
  --   letter-initial tokens) -- a lowercase-snake-only test would classify a
  --   Title-Case controlled vocabulary as arbitrary content and mislead the
  --   mapping decision. `sentence_shaped_elems` counts elements that are long
  --   or carry sentence punctuation. Neither emits an element.
  --
  -- ROW-LEVEL DATA IS NEVER EMITTED. Names, free text, coordinates, contact
  --   details and sensitive-identity columns are never read by this section.
  --
  -- SNAPSHOT FIDELITY (see SANITIZATION-CONTRACT.md section 4.1)
  --   sanitized-faithful : every `*_values`, `preference_validity`,
  --                        `gender_compat`, `publication` and bounded enum
  --                        measures.
  --   PRISTINE-ONLY      : full_name / display_name token shape, country,
  --                        body_type and every array measure. The sanitizer
  --                        pseudonymizes/folds/redacts these. Running them against
  --                        the sanitized copy measures the SANITIZER, not
  --                        Date9ja -- record which database produced them.
  -- =========================================================================
  (200, 'source_types', 'measured users columns: data_type/udt_name',
        NULL,
        (SELECT string_agg(column_name || ':' || replace(data_type, ' ', '_') || '/' || udt_name,
                              ' ' ORDER BY column_name)
           FROM information_schema.columns
          WHERE table_schema = current_schema() AND table_name = 'users'
            AND column_name = ANY (
                  ARRAY['body_type','children_count','commitment_timeline','country_of_residence',
                        'dealbreakers','deletion_comment','deletion_reason_code','discovery_restricted_at',
                        'discovery_restricted_by_id','discovery_restriction_note',
                        'discovery_restriction_reason','display_name','drinking','education',
                        'family_involvement_preference','fitness','full_name','gender','height',
                        'interests','languages_spoken','looking_for','marital_status',
                        'onboarding_completed_at','preferred_age_max','preferred_age_min',
                        'preferred_countries','preferred_distance_km','profile_completeness_score',
                        'profile_hidden','relationship_intention','relationship_values',
                        'relocation_preferences','smoking','wants_children','willing_to_relocate']))),
  (201, 'source_types', 'expected value-census columns MISSING from users (must be none)',
        NULL,
        (SELECT COALESCE(string_agg(c, ' ' ORDER BY c), 'none')
           FROM unnest(
                  ARRAY['body_type','children_count','commitment_timeline','country_of_residence',
                        'dealbreakers','deletion_comment','deletion_reason_code','discovery_restricted_at',
                        'discovery_restricted_by_id','discovery_restriction_note',
                        'discovery_restriction_reason','display_name','drinking','education',
                        'family_involvement_preference','fitness','full_name','gender','height',
                        'interests','languages_spoken','looking_for','marital_status',
                        'onboarding_completed_at','preferred_age_max','preferred_age_min',
                        'preferred_countries','preferred_distance_km','profile_completeness_score',
                        'profile_hidden','relationship_intention','relationship_values',
                        'relocation_preferences','smoking','wants_children','willing_to_relocate']) c
          WHERE c NOT IN (SELECT column_name FROM information_schema.columns
                           WHERE table_schema = current_schema() AND table_name = 'users'))),
  (202, 'source_types', 'users columns NOT classified by importer/denylist/value-census/runbook (schema metadata only)',
        NULL,
        (SELECT COALESCE(string_agg(column_name, ' ' ORDER BY column_name), 'none')
           FROM information_schema.columns
          WHERE table_schema = current_schema() AND table_name = 'users'
            AND column_name <> ALL (
                  ARRAY['about_me','admin','attribution_campaign','attribution_content',
                        'attribution_medium','attribution_source','aunty_phobie_language','ban_reason',
                        'banned_at','body_type','browser_name','children_count','city',
                        'commitment_timeline','confirmation_sent_at','confirmation_token',
                        'confirmed_at','country_of_residence','created_at','current_sign_in_at',
                        'current_sign_in_ip','date_of_birth','dealbreakers','deleted_at',
                        'deletion_comment','deletion_reason','deletion_reason_code','denomination','device_type',
                        'discovery_restricted_at','discovery_restricted_by_id','discovery_restriction_note',
                        'discovery_restriction_reason','display_name','drinking',
                        'education','email','email_notification_preferences','encrypted_password',
                        'ethnicity','family_involvement_preference','fitness',
                        'flagged_for_moderation_at','founding_member','full_name','gender','genotype',
                        'height','hide_last_seen','id','ideal_partner_description',
                        'interest_in_nigerian_culture','interests','intertribal_marriage_openness',
                        'is_nigerian','jti','languages_spoken','last_active_at','last_sign_in_at',
                        'last_sign_in_ip','location_latitude','location_longitude','looking_for',
                        'marital_status','nationality','notification_preferences','occupation',
                        'onboarding_completed_at','os_name','phone','phone_verified_at',
                        'polygamy_openness','preferred_age_max','preferred_age_min',
                        'preferred_countries','preferred_distance_km','preferred_ethnicity',
                        'preferred_genotype','preferred_religion','preferred_tribes',
                        'premium_expires_at','profile_completeness_score','profile_hidden','public_id',
                        'relationship_intention','relationship_values','religion',
                        'relocation_preferences','reset_password_sent_at','reset_password_token',
                        'rewind_used_on','seed_account','sign_in_count','signup_source','smoking',
                        'state_of_origin','subscription_status','suspended_at','suspension_reason',
                        'tribe','trust_xp','unconfirmed_email','updated_at','v2_onboarding_answers',
                        'verification_tier','wants_children','willing_to_relocate']))),
  (210, 'profile_values', 'users.gender bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE gender IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.gender IS NULL THEN 'NULL'
                                      WHEN u.gender::text ~ '^-?[0-9]{1,9}$' THEN u.gender::text
                                      WHEN length(u.gender::text) <= 40
                                       AND u.gender::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.gender::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT gender::text) n FROM users WHERE gender IS NOT NULL) d)),
  (211, 'profile_values', 'users.looking_for bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE looking_for IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.looking_for IS NULL THEN 'NULL'
                                      WHEN u.looking_for::text ~ '^-?[0-9]{1,9}$' THEN u.looking_for::text
                                      WHEN length(u.looking_for::text) <= 40
                                       AND u.looking_for::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.looking_for::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT looking_for::text) n FROM users WHERE looking_for IS NOT NULL) d)),
  (212, 'profile_values', 'users.smoking bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE smoking IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.smoking IS NULL THEN 'NULL'
                                      WHEN u.smoking::text ~ '^-?[0-9]{1,9}$' THEN u.smoking::text
                                      WHEN length(u.smoking::text) <= 40
                                       AND u.smoking::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.smoking::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT smoking::text) n FROM users WHERE smoking IS NOT NULL) d)),
  (213, 'profile_values', 'users.drinking bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE drinking IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.drinking IS NULL THEN 'NULL'
                                      WHEN u.drinking::text ~ '^-?[0-9]{1,9}$' THEN u.drinking::text
                                      WHEN length(u.drinking::text) <= 40
                                       AND u.drinking::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.drinking::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT drinking::text) n FROM users WHERE drinking IS NOT NULL) d)),
  (214, 'profile_values', 'users.fitness bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE fitness IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.fitness IS NULL THEN 'NULL'
                                      WHEN u.fitness::text ~ '^-?[0-9]{1,9}$' THEN u.fitness::text
                                      WHEN length(u.fitness::text) <= 40
                                       AND u.fitness::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.fitness::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT fitness::text) n FROM users WHERE fitness IS NOT NULL) d)),
  (215, 'profile_values', 'users.relationship_intention bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE relationship_intention IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.relationship_intention IS NULL THEN 'NULL'
                                      WHEN u.relationship_intention::text ~ '^-?[0-9]{1,9}$' THEN u.relationship_intention::text
                                      WHEN length(u.relationship_intention::text) <= 40
                                       AND u.relationship_intention::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.relationship_intention::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT relationship_intention::text) n FROM users WHERE relationship_intention IS NOT NULL) d)),
  (216, 'profile_values', 'users.commitment_timeline bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE commitment_timeline IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.commitment_timeline IS NULL THEN 'NULL'
                                      WHEN u.commitment_timeline::text ~ '^-?[0-9]{1,9}$' THEN u.commitment_timeline::text
                                      WHEN length(u.commitment_timeline::text) <= 40
                                       AND u.commitment_timeline::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.commitment_timeline::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT commitment_timeline::text) n FROM users WHERE commitment_timeline IS NOT NULL) d)),
  (217, 'profile_values', 'users.wants_children bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE wants_children IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.wants_children IS NULL THEN 'NULL'
                                      WHEN u.wants_children::text ~ '^-?[0-9]{1,9}$' THEN u.wants_children::text
                                      WHEN length(u.wants_children::text) <= 40
                                       AND u.wants_children::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.wants_children::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT wants_children::text) n FROM users WHERE wants_children IS NOT NULL) d)),
  (218, 'profile_values', 'users.marital_status bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE marital_status IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.marital_status IS NULL THEN 'NULL'
                                      WHEN u.marital_status::text ~ '^-?[0-9]{1,9}$' THEN u.marital_status::text
                                      WHEN length(u.marital_status::text) <= 40
                                       AND u.marital_status::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.marital_status::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT marital_status::text) n FROM users WHERE marital_status IS NOT NULL) d)),
  (219, 'profile_values', 'users.education bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE education IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.education IS NULL THEN 'NULL'
                                      WHEN u.education::text ~ '^-?[0-9]{1,9}$' THEN u.education::text
                                      WHEN length(u.education::text) <= 40
                                       AND u.education::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.education::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT education::text) n FROM users WHERE education IS NOT NULL) d)),
  (220, 'profile_values', 'users.family_involvement_preference bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE family_involvement_preference IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.family_involvement_preference IS NULL THEN 'NULL'
                                      WHEN u.family_involvement_preference::text ~ '^-?[0-9]{1,9}$' THEN u.family_involvement_preference::text
                                      WHEN length(u.family_involvement_preference::text) <= 40
                                       AND u.family_involvement_preference::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.family_involvement_preference::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT family_involvement_preference::text) n FROM users WHERE family_involvement_preference IS NOT NULL) d)),
  -- body_type is USER-ENTERED FREE TEXT, not an enum: the onboarding control is
  -- a plain <input> with a suggestion datalist (Date9ja web/src/pages/AuthPages.js
  -- :1520-1528) and the API stores any unrecognised value verbatim
  -- (api/app/controllers/api/v1/me_controller.rb:84-99 `normalize_body_type`
  -- falls back to `raw`; proven by its own test api/test/requests/api/v1/
  -- me_update_test.rb:21-25, which stores "not-a-real-body-type" unchanged).
  -- The generic bounded emitter is therefore NOT safe here -- a short
  -- person-name-shaped or sensitive phrase satisfies the label grammar. This
  -- measure uses a CLOSED ALLOWLIST of the documented historical suggestions
  -- instead; everything else folds to OTHER, fail-closed. Provenance of the
  -- six values (all three agree): me_controller.rb:87-97 canonical targets,
  -- web/src/pages/ProfilePage.js:61-68 select options, AuthPages.js:1521-1528
  -- datalist. Documented aliases (average / plus / big) are deliberately NOT
  -- allowlisted: they only ever reach the column through a path that already
  -- canonicalises them, and folding them to OTHER is the safe direction.
  (221, 'profile_values', 'users.body_type ALLOWLISTED bucket counts (free text; unknown folds to OTHER)',
        (SELECT count(*) FROM users WHERE body_type IS NOT NULL AND btrim(body_type) <> ''),
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                SELECT CASE
                         WHEN u.body_type IS NULL THEN 'NULL'
                         WHEN btrim(u.body_type) = '' THEN 'BLANK'
                         WHEN lower(regexp_replace(btrim(u.body_type), '[[:space:]-]+', '_', 'g'))
                              IN ('slim', 'athletic', 'regular', 'curvy', 'muscular', 'plus_size')
                           THEN lower(regexp_replace(btrim(u.body_type), '[[:space:]-]+', '_', 'g'))
                         ELSE 'OTHER'
                       END b, count(*) c
                  FROM users u GROUP BY 1) t)),
  (225, 'profile_values', 'users.body_type distinct non-blank value count (no values emitted)',
        (SELECT count(DISTINCT body_type) FROM users
          WHERE body_type IS NOT NULL AND btrim(body_type) <> ''),
        'cardinality only -- how far the column drifted from the six documented suggestions'),
  (222, 'profile_values', 'users.willing_to_relocate bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE willing_to_relocate IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.willing_to_relocate IS NULL THEN 'NULL'
                                      WHEN u.willing_to_relocate::text ~ '^-?[0-9]{1,9}$' THEN u.willing_to_relocate::text
                                      WHEN length(u.willing_to_relocate::text) <= 40
                                       AND u.willing_to_relocate::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.willing_to_relocate::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT willing_to_relocate::text) n FROM users WHERE willing_to_relocate IS NOT NULL) d)),
  (223, 'profile_values', 'users.children_count bounded value distribution',
        NULL,
        (SELECT CASE WHEN d.n > 24
                     THEN 'UNBOUNDED distinct:' || d.n || ' null:' ||
                          (SELECT count(*) FROM users WHERE children_count IS NULL)
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.children_count IS NULL THEN 'NULL'
                                      WHEN u.children_count::text ~ '^-?[0-9]{1,9}$' THEN u.children_count::text
                                      WHEN length(u.children_count::text) <= 40
                                       AND u.children_count::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN translate(lower(u.children_count::text), ' ', '_')
                                      ELSE 'OTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(DISTINCT children_count::text) n FROM users WHERE children_count IS NOT NULL) d)),
  (224, 'profile_values', 'users.height aggregate (no per-row values)',
        NULL,
        (SELECT 'null:' || (SELECT count(*) FROM users WHERE height IS NULL)
             || ' present:' || (SELECT count(*) FROM users WHERE height IS NOT NULL)
             || ' min:' || COALESCE((SELECT min(height)::text FROM users), 'n/a')
             || ' max:' || COALESCE((SELECT max(height)::text FROM users), 'n/a'))),
  (230, 'preference_validity', 'preferred_age_min IS NULL',
        (SELECT count(*) FROM users WHERE preferred_age_min IS NULL),
        'no D8N ProfilePreference.min_age input'),
  (231, 'preference_validity', 'preferred_age_max IS NULL',
        (SELECT count(*) FROM users WHERE preferred_age_max IS NULL),
        'no D8N ProfilePreference.max_age input'),
  (232, 'preference_validity', 'both age preferences NULL',
        (SELECT count(*) FROM users WHERE preferred_age_min IS NULL AND preferred_age_max IS NULL),
        'Matching::ProfileParticipant requires both'),
  (233, 'preference_validity', 'preferred_age_min < 18 (D8N floor)',
        (SELECT count(*) FROM users WHERE preferred_age_min IS NOT NULL AND preferred_age_min < 18),
        'violates FieldCatalog min_age gte 18'),
  (234, 'preference_validity', 'preferred_age_min > 120 (D8N ceiling)',
        (SELECT count(*) FROM users WHERE preferred_age_min IS NOT NULL AND preferred_age_min > 120),
        'violates FieldCatalog min_age lte 120'),
  (235, 'preference_validity', 'preferred_age_max < 18 (D8N floor)',
        (SELECT count(*) FROM users WHERE preferred_age_max IS NOT NULL AND preferred_age_max < 18),
        'violates FieldCatalog max_age gte 18'),
  (236, 'preference_validity', 'preferred_age_max > 120 (D8N ceiling)',
        (SELECT count(*) FROM users WHERE preferred_age_max IS NOT NULL AND preferred_age_max > 120),
        'violates FieldCatalog max_age lte 120'),
  (237, 'preference_validity', 'preferred_age_min > preferred_age_max (inverted)',
        (SELECT count(*) FROM users WHERE preferred_age_min IS NOT NULL AND preferred_age_max IS NOT NULL AND preferred_age_min > preferred_age_max),
        'violates FieldCatalog age_range_is_ordered'),
  (238, 'preference_validity', 'age pair VALID for D8N',
        (SELECT count(*) FROM users WHERE preferred_age_min BETWEEN 18 AND 120 AND preferred_age_max BETWEEN 18 AND 120 AND preferred_age_min <= preferred_age_max),
        'migrates unchanged'),
  (240, 'preference_validity', 'preferred_distance_km IS NULL',
        (SELECT count(*) FROM users WHERE preferred_distance_km IS NULL),
        'no D8N ProfilePreference.max_distance_km input'),
  (241, 'preference_validity', 'preferred_distance_km <= 0',
        (SELECT count(*) FROM users WHERE preferred_distance_km IS NOT NULL AND preferred_distance_km <= 0),
        'violates FieldCatalog max_distance_km gt 0'),
  (242, 'preference_validity', 'preferred_distance_km > 500 (D8N ceiling)',
        (SELECT count(*) FROM users WHERE preferred_distance_km IS NOT NULL AND preferred_distance_km > 500),
        'violates FieldCatalog max_distance_km lte 500'),
  (243, 'preference_validity', 'preferred_distance_km VALID for D8N',
        (SELECT count(*) FROM users WHERE preferred_distance_km BETWEEN 1 AND 500),
        'migrates unchanged'),
  (239, 'preference_validity', 'age preference aggregate bounds (no per-row values)',
        NULL,
        (SELECT 'min_age[' || COALESCE(min(preferred_age_min)::text, 'n/a') || '..' ||
                COALESCE(max(preferred_age_min)::text, 'n/a') || '] max_age[' ||
                COALESCE(min(preferred_age_max)::text, 'n/a') || '..' ||
                COALESCE(max(preferred_age_max)::text, 'n/a') || ']' FROM users)),
  (244, 'preference_validity', 'distance preference aggregate bounds (no per-row values)',
        NULL,
        (SELECT 'distance[' || COALESCE(min(preferred_distance_km)::text, 'n/a') || '..' ||
                COALESCE(max(preferred_distance_km)::text, 'n/a') || ']' FROM users)),
  (245, 'preference_validity', 'users ELIGIBLE for a complete ProfilePreference (Pass 2 target)',
        -- `IS TRUE` / `IS NOT TRUE` rather than a bare predicate / NOT: a NULL
        -- input makes the AND-chain NULL, and `WHERE NULL` counts nothing --
        -- which would silently drop the row from BOTH cohorts instead of
        -- partitioning the live population. These two measures MUST sum to the
        -- kept, non-banned population.
        (SELECT count(*) FROM users
          WHERE deleted_at IS NULL AND banned_at IS NULL
            AND (looking_for IS NOT NULL
                   AND preferred_age_min BETWEEN 18 AND 120
                   AND preferred_age_max BETWEEN 18 AND 120
                   AND preferred_age_min <= preferred_age_max
                   AND preferred_distance_km BETWEEN 1 AND 500) IS TRUE),
        'all four required Date9ja preference fields present and inside D8N validation ceilings'),
  (246, 'preference_validity', 'users LACKING at least one required preference input (Pass 2 policy cohort)',
        (SELECT count(*) FROM users
          WHERE deleted_at IS NULL AND banned_at IS NULL
            AND (looking_for IS NOT NULL
                   AND preferred_age_min BETWEEN 18 AND 120
                   AND preferred_age_max BETWEEN 18 AND 120
                   AND preferred_age_min <= preferred_age_max
                   AND preferred_distance_km BETWEEN 1 AND 500) IS NOT TRUE),
        'needs an approved invalid/missing-data policy before Pass 2'),
  (250, 'gender_compat', 'users.gender IS NULL',
        (SELECT count(*) FROM users WHERE gender IS NULL),
        'cannot be a discovery CANDIDATE: EligibilityScope matches profiles.gender exactly'),
  (251, 'gender_compat', 'users.looking_for IS NULL',
        (SELECT count(*) FROM users WHERE looking_for IS NULL),
        'cannot be a discovery VIEWER: interested_in would be empty'),
  (252, 'gender_compat', 'distinct users.gender values',
        (SELECT count(DISTINCT gender::text) FROM users WHERE gender IS NOT NULL),
        'size of the source gender code space'),
  (253, 'gender_compat', 'distinct users.looking_for values',
        (SELECT count(DISTINCT looking_for::text) FROM users WHERE looking_for IS NOT NULL),
        'size of the source looking_for code space'),
  (254, 'gender_compat', 'distinct values present in BOTH gender and looking_for',
        (SELECT count(*) FROM (SELECT DISTINCT gender::text v FROM users WHERE gender IS NOT NULL
                               INTERSECT
                               SELECT DISTINCT looking_for::text FROM users WHERE looking_for IS NOT NULL) s),
        'shared code space: if this equals BOTH distinct counts the columns are reciprocal as-is'),
  (255, 'gender_compat', 'distinct gender values NOT present in looking_for',
        (SELECT count(*) FROM (SELECT DISTINCT gender::text v FROM users WHERE gender IS NOT NULL
                               EXCEPT
                               SELECT DISTINCT looking_for::text FROM users WHERE looking_for IS NOT NULL) s),
        'nonzero means a candidate gender no viewer can express a preference for'),
  (256, 'gender_compat', 'distinct looking_for values NOT present in gender',
        (SELECT count(*) FROM (SELECT DISTINCT looking_for::text v FROM users WHERE looking_for IS NOT NULL
                               EXCEPT
                               SELECT DISTINCT gender::text FROM users WHERE gender IS NOT NULL) s),
        'nonzero means looking_for carries a wider vocabulary (e.g. an everyone/both code)'),
  (257, 'gender_compat', 'users with BOTH gender and looking_for present',
        (SELECT count(*) FROM users WHERE gender IS NOT NULL AND looking_for IS NOT NULL
           AND deleted_at IS NULL AND banned_at IS NULL),
        'reciprocal-capable population once the vocabulary mapping is approved'),
  (258, 'gender_compat', 'gender x looking_for pair distribution (bounded codes only)',
        NULL,
        (SELECT CASE WHEN p.n > 24
                     THEN 'UNBOUNDED distinct_pairs:' || p.n
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.gender IS NULL THEN 'gNULL'
                                      WHEN u.gender::text ~ '^-?[0-9]{1,9}$' THEN 'g' || u.gender::text
                                      WHEN length(u.gender::text) <= 40
                                       AND u.gender::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN 'g' || translate(lower(u.gender::text), ' ', '_')
                                      ELSE 'gOTHER'
                                    END || '/' ||
                                    CASE
                                      WHEN u.looking_for IS NULL THEN 'lNULL'
                                      WHEN u.looking_for::text ~ '^-?[0-9]{1,9}$' THEN 'l' || u.looking_for::text
                                      WHEN length(u.looking_for::text) <= 40
                                       AND u.looking_for::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN 'l' || translate(lower(u.looking_for::text), ' ', '_')
                                      ELSE 'lOTHER'
                                    END b, count(*) c
                               FROM users u GROUP BY 1) t)
                END
           FROM (SELECT count(*) n FROM (SELECT DISTINCT gender::text, looking_for::text FROM users) d) p)),
  -- -----------------------------------------------------------------------
  -- MIGRATION-ELIGIBLE POPULATION AND ONBOARDING PARTITION (ord 259, 290-299)
  --
  -- POPULATION DEFINITION -- taken from the authoritative importer rules, NOT
  -- invented here. `Date9ja::Import::IdentityImport#import_one`
  -- (domains/date9ja/import/identity_import.rb:63-64) skips a source row when
  -- `record.soft_deleted?` or `record.banned?`, and
  -- `Date9ja::Snapshot::UserRecord` (domains/date9ja/snapshot/user_record.rb
  -- :48,50) defines those as `deleted_at.present?` / `banned_at.present?`.
  -- The migration-eligible population is therefore exactly:
  --     deleted_at IS NULL AND banned_at IS NULL
  -- There is no seed/admin exclusion in the importer, so none is applied here;
  -- measures 245/246 already use this same predicate.
  --
  -- ONBOARDING PARTITION -- `onboarding_completed_at IS NOT NULL`, the same
  -- predicate as measures 30 and 270. Onboarding is NOT an eligibility filter;
  -- it splits the eligible population because the two cohorts reached the
  -- `looking_for` column through different write paths.
  --
  -- Each cohort is split into three MUTUALLY EXCLUSIVE buckets -- same code,
  -- differing code, indeterminate (either side NULL) -- so 291+292+293 = 290
  -- and 295+296+297 = 294, and 290+294 = the eligible population. Measure 299
  -- states those sums and reports OK / MISMATCH rather than assuming them.
  -- Counts only; no row-level data.
  -- -----------------------------------------------------------------------
  (259, 'gender_compat', 'gender x looking_for pair distribution, MIGRATION-ELIGIBLE only (bounded codes)',
        (SELECT count(*) FROM users WHERE deleted_at IS NULL AND banned_at IS NULL),
        (SELECT CASE WHEN p.n > 24
                     THEN 'UNBOUNDED distinct_pairs:' || p.n
                     ELSE (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                             SELECT CASE
                                      WHEN u.gender IS NULL THEN 'gNULL'
                                      WHEN u.gender::text ~ '^-?[0-9]{1,9}$' THEN 'g' || u.gender::text
                                      WHEN length(u.gender::text) <= 40
                                       AND u.gender::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN 'g' || translate(lower(u.gender::text), ' ', '_')
                                      ELSE 'gOTHER'
                                    END || '/' ||
                                    CASE
                                      WHEN u.looking_for IS NULL THEN 'lNULL'
                                      WHEN u.looking_for::text ~ '^-?[0-9]{1,9}$' THEN 'l' || u.looking_for::text
                                      WHEN length(u.looking_for::text) <= 40
                                       AND u.looking_for::text ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'
                                        THEN 'l' || translate(lower(u.looking_for::text), ' ', '_')
                                      ELSE 'lOTHER'
                                    END b, count(*) c
                               FROM users u
                              WHERE u.deleted_at IS NULL AND u.banned_at IS NULL
                              GROUP BY 1) t)
                END
           FROM (SELECT count(*) n FROM (SELECT DISTINCT gender::text, looking_for::text FROM users
                                          WHERE deleted_at IS NULL AND banned_at IS NULL) d) p)),
  (290, 'gender_compat', 'MIGRATION-ELIGIBLE population (importer: not soft-deleted, not banned)',
        (SELECT count(*) FROM users WHERE deleted_at IS NULL AND banned_at IS NULL),
        'identity_import.rb:63-64 + user_record.rb:48,50'),
  (291, 'gender_compat', 'eligible AND onboarded: cohort size',
        (SELECT count(*) FROM users
          WHERE deleted_at IS NULL AND banned_at IS NULL AND onboarding_completed_at IS NOT NULL),
        'reached looking_for through the onboarding form'),
  (292, 'gender_compat', 'eligible AND onboarded: looking_for code SAME as gender code',
        (SELECT count(*) FROM users
          WHERE deleted_at IS NULL AND banned_at IS NULL AND onboarding_completed_at IS NOT NULL
            AND (gender::text = looking_for::text) IS TRUE),
        NULL),
  (293, 'gender_compat', 'eligible AND onboarded: looking_for code DIFFERS from gender code',
        (SELECT count(*) FROM users
          WHERE deleted_at IS NULL AND banned_at IS NULL AND onboarding_completed_at IS NOT NULL
            AND (gender::text <> looking_for::text) IS TRUE),
        NULL),
  (294, 'gender_compat', 'eligible AND onboarded: indeterminate (gender or looking_for NULL)',
        (SELECT count(*) FROM users
          WHERE deleted_at IS NULL AND banned_at IS NULL AND onboarding_completed_at IS NOT NULL
            AND (gender IS NULL OR looking_for IS NULL)),
        NULL),
  (295, 'gender_compat', 'eligible AND NOT onboarded: cohort size',
        (SELECT count(*) FROM users
          WHERE deleted_at IS NULL AND banned_at IS NULL AND onboarding_completed_at IS NULL),
        'never submitted the onboarding form'),
  (296, 'gender_compat', 'eligible AND NOT onboarded: looking_for code SAME as gender code',
        (SELECT count(*) FROM users
          WHERE deleted_at IS NULL AND banned_at IS NULL AND onboarding_completed_at IS NULL
            AND (gender::text = looking_for::text) IS TRUE),
        NULL),
  (297, 'gender_compat', 'eligible AND NOT onboarded: looking_for code DIFFERS from gender code',
        (SELECT count(*) FROM users
          WHERE deleted_at IS NULL AND banned_at IS NULL AND onboarding_completed_at IS NULL
            AND (gender::text <> looking_for::text) IS TRUE),
        NULL),
  (298, 'gender_compat', 'eligible AND NOT onboarded: indeterminate (gender or looking_for NULL)',
        (SELECT count(*) FROM users
          WHERE deleted_at IS NULL AND banned_at IS NULL AND onboarding_completed_at IS NULL
            AND (gender IS NULL OR looking_for IS NULL)),
        NULL),
  (299, 'gender_compat', 'partition proof for 290-298 (must read OK)',
        NULL,
        (SELECT 'eligible:' || e.n
             || ' onboarded:' || a.tot || '=' || a.same || '+' || a.diff || '+' || a.ind
             || ' not_onboarded:' || b.tot || '=' || b.same || '+' || b.diff || '+' || b.ind
             || ' ' || CASE WHEN a.tot = a.same + a.diff + a.ind
                             AND b.tot = b.same + b.diff + b.ind
                             AND e.n = a.tot + b.tot
                            THEN 'OK' ELSE 'MISMATCH' END
           FROM (SELECT count(*) n FROM users WHERE deleted_at IS NULL AND banned_at IS NULL) e,
                (SELECT count(*) tot,
                        count(*) FILTER (WHERE (gender::text = looking_for::text) IS TRUE) same,
                        count(*) FILTER (WHERE (gender::text <> looking_for::text) IS TRUE) diff,
                        count(*) FILTER (WHERE gender IS NULL OR looking_for IS NULL) ind
                   FROM users
                  WHERE deleted_at IS NULL AND banned_at IS NULL
                    AND onboarding_completed_at IS NOT NULL) a,
                (SELECT count(*) tot,
                        count(*) FILTER (WHERE (gender::text = looking_for::text) IS TRUE) same,
                        count(*) FILTER (WHERE (gender::text <> looking_for::text) IS TRUE) diff,
                        count(*) FILTER (WHERE gender IS NULL OR looking_for IS NULL) ind
                   FROM users
                  WHERE deleted_at IS NULL AND banned_at IS NULL
                    AND onboarding_completed_at IS NULL) b)),
  (260, 'profile_shape', 'users.full_name token shape (PRISTINE-ONLY; no names emitted)',
        NULL,
        (SELECT 'null:'   || (SELECT count(*) FROM users WHERE full_name IS NULL)
             || ' blank:' || (SELECT count(*) FROM users WHERE full_name IS NOT NULL AND btrim(full_name) = '')
             || ' 1_token:'  || (SELECT count(*) FROM users WHERE btrim(full_name) <> ''
                                  AND array_length(regexp_split_to_array(btrim(full_name), '\s+'), 1) = 1)
             || ' 2_token:'  || (SELECT count(*) FROM users WHERE btrim(full_name) <> ''
                                  AND array_length(regexp_split_to_array(btrim(full_name), '\s+'), 1) = 2)
             || ' 3plus_token:' || (SELECT count(*) FROM users WHERE btrim(full_name) <> ''
                                  AND array_length(regexp_split_to_array(btrim(full_name), '\s+'), 1) >= 3))),
  (261, 'profile_shape', 'users.display_name token shape (PRISTINE-ONLY; no names emitted)',
        NULL,
        (SELECT 'null:'   || (SELECT count(*) FROM users WHERE display_name IS NULL)
             || ' blank:' || (SELECT count(*) FROM users WHERE display_name IS NOT NULL AND btrim(display_name) = '')
             || ' 1_token:'  || (SELECT count(*) FROM users WHERE btrim(display_name) <> ''
                                  AND array_length(regexp_split_to_array(btrim(display_name), '\s+'), 1) = 1)
             || ' 2_token:'  || (SELECT count(*) FROM users WHERE btrim(display_name) <> ''
                                  AND array_length(regexp_split_to_array(btrim(display_name), '\s+'), 1) = 2)
             || ' 3plus_token:' || (SELECT count(*) FROM users WHERE btrim(display_name) <> ''
                                  AND array_length(regexp_split_to_array(btrim(display_name), '\s+'), 1) >= 3))),
  (265, 'country', 'users.country_of_residence value SHAPE classification (no raw values)',
        NULL,
        (SELECT 'null:' || (SELECT count(*) FROM users WHERE country_of_residence IS NULL)
             || ' blank:' || (SELECT count(*) FROM users
                               WHERE country_of_residence IS NOT NULL AND btrim(country_of_residence) = '')
             || ' iso2:' || (SELECT count(*) FROM users WHERE btrim(country_of_residence) ~ '^[A-Za-z]{2}$')
             || ' name_like:' || (SELECT count(*) FROM users
                                   WHERE btrim(country_of_residence) ~ '^[A-Za-z][A-Za-z .-]{2,59}$')
             || ' other:' || (SELECT count(*) FROM users
                               WHERE btrim(country_of_residence) <> ''
                                 AND btrim(country_of_residence) !~ '^[A-Za-z]{2}$'
                                 AND btrim(country_of_residence) !~ '^[A-Za-z][A-Za-z .-]{2,59}$')
             || ' distinct:' || (SELECT count(DISTINCT lower(btrim(country_of_residence))) FROM users
                                  WHERE btrim(country_of_residence) <> ''))),
  (266, 'country', 'users.country_of_residence ALLOWLISTED bucket counts (unknown folds to OTHER)',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
           SELECT CASE
                    WHEN country_of_residence IS NULL OR btrim(country_of_residence) = '' THEN 'NULL'
                    WHEN lower(btrim(country_of_residence)) IN ('ng','nga','nigeria') THEN 'nigeria'
                    WHEN lower(btrim(country_of_residence)) IN ('gb','uk','gbr','united kingdom') THEN 'united_kingdom'
                    WHEN lower(btrim(country_of_residence)) IN ('us','usa','united states',
                         'united states of america') THEN 'united_states'
                    WHEN lower(btrim(country_of_residence)) IN ('ca','can','canada') THEN 'canada'
                    WHEN lower(btrim(country_of_residence)) IN ('gh','gha','ghana') THEN 'ghana'
                    WHEN lower(btrim(country_of_residence)) IN ('za','zaf','south africa') THEN 'south_africa'
                    WHEN lower(btrim(country_of_residence)) IN ('ke','ken','kenya') THEN 'kenya'
                    WHEN lower(btrim(country_of_residence)) IN ('ie','irl','ireland') THEN 'ireland'
                    WHEN lower(btrim(country_of_residence)) IN ('de','deu','germany') THEN 'germany'
                    WHEN lower(btrim(country_of_residence)) IN ('ae','are','united arab emirates') THEN 'uae'
                    ELSE 'OTHER'
                  END b, count(*) c FROM users GROUP BY 1) t)),
  (270, 'publication', 'profile_hidden x onboarding_completed_at cohorts',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
           SELECT CASE WHEN profile_hidden THEN 'hidden' ELSE 'visible' END || '/' ||
                  CASE WHEN onboarding_completed_at IS NOT NULL THEN 'onboarded' ELSE 'not_onboarded' END b,
                  count(*) c FROM users GROUP BY 1) t)),
  (271, 'publication', 'profile_completeness_score bands',
        NULL,
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
           SELECT CASE
                    WHEN profile_completeness_score IS NULL THEN 'NULL'
                    WHEN profile_completeness_score < 0 OR profile_completeness_score > 100 THEN 'OUT_OF_RANGE'
                    WHEN profile_completeness_score = 0 THEN '000'
                    WHEN profile_completeness_score < 50 THEN '001_049'
                    WHEN profile_completeness_score < 80 THEN '050_079'
                    WHEN profile_completeness_score < 100 THEN '080_099'
                    ELSE '100'
                  END b, count(*) c FROM users GROUP BY 1) t)),
  (272, 'publication', 'live + onboarded + not hidden (candidate migrated-publication cohort)',
        (SELECT count(*) FROM users
          WHERE deleted_at IS NULL AND banned_at IS NULL AND suspended_at IS NULL
            AND profile_hidden = false AND onboarding_completed_at IS NOT NULL),
        'candidate only: D8N publication requires Profiles::Completion to pass, not this flag'),
  (280, 'arrays', 'users.interests array shape (PRISTINE-ONLY)',
        NULL,
        (SELECT 'null:'      || (SELECT count(*) FROM users WHERE interests IS NULL)
             || ' empty:'    || (SELECT count(*) FROM users WHERE interests IS NOT NULL AND cardinality(interests) = 0)
             || ' nonempty:' || (SELECT count(*) FROM users WHERE cardinality(interests) > 0)
             || ' max_card:' || COALESCE((SELECT max(cardinality(interests)) FROM users), 0)
             || ' distinct_elems:'     || (SELECT count(DISTINCT e) FROM users, unnest(interests) e)
             || ' label_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(interests) e
                                            WHERE e ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,2}$')
             || ' sentence_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(interests) e
                                            WHERE length(e) > 40 OR e ~ '[.,;:!?]')
             || ' long_elems:'         || (SELECT count(DISTINCT e) FROM users, unnest(interests) e
                                            WHERE length(e) > 40))),
  (281, 'arrays', 'users.relationship_values array shape (PRISTINE-ONLY)',
        NULL,
        (SELECT 'null:'      || (SELECT count(*) FROM users WHERE relationship_values IS NULL)
             || ' empty:'    || (SELECT count(*) FROM users WHERE relationship_values IS NOT NULL AND cardinality(relationship_values) = 0)
             || ' nonempty:' || (SELECT count(*) FROM users WHERE cardinality(relationship_values) > 0)
             || ' max_card:' || COALESCE((SELECT max(cardinality(relationship_values)) FROM users), 0)
             || ' distinct_elems:'     || (SELECT count(DISTINCT e) FROM users, unnest(relationship_values) e)
             || ' label_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(relationship_values) e
                                            WHERE e ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,2}$')
             || ' sentence_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(relationship_values) e
                                            WHERE length(e) > 40 OR e ~ '[.,;:!?]')
             || ' long_elems:'         || (SELECT count(DISTINCT e) FROM users, unnest(relationship_values) e
                                            WHERE length(e) > 40))),
  (282, 'arrays', 'users.dealbreakers array shape (PRISTINE-ONLY)',
        NULL,
        (SELECT 'null:'      || (SELECT count(*) FROM users WHERE dealbreakers IS NULL)
             || ' empty:'    || (SELECT count(*) FROM users WHERE dealbreakers IS NOT NULL AND cardinality(dealbreakers) = 0)
             || ' nonempty:' || (SELECT count(*) FROM users WHERE cardinality(dealbreakers) > 0)
             || ' max_card:' || COALESCE((SELECT max(cardinality(dealbreakers)) FROM users), 0)
             || ' distinct_elems:'     || (SELECT count(DISTINCT e) FROM users, unnest(dealbreakers) e)
             || ' label_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(dealbreakers) e
                                            WHERE e ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,2}$')
             || ' sentence_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(dealbreakers) e
                                            WHERE length(e) > 40 OR e ~ '[.,;:!?]')
             || ' long_elems:'         || (SELECT count(DISTINCT e) FROM users, unnest(dealbreakers) e
                                            WHERE length(e) > 40))),
  (283, 'arrays', 'users.languages_spoken array shape',
        NULL,
        (SELECT 'null:'      || (SELECT count(*) FROM users WHERE languages_spoken IS NULL)
             || ' empty:'    || (SELECT count(*) FROM users WHERE languages_spoken IS NOT NULL AND cardinality(languages_spoken) = 0)
             || ' nonempty:' || (SELECT count(*) FROM users WHERE cardinality(languages_spoken) > 0)
             || ' max_card:' || COALESCE((SELECT max(cardinality(languages_spoken)) FROM users), 0)
             || ' distinct_elems:'     || (SELECT count(DISTINCT e) FROM users, unnest(languages_spoken) e)
             || ' label_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(languages_spoken) e
                                            WHERE e ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,2}$')
             || ' sentence_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(languages_spoken) e
                                            WHERE length(e) > 40 OR e ~ '[.,;:!?]')
             || ' long_elems:'         || (SELECT count(DISTINCT e) FROM users, unnest(languages_spoken) e
                                            WHERE length(e) > 40))),
  (284, 'arrays', 'users.preferred_countries array shape',
        NULL,
        (SELECT 'null:'      || (SELECT count(*) FROM users WHERE preferred_countries IS NULL)
             || ' empty:'    || (SELECT count(*) FROM users WHERE preferred_countries IS NOT NULL AND cardinality(preferred_countries) = 0)
             || ' nonempty:' || (SELECT count(*) FROM users WHERE cardinality(preferred_countries) > 0)
             || ' max_card:' || COALESCE((SELECT max(cardinality(preferred_countries)) FROM users), 0)
             || ' distinct_elems:'     || (SELECT count(DISTINCT e) FROM users, unnest(preferred_countries) e)
             || ' label_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(preferred_countries) e
                                            WHERE e ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,2}$')
             || ' sentence_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(preferred_countries) e
                                            WHERE length(e) > 40 OR e ~ '[.,;:!?]')
             || ' long_elems:'         || (SELECT count(DISTINCT e) FROM users, unnest(preferred_countries) e
                                            WHERE length(e) > 40))),
  (285, 'arrays', 'users.relocation_preferences array shape',
        NULL,
        (SELECT 'null:'      || (SELECT count(*) FROM users WHERE relocation_preferences IS NULL)
             || ' empty:'    || (SELECT count(*) FROM users WHERE relocation_preferences IS NOT NULL AND cardinality(relocation_preferences) = 0)
             || ' nonempty:' || (SELECT count(*) FROM users WHERE cardinality(relocation_preferences) > 0)
             || ' max_card:' || COALESCE((SELECT max(cardinality(relocation_preferences)) FROM users), 0)
             || ' distinct_elems:'     || (SELECT count(DISTINCT e) FROM users, unnest(relocation_preferences) e)
             || ' label_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(relocation_preferences) e
                                            WHERE e ~* '^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,2}$')
             || ' sentence_shaped_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(relocation_preferences) e
                                            WHERE length(e) > 40 OR e ~ '[.,;:!?]')
             || ' long_elems:'         || (SELECT count(DISTINCT e) FROM users, unnest(relocation_preferences) e
                                            WHERE length(e) > 40))),

  -- ---- SENSITIVE identity / culture / health classification (PRISTINE-ONLY) -
  -- Privacy-safe review inputs for SensitiveProfileImport. Every measure emits
  -- ONLY aggregate counts: a per-column ALLOWLIST that mirrors the D8N option
  -- codes (Profiles::CapabilityCatalog), with everything unrecognised folded to
  -- OTHER. No member-entered string is ever emitted. The allowlist_hit /
  -- OTHER split is exactly what the E-5 review needs to decide whether a
  -- column can be reclassified REDACT -> PRESERVE for the reviewed values.
  -- These run PRISTINE-ONLY: the sanitizer NULLs every column below.
  (320, 'sensitive', 'users.is_nigerian distribution (boolean, no free text)',
        NULL,
        (SELECT 'true:' || count(*) FILTER (WHERE is_nigerian IS TRUE)
             || ' false:' || count(*) FILTER (WHERE is_nigerian IS FALSE)
             || ' null:' || count(*) FILTER (WHERE is_nigerian IS NULL) FROM users)),
  (321, 'sensitive', 'users.state_of_origin ALLOWLISTED to the 37 canonical states (unknown -> OTHER)',
        (SELECT count(*) FROM users WHERE state_of_origin IS NOT NULL AND btrim(state_of_origin) <> ''),
        (SELECT 'allowlist_hit:' || count(*) FILTER (
                  WHERE lower(btrim(regexp_replace(state_of_origin, '\s+', ' ', 'g'))) IN (
                    'abia','adamawa','akwa ibom','anambra','bauchi','bayelsa','benue','borno',
                    'cross river','delta','ebonyi','edo','ekiti','enugu','gombe','imo','jigawa',
                    'kaduna','kano','katsina','kebbi','kogi','kwara','lagos','nasarawa','niger',
                    'ogun','ondo','osun','oyo','plateau','rivers','sokoto','taraba','yobe','zamfara',
                    'federal capital territory','fct','abuja'))
             || ' other_nonblank:' || count(*) FILTER (
                  WHERE state_of_origin IS NOT NULL AND btrim(state_of_origin) <> ''
                    AND lower(btrim(regexp_replace(state_of_origin, '\s+', ' ', 'g'))) NOT IN (
                    'abia','adamawa','akwa ibom','anambra','bauchi','bayelsa','benue','borno',
                    'cross river','delta','ebonyi','edo','ekiti','enugu','gombe','imo','jigawa',
                    'kaduna','kano','katsina','kebbi','kogi','kwara','lagos','nasarawa','niger',
                    'ogun','ondo','osun','oyo','plateau','rivers','sokoto','taraba','yobe','zamfara',
                    'federal capital territory','fct','abuja'))
             || ' null_or_blank:' || count(*) FILTER (WHERE state_of_origin IS NULL OR btrim(state_of_origin) = '')
           FROM users)),
  (322, 'sensitive', 'users.nationality shape (ISO-2 vs name vs other; no values)',
        NULL,
        (SELECT 'iso2:' || count(*) FILTER (WHERE btrim(nationality) ~ '^[A-Za-z]{2}$')
             || ' name_like:' || count(*) FILTER (WHERE btrim(nationality) ~ '^[A-Za-z][A-Za-z .-]{2,59}$')
             || ' other_nonblank:' || count(*) FILTER (
                  WHERE nationality IS NOT NULL AND btrim(nationality) <> ''
                    AND btrim(nationality) !~ '^[A-Za-z]{2}$'
                    AND btrim(nationality) !~ '^[A-Za-z][A-Za-z .-]{2,59}$')
             || ' null_or_blank:' || count(*) FILTER (WHERE nationality IS NULL OR btrim(nationality) = '')
           FROM users)),
  (323, 'sensitive', 'users.tribe ALLOWLISTED to D8N tribe codes (unknown -> OTHER)',
        (SELECT count(*) FROM users WHERE tribe IS NOT NULL AND btrim(tribe) <> ''),
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
           SELECT CASE
                    WHEN tribe IS NULL OR btrim(tribe) = '' THEN 'NULL'
                    WHEN lower(btrim(tribe)) IN ('igbo','ibo') THEN 'igbo'
                    WHEN lower(btrim(tribe)) = 'yoruba' THEN 'yoruba'
                    WHEN lower(btrim(tribe)) IN ('hausa','hausa fulani') THEN 'hausa'
                    WHEN lower(btrim(tribe)) = 'fulani' THEN 'fulani'
                    WHEN lower(btrim(tribe)) IN ('ijaw','izon') THEN 'ijaw'
                    WHEN lower(btrim(tribe)) = 'ibibio' THEN 'ibibio'
                    WHEN lower(btrim(tribe)) IN ('edo','bini') THEN 'edo'
                    WHEN lower(btrim(tribe)) = 'kanuri' THEN 'kanuri'
                    ELSE 'OTHER'
                  END b, count(*) c FROM users GROUP BY 1) t)),
  (324, 'sensitive', 'users.ethnicity ALLOWLISTED to D8N ethnicity codes (unknown -> OTHER)',
        (SELECT count(*) FROM users WHERE ethnicity IS NOT NULL AND btrim(ethnicity) <> ''),
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
           SELECT CASE
                    WHEN ethnicity IS NULL OR btrim(ethnicity) = '' THEN 'NULL'
                    WHEN lower(btrim(ethnicity)) IN ('igbo','ibo','yoruba','hausa','fulani','ijaw',
                         'ibibio','edo','bini','kanuri','tiv','nupe','igala','efik','urhobo',
                         'itsekiri','annang','mixed','mixed race') THEN 'allowlist_hit'
                    ELSE 'OTHER'
                  END b, count(*) c FROM users GROUP BY 1) t)),
  (325, 'sensitive', 'users.religion ALLOWLISTED to D8N religion codes (unknown -> OTHER)',
        (SELECT count(*) FROM users WHERE religion IS NOT NULL AND btrim(religion) <> ''),
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
           SELECT CASE
                    WHEN religion IS NULL OR btrim(religion) = '' THEN 'NULL'
                    WHEN lower(btrim(religion)) IN ('christian','christianity','catholic','protestant','pentecostal') THEN 'christian'
                    WHEN lower(btrim(religion)) IN ('muslim','islam','islamic') THEN 'muslim'
                    WHEN lower(btrim(religion)) IN ('traditional','african traditional','spiritual') THEN 'spiritual'
                    WHEN lower(btrim(religion)) IN ('hindu','hinduism','buddhist','buddhism','jewish','judaism',
                         'sikh','sikhism','agnostic','atheist','none') THEN 'allowlist_other_faith'
                    ELSE 'OTHER'
                  END b, count(*) c FROM users GROUP BY 1) t)),
  (326, 'sensitive', 'users.denomination ALLOWLISTED to D8N denomination codes (unknown -> OTHER)',
        (SELECT count(*) FROM users WHERE denomination IS NOT NULL AND btrim(denomination) <> ''),
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
           SELECT CASE
                    WHEN denomination IS NULL OR btrim(denomination) = '' THEN 'NULL'
                    WHEN lower(btrim(regexp_replace(denomination, '\s+', ' ', 'g'))) IN (
                         'catholic','roman catholic','anglican','church of nigeria','pentecostal','baptist',
                         'methodist','presbyterian','orthodox','adventist','seventh day adventist',
                         'evangelical','non denominational','nondenominational','sunni','shia','shiite',
                         'ahmadiyya','none') THEN 'allowlist_hit'
                    ELSE 'OTHER'
                  END b, count(*) c FROM users GROUP BY 1) t)),
  (327, 'sensitive', 'users.genotype ALLOWLISTED to haemoglobin genotypes (health data; unknown -> OTHER)',
        (SELECT count(*) FROM users WHERE genotype IS NOT NULL AND btrim(genotype) <> ''),
        (SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
           SELECT CASE
                    WHEN genotype IS NULL OR btrim(genotype) = '' THEN 'NULL'
                    WHEN upper(btrim(genotype)) IN ('AA','AS','SS','AC','SC','CC') THEN upper(btrim(genotype))
                    WHEN lower(btrim(genotype)) IN ('not tested','unknown','dont know') THEN 'not_tested'
                    ELSE 'OTHER'
                  END b, count(*) c FROM users GROUP BY 1) t)),
  (328, 'sensitive', 'users.intertribal_marriage_openness / polygamy_openness bounded distributions',
        NULL,
        (SELECT 'intertribal[' || COALESCE((SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                   SELECT CASE WHEN intertribal_marriage_openness IS NULL THEN 'NULL'
                               WHEN length(intertribal_marriage_openness::text) <= 20
                                AND intertribal_marriage_openness::text ~* '^[a-z0-9 _-]+$'
                                 THEN lower(intertribal_marriage_openness::text)
                               ELSE 'OTHER' END b, count(*) c FROM users GROUP BY 1) t), 'n/a')
             || '] polygamy[' || COALESCE((SELECT string_agg(b || ':' || c, ' ' ORDER BY b) FROM (
                   SELECT CASE WHEN polygamy_openness IS NULL THEN 'NULL'
                               WHEN length(polygamy_openness::text) <= 20
                                AND polygamy_openness::text ~* '^[a-z0-9 _-]+$'
                                 THEN lower(polygamy_openness::text)
                               ELSE 'OTHER' END b, count(*) c FROM users GROUP BY 1) t), 'n/a') || ']')),
  (329, 'sensitive', 'users.interest_in_nigerian_culture shape only (free text; no values)',
        NULL,
        (SELECT 'null:' || count(*) FILTER (WHERE interest_in_nigerian_culture IS NULL)
             || ' present:' || count(*) FILTER (WHERE interest_in_nigerian_culture IS NOT NULL
                                                  AND btrim(interest_in_nigerian_culture) <> '')
             || ' over_1000_chars:' || count(*) FILTER (WHERE length(interest_in_nigerian_culture) > 1000)
           FROM users)),
  (330, 'sensitive', 'users.preferred_religion / preferred_tribes / preferred_ethnicity / preferred_genotype array shapes',
        NULL,
        (SELECT 'religion[nonempty:' || count(*) FILTER (WHERE cardinality(preferred_religion) > 0)
             || ' distinct_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(preferred_religion) e) || ']'
             || ' tribes[nonempty:' || count(*) FILTER (WHERE cardinality(preferred_tribes) > 0)
             || ' distinct_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(preferred_tribes) e) || ']'
             || ' ethnicity[nonempty:' || count(*) FILTER (WHERE cardinality(preferred_ethnicity) > 0)
             || ' distinct_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(preferred_ethnicity) e) || ']'
             || ' genotype[nonempty:' || count(*) FILTER (WHERE cardinality(preferred_genotype) > 0)
             || ' distinct_elems:' || (SELECT count(DISTINCT e) FROM users, unnest(preferred_genotype) e) || ']'
           FROM users)),

  -- ---- authoritative readiness / liquidity impact (2026-09-08) ---------
  -- The date is pinned to the snapshot timestamp so output is deterministic.
  (300, 'readiness', 'date of birth state', NULL,
        (SELECT 'present:' || count(*) FILTER (WHERE date_of_birth IS NOT NULL)
             || ' missing:' || count(*) FILTER (WHERE date_of_birth IS NULL)
             || ' future:' || count(*) FILTER (WHERE date_of_birth > DATE '2026-09-08')
             || ' adult_18plus:' || count(*) FILTER (WHERE date_of_birth <= DATE '2008-09-08')
             || ' implausible_over_120:' || count(*) FILTER (WHERE date_of_birth < DATE '1906-09-08')
           FROM users)),
  (301, 'readiness', 'preferred age pair state', NULL,
        (SELECT 'complete_valid:' || count(*) FILTER (
                  WHERE preferred_age_min BETWEEN 18 AND 120 AND preferred_age_max BETWEEN 18 AND 120
                    AND preferred_age_min <= preferred_age_max)
             || ' both_null:' || count(*) FILTER (
                  WHERE preferred_age_min IS NULL AND preferred_age_max IS NULL)
             || ' partial:' || count(*) FILTER (
                  WHERE (preferred_age_min IS NULL) <> (preferred_age_max IS NULL))
             || ' invalid:' || count(*) FILTER (
                  WHERE preferred_age_min IS NOT NULL AND preferred_age_max IS NOT NULL
                    AND NOT (preferred_age_min BETWEEN 18 AND 120 AND preferred_age_max BETWEEN 18 AND 120
                             AND preferred_age_min <= preferred_age_max))
           FROM users)),
  (302, 'readiness', 'location/profile geography completeness', NULL,
        (SELECT 'country_present:' || count(*) FILTER (WHERE btrim(country_of_residence) <> '')
             || ' city_present:' || count(*) FILTER (WHERE city IS NOT NULL AND btrim(city) <> '')
             || ' coordinates_pair:' || count(*) FILTER (
                  WHERE location_latitude IS NOT NULL AND location_longitude IS NOT NULL)
             || ' preferred_distance_present:' || count(*) FILTER (WHERE preferred_distance_km IS NOT NULL)
             || ' preferred_countries_nonempty:' || count(*) FILTER (WHERE cardinality(preferred_countries) > 0)
           FROM users)),
  (303, 'readiness', 'photo availability by user', NULL,
        (SELECT 'any_photo:' || count(*) FILTER (WHERE any_photo)
             || ' non_rejected_photo:' || count(*) FILTER (WHERE non_rejected_photo)
             || ' approved_photo:' || count(*) FILTER (WHERE approved_photo)
             || ' no_photo:' || count(*) FILTER (WHERE NOT any_photo)
           FROM (
             SELECT u.id, EXISTS (SELECT 1 FROM photos p WHERE p.user_id=u.id) any_photo,
                    EXISTS (SELECT 1 FROM photos p WHERE p.user_id=u.id AND p.moderation_status <> 2) non_rejected_photo,
                    EXISTS (SELECT 1 FROM photos p WHERE p.user_id=u.id AND p.moderation_status = 1) approved_photo
               FROM users u) d)),
  (304, 'readiness', 'occupation presence',
        (SELECT count(*) FROM users WHERE occupation IS NOT NULL AND btrim(occupation) <> ''),
        'content is never emitted'),
  (305, 'readiness', 'bio presence and length bands', NULL,
        (SELECT 'missing:' || count(*) FILTER (WHERE about_me IS NULL OR btrim(about_me) = '')
             || ' len_1_9:' || count(*) FILTER (WHERE length(btrim(about_me)) BETWEEN 1 AND 9)
             || ' len_10_1000:' || count(*) FILTER (WHERE length(btrim(about_me)) BETWEEN 10 AND 1000)
             || ' len_1001_5000:' || count(*) FILTER (WHERE length(btrim(about_me)) BETWEEN 1001 AND 5000)
             || ' len_over_5000:' || count(*) FILTER (WHERE length(btrim(about_me)) > 5000)
           FROM users)),
  (306, 'readiness', 'ideal-partner text presence and length bands', NULL,
        (SELECT 'missing:' || count(*) FILTER (WHERE ideal_partner_description IS NULL OR btrim(ideal_partner_description) = '')
             || ' len_1_600:' || count(*) FILTER (WHERE length(btrim(ideal_partner_description)) BETWEEN 1 AND 600)
             || ' len_601_5000:' || count(*) FILTER (WHERE length(btrim(ideal_partner_description)) BETWEEN 601 AND 5000)
             || ' len_over_5000:' || count(*) FILTER (WHERE length(btrim(ideal_partner_description)) > 5000)
           FROM users)),
  (307, 'readiness', 'height quality bands', NULL,
        (SELECT 'missing:' || count(*) FILTER (WHERE height IS NULL)
             || ' plausible_cm_100_250:' || count(*) FILTER (WHERE height BETWEEN 100 AND 250)
             || ' outside_cm_100_250:' || count(*) FILTER (WHERE height IS NOT NULL AND height NOT BETWEEN 100 AND 250)
             || ' min:' || COALESCE(min(height)::text, 'n/a')
             || ' max:' || COALESCE(max(height)::text, 'n/a') FROM users)),
  (308, 'readiness', 'body type presence',
        (SELECT count(*) FROM users WHERE body_type IS NOT NULL AND btrim(body_type) <> ''),
        'free text; values never emitted here'),
  (309, 'readiness', 'source-safety eligible market population',
        (SELECT count(*) FROM users WHERE deleted_at IS NULL AND banned_at IS NULL AND suspended_at IS NULL
          AND profile_hidden = false AND discovery_restricted_at IS NULL
          AND gender IN (0,1) AND looking_for IN (0,1)),
        'liquidity-first base; age/location/completion intentionally not applied'),
  (310, 'readiness', 'source-safety eligible excluded by complete-age requirement',
        (SELECT count(*) FROM users WHERE deleted_at IS NULL AND banned_at IS NULL AND suspended_at IS NULL
          AND profile_hidden = false AND discovery_restricted_at IS NULL
          AND gender IN (0,1) AND looking_for IN (0,1)
          AND (preferred_age_min BETWEEN 18 AND 120 AND preferred_age_max BETWEEN 18 AND 120
               AND preferred_age_min <= preferred_age_max) IS NOT TRUE),
        'impact only; approved Date9ja policy does not make age a hard gate'),
  (311, 'readiness', 'source-safety eligible missing city or country',
        (SELECT count(*) FROM users WHERE deleted_at IS NULL AND banned_at IS NULL AND suspended_at IS NULL
          AND profile_hidden = false AND discovery_restricted_at IS NULL
          AND gender IN (0,1) AND looking_for IN (0,1)
          AND (btrim(country_of_residence) = '' OR city IS NULL OR btrim(city) = '')),
        'impact only; approved Date9ja policy does not make location a hard discovery gate'),
  (312, 'readiness', 'source-safety eligible without any non-rejected photo',
        (SELECT count(*) FROM users u WHERE deleted_at IS NULL AND banned_at IS NULL AND suspended_at IS NULL
          AND profile_hidden = false AND discovery_restricted_at IS NULL
          AND gender IN (0,1) AND looking_for IN (0,1)
          AND NOT EXISTS (SELECT 1 FROM photos p WHERE p.user_id=u.id AND p.moderation_status <> 2)),
        'Date9ja shows a placeholder; D8N publication currently requires a photo'),
  (313, 'readiness', 'source-safety eligible satisfying current D8N source-data gates',
        (SELECT count(*) FROM users u WHERE deleted_at IS NULL AND banned_at IS NULL AND suspended_at IS NULL
          AND profile_hidden = false AND discovery_restricted_at IS NULL
          AND gender IN (0,1) AND looking_for IN (0,1)
          AND array_length(regexp_split_to_array(btrim(full_name), '\s+'),1)=2
          AND btrim(display_name) <> '' AND date_of_birth <= DATE '2008-09-08'
          AND btrim(country_of_residence) <> '' AND city IS NOT NULL AND btrim(city) <> ''
          AND about_me IS NOT NULL AND length(btrim(about_me)) >= 10
          AND is_nigerian IS NOT NULL
          AND ((is_nigerian AND state_of_origin IS NOT NULL AND btrim(state_of_origin) <> '' AND
                tribe IS NOT NULL AND btrim(tribe) <> '') OR
               (NOT is_nigerian AND nationality IS NOT NULL AND btrim(nationality) <> ''))
          AND preferred_age_min BETWEEN 18 AND 120 AND preferred_age_max BETWEEN 18 AND 120
          AND preferred_age_min <= preferred_age_max
          AND relationship_intention IS NOT NULL AND children_count IS NOT NULL
          AND wants_children IS NOT NULL AND religion IS NOT NULL
          AND family_involvement_preference IS NOT NULL
          AND v2_onboarding_answers ?& ARRAY['faith_practice','money_providing','settlement','children','conflict']
          AND EXISTS (SELECT 1 FROM photos p WHERE p.user_id=u.id AND p.moderation_status <> 2)),
        'source-data potential only; current importer does not preserve every required field/group'),
  (314, 'validation', 'unknown bounded enum values',
        (SELECT count(*) FROM users WHERE
          (gender IS NOT NULL AND gender NOT IN (0,1)) OR
          (looking_for IS NOT NULL AND looking_for NOT IN (0,1)) OR
          (relationship_intention IS NOT NULL AND relationship_intention NOT IN (0,1,2,3,4,5)) OR
          (commitment_timeline IS NOT NULL AND commitment_timeline NOT IN (0,1,2,3,4)) OR
          (smoking IS NOT NULL AND smoking NOT IN (0,1,2)) OR
          (drinking IS NOT NULL AND drinking NOT IN (0,1,2)) OR
          (fitness IS NOT NULL AND fitness NOT IN (0,1,2)) OR
          (wants_children IS NOT NULL AND wants_children NOT IN (0,1,2)) OR
          (children_count IS NOT NULL AND children_count NOT IN (0,1,2,3)) OR
          (marital_status IS NOT NULL AND marital_status NOT IN (0,1,2)) OR
          (education IS NOT NULL AND education NOT IN (0,1,2,3,4)) OR
          (family_involvement_preference IS NOT NULL AND family_involvement_preference NOT IN (0,1,2))),
        (SELECT 'gender:' || count(*) FILTER (WHERE gender IS NOT NULL AND gender NOT IN (0,1))
             || ' looking_for:' || count(*) FILTER (WHERE looking_for IS NOT NULL AND looking_for NOT IN (0,1))
             || ' relationship_intention:' || count(*) FILTER (WHERE relationship_intention IS NOT NULL AND relationship_intention NOT IN (0,1,2,3,4,5))
             || ' commitment_timeline:' || count(*) FILTER (WHERE commitment_timeline IS NOT NULL AND commitment_timeline NOT IN (0,1,2,3,4))
             || ' lifestyle:' || count(*) FILTER (WHERE (smoking IS NOT NULL AND smoking NOT IN (0,1,2)) OR (drinking IS NOT NULL AND drinking NOT IN (0,1,2)) OR (fitness IS NOT NULL AND fitness NOT IN (0,1,2)))
             || ' family:' || count(*) FILTER (WHERE (wants_children IS NOT NULL AND wants_children NOT IN (0,1,2)) OR (children_count IS NOT NULL AND children_count NOT IN (0,1,2,3)) OR (marital_status IS NOT NULL AND marital_status NOT IN (0,1,2)) OR (education IS NOT NULL AND education NOT IN (0,1,2,3,4)) OR (family_involvement_preference IS NOT NULL AND family_involvement_preference NOT IN (0,1,2)))
           FROM users)),
  (315, 'validation', 'array columns with NULL elements',
        (SELECT count(*) FROM users WHERE
          array_position(languages_spoken,NULL) IS NOT NULL OR array_position(interests,NULL) IS NOT NULL OR
          array_position(relationship_values,NULL) IS NOT NULL OR array_position(dealbreakers,NULL) IS NOT NULL OR
          array_position(preferred_countries,NULL) IS NOT NULL OR array_position(relocation_preferences,NULL) IS NOT NULL),
        'must be zero before array mapping'),
  (316, 'validation', 'array maximum element lengths', NULL,
        (SELECT 'languages:' || COALESCE(max(length(e)),0) FROM users, unnest(languages_spoken) e) || ' ' ||
        (SELECT 'interests:' || COALESCE(max(length(e)),0) FROM users, unnest(interests) e) || ' ' ||
        (SELECT 'relationship_values:' || COALESCE(max(length(e)),0) FROM users, unnest(relationship_values) e) || ' ' ||
        (SELECT 'dealbreakers:' || COALESCE(max(length(e)),0) FROM users, unnest(dealbreakers) e) || ' ' ||
        (SELECT 'preferred_countries:' || COALESCE(max(length(e)),0) FROM users, unnest(preferred_countries) e) || ' ' ||
        (SELECT 'relocation_preferences:' || COALESCE(max(length(e)),0) FROM users, unnest(relocation_preferences) e))
)
SELECT section, measure, source_count, note
FROM census
ORDER BY ord;

ROLLBACK;

\echo ''
\echo 'Source census complete. Paste the table above into'
\echo 'docs/migrations/date9ja-to-d8n/RECONCILIATION.md (Source column + notes),'
\echo 'record the snapshot id / run timestamp, and use it as the importer'
\echo 'dry-run acceptance baseline.'
\echo ''
\echo 'Sections source_types / profile_values / preference_validity /'
\echo 'gender_compat / profile_shape / country / publication / arrays (ord 200+)'
\echo 'also go into docs/migrations/date9ja-to-d8n/PROFILE-VALUE-MAPPING.md.'
\echo 'Record WHICH database produced them: profile_shape (260/261), country,'
\echo 'body_type and every array row (280-285) are PRISTINE-ONLY -- against'
\echo 'the sanitized copy they measure the sanitizer, not source values.'
\echo 'Measure 202 must read "none"; anything listed there is an unclassified'
\echo 'source column that has to be classified before Pass 2.'
