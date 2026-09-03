-- =============================================================================
-- Date9ja SOURCE-schema signature contract  (canonical — v2, 2026-09-02)
-- =============================================================================
-- ONE definition, included (\ir) by every Date9ja source-adapter script:
--   scripts/date9ja/sanitize_snapshot.sql
--   scripts/date9ja/verify_sanitized_snapshot.sql
--   scripts/date9ja/source_census.sql
--
-- This is Date9ja SOURCE ADAPTER tooling. It is allowed to know Date9ja's
-- legacy schema. It does NOT belong in shared D8N migration primitives.
--
-- WHY v2
--   The v1 guard hashed only `table_name.column_name`, so a type-only,
--   nullability-only or ordinal-position-only change to the classified source
--   schema could pass. v2 makes the guard a genuine structural-compatibility
--   contract: any change an importer or the sanitizer could care about aborts
--   the run.
--
-- WHAT THE SIGNATURE COVERS (per column, ordered by table_name, ordinal_position)
--   table_schema, table_name, ordinal_position, column_name,
--   data_type, udt_name (true type identity, incl. array element type),
--   is_nullable,
--   character_maximum_length, numeric_precision, numeric_scale,
--   datetime_precision,
--   column_default  (sequence defaults normalised to 'SEQ' — a column either is
--                    or is not serial; the sequence name is derived from the
--                    table and its rendering differs by PG version / dump style).
--
-- WHAT IT DELIBERATELY EXCLUDES (unstable / environment-specific / irrelevant)
--   udt_catalog (database name), collation_name (locale), dtd_identifier,
--   generation expressions (none in this schema), comments, storage/TOAST,
--   index/constraint metadata (checked structurally elsewhere), grantees.
--
-- EXPECTED VALUES
--   Computed from the operator's schema-only artifact
--   (~/date9ja-snapshot-work/schema/date9ja-production-schema.sql), 2026-09-02.
--   No raw production database was accessed.
--
--     v2 signature : 41a653a8d4c25621071fb76e6e59fbc0
--     base tables  : 51  (exact set asserted below)
--     columns      : 574
--
--   PG-version note: `information_schema` renders data_type / udt_name /
--   precisions identically across PG 14–17, and sequence defaults are
--   normalised, so this value is expected to hold on the operator's PG17
--   snapshot. On the FIRST v2 run the operator confirms it by running THIS
--   FILE standalone (it is self-contained and read-only):
--     psql -d date9ja_snapshot_sanitized -f scripts/date9ja/schema_signature.sql
--   -> prints "Date9ja schema signature OK (v2 41a653a8...)"  = confirmed.
--   -> RAISEs "SCHEMA DRIFT: ... signature <X> != expected"    = <X> is the
--      operator-observed value; if the only cause is a PG17 default-rendering
--      difference, pin <X> in v_expect_sig below and record the one-line diff
--      in SANITIZATION-CONTRACT.md §3. Do NOT weaken the contract to pass.
-- =============================================================================

DO $date9ja_schema_signature$
DECLARE
  v_expect_sig    text := '41a653a8d4c25621071fb76e6e59fbc0';
  v_expect_cols   int  := 574;
  v_tables        int;
  v_cols          int;
  v_sig           text;
  v_missing       text;
  v_extra         text;
  v_expected_tables text[] := ARRAY[
    'active_storage_attachments','active_storage_blobs','active_storage_variant_records',
    'ar_internal_metadata','audit_logs','aunty_phobie_conversations','aunty_phobie_messages',
    'aunty_phobie_usage_events','blocks','career_applications','career_jobs',
    'community_answer_votes','community_answers','community_event_rsvps','community_events',
    'community_questions','community_remarks','community_reports','community_stories',
    'company_goals','company_journal_entries','company_settings','daily_introductions',
    'daily_life_entries','dating_hub_batches','error_logs','explore_impressions',
    'feedback_items','likes','matches','message_reactions','messages','notification_deliveries',
    'notifications','personas','phone_verifications','photos','profile_passes','profile_videos',
    'profile_views','push_tokens','reports','schema_migrations','selfie_verifications',
    'tracked_contact_notes','tracked_contacts','trust_adjustments','trust_events','users',
    'verification_checks','verification_events'
  ];
BEGIN
  -- (a) exact base-table COUNT
  SELECT count(*) INTO v_tables
  FROM information_schema.tables
  WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
  IF v_tables <> array_length(v_expected_tables, 1) THEN
    RAISE EXCEPTION 'SCHEMA DRIFT: expected % public base tables, found % (wrong database, or migrations applied)',
      array_length(v_expected_tables, 1), v_tables;
  END IF;

  -- (b) exact base-table SET (names) — missing
  SELECT string_agg(t, ', ' ORDER BY t) INTO v_missing
  FROM unnest(v_expected_tables) t
  WHERE t NOT IN (SELECT table_name FROM information_schema.tables
                  WHERE table_schema = 'public' AND table_type = 'BASE TABLE');
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'SCHEMA DRIFT: expected table(s) missing: %', v_missing;
  END IF;

  -- (c) exact base-table SET (names) — extra
  SELECT string_agg(table_name, ', ' ORDER BY table_name) INTO v_extra
  FROM information_schema.tables
  WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    AND table_name <> ALL (v_expected_tables);
  IF v_extra IS NOT NULL THEN
    RAISE EXCEPTION 'SCHEMA DRIFT: unexpected table(s) present (classify in SANITIZATION-CONTRACT.md first): %', v_extra;
  END IF;

  -- (d) exact column count
  SELECT count(*) INTO v_cols
  FROM information_schema.columns
  WHERE table_schema = 'public';
  IF v_cols <> v_expect_cols THEN
    RAISE EXCEPTION 'SCHEMA DRIFT: expected % public columns, found %', v_expect_cols, v_cols;
  END IF;

  -- (e) canonical v2 structural signature
  SELECT md5(string_agg(
           table_schema            || '|' ||
           table_name              || '|' ||
           ordinal_position        || '|' ||
           column_name             || '|' ||
           data_type               || '|' ||
           udt_name                || '|' ||
           is_nullable             || '|' ||
           coalesce(character_maximum_length::text, '') || '|' ||
           coalesce(numeric_precision::text,        '') || '|' ||
           coalesce(numeric_scale::text,            '') || '|' ||
           coalesce(datetime_precision::text,       '') || '|' ||
           coalesce(regexp_replace(column_default, '^nextval\(''[^'']*''::regclass\)$', 'SEQ'), ''),
           E'\n' ORDER BY table_name COLLATE "C", ordinal_position))
    INTO v_sig
  FROM information_schema.columns
  WHERE table_schema = 'public';

  IF v_sig IS DISTINCT FROM v_expect_sig THEN
    RAISE EXCEPTION
      'SCHEMA DRIFT: Date9ja source-schema signature % != expected % (v2). '
      'Type / nullability / ordinal / default / new-or-renamed column drift. '
      'Re-classify every changed column in SANITIZATION-CONTRACT.md and re-pin the signature before re-running.',
      v_sig, v_expect_sig;
  END IF;

  RAISE NOTICE 'Date9ja schema signature OK (v2 %, % tables, % columns)', v_sig, v_tables, v_cols;
END
$date9ja_schema_signature$;
