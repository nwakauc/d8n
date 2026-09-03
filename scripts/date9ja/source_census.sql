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
-- Schema-drift guard — canonical Date9ja source-schema signature (v2), shared
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
        (SELECT count(*) FROM feedback_items WHERE reviewed_at IS NULL), 'review queue continuity')
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
