# frozen_string_literal: true

require "test_helper"
require_relative "../../support/date9ja_census_sql"

module Date9ja
  # Executes the COMMITTED SQL of the Pass-1 profile/preference value census
  # (`scripts/date9ja/source_census.sql`, ord 200-299) against a synthetic
  # Date9ja-shaped `users` table in an isolated schema.
  #
  # The measures under test are read out of the real script by
  # Date9jaCensusSql, so these assertions cover the exact text an operator runs
  # against the snapshot -- not a transcription of it. No snapshot, no
  # production, and no Date9ja data is involved: every row here is invented in
  # the test.
  class ProfileValueCensusTest < ActiveSupport::TestCase
    FIXTURE_SCHEMA = "d9j_value_census_fixture"

    # Column list mirrors SNAPSHOT-RUNBOOK.md section 4 `users`. `gender` and
    # `looking_for` are parameterised because settling their real storage type is
    # the whole point of the census -- the emitter has to behave identically
    # whichever it turns out to be.
    def create_fixture!(gender_type: "integer", looking_for_type: "integer", extra: {}, omit: [])
      columns = {
        "id" => "bigint PRIMARY KEY",
        "gender" => gender_type,
        "looking_for" => looking_for_type,
        "smoking" => "integer",
        "drinking" => "integer",
        "fitness" => "integer",
        "relationship_intention" => "integer",
        "commitment_timeline" => "integer",
        "wants_children" => "integer",
        "children_count" => "integer",
        "marital_status" => "integer",
        "education" => "integer",
        "family_involvement_preference" => "integer",
        "body_type" => "character varying",
        "height" => "integer",
        "willing_to_relocate" => "boolean",
        "preferred_age_min" => "integer",
        "preferred_age_max" => "integer",
        "preferred_distance_km" => "integer",
        "country_of_residence" => "character varying",
        "profile_hidden" => "boolean NOT NULL DEFAULT false",
        "onboarding_completed_at" => "timestamp",
        "profile_completeness_score" => "integer",
        "full_name" => "character varying",
        "display_name" => "character varying",
        "interests" => "character varying[]",
        "relationship_values" => "character varying[]",
        "dealbreakers" => "character varying[]",
        "languages_spoken" => "character varying[]",
        "preferred_countries" => "character varying[]",
        "relocation_preferences" => "character varying[]",
        "deleted_at" => "timestamp",
        "banned_at" => "timestamp",
        "suspended_at" => "timestamp",
        "discovery_restricted_at" => "timestamp",
        "discovery_restriction_reason" => "character varying",
        "discovery_restriction_note" => "text",
        "discovery_restricted_by_id" => "bigint",
        "deletion_reason_code" => "character varying",
        "deletion_comment" => "text"
      }.merge(extra).except(*omit)

      definition = columns.map { |name, type| "#{connection.quote_column_name(name)} #{type}" }.join(", ")
      connection.execute("CREATE SCHEMA #{FIXTURE_SCHEMA}")
      connection.execute("SET LOCAL search_path TO #{FIXTURE_SCHEMA}")
      connection.execute("CREATE TABLE users (#{definition})")
      @fixture_columns = columns.keys
      @next_id = 0
    end

    def insert!(**attributes)
      @next_id += 1
      row = { "id" => @next_id }.merge(attributes.transform_keys(&:to_s))
      unknown = row.keys - @fixture_columns
      raise ArgumentError, "unknown fixture column(s): #{unknown.join(', ')}" if unknown.any?

      names = row.keys.map { |name| connection.quote_column_name(name) }.join(", ")
      values = row.values.map { |value| quote_value(value) }.join(", ")
      connection.execute("INSERT INTO users (#{names}) VALUES (#{values})")
    end

    def quote_value(value)
      case value
      when nil then "NULL"
      when Array then "ARRAY[#{value.map { |item| connection.quote(item) }.join(', ')}]::character varying[]"
      when true, false, Integer then connection.quote(value)
      else connection.quote(value)
      end
    end

    def connection = ActiveRecord::Base.connection

    # Runs one census measure exactly as committed and returns [count, note].
    def census(ord)
      measure = Date9jaCensusSql.measure(ord)
      row = connection.select_one(measure.select_sql)
      [ row["source_count"], row["note"] ]
    end

    def note(ord) = census(ord).last

    def count(ord) = census(ord).first

    # Parses a `key:value key:value` note into a hash of integers.
    def buckets(ord)
      note(ord).to_s.split(" ").to_h do |pair|
        key, value = pair.split(":", 2)
        [ key, Integer(value) ]
      end
    end

    teardown do
      connection.execute("SET LOCAL search_path TO public")
    rescue ActiveRecord::StatementInvalid
      # A test that deliberately provokes a SQL error leaves the transaction
      # aborted; the surrounding test transaction still rolls everything back.
      nil
    end

    # Runs a statement that is expected to raise, inside a savepoint, so the
    # outer test transaction stays usable afterwards.
    def assert_sql_error(pattern, &block)
      error = assert_raises(ActiveRecord::StatementInvalid) do
        connection.transaction(requires_new: true, &block)
      end
      assert_match pattern, error.message
      error
    end

    # -- structure / privacy contract (no database) ---------------------------

    test "the committed script keeps its read-only, guarded, rolled-back scaffolding" do
      sql = Date9jaCensusSql.source

      assert_includes sql, "SET TRANSACTION READ ONLY"
      assert_includes sql, "ROLLBACK;"
      assert_includes sql, "\\ir schema_signature.sql"
      assert_operator sql.index("\\ir schema_signature.sql"), :<, sql.index("WITH census("),
        "the schema guard must run before any count is read"
    end

    test "every Pass-1 measure has a unique ord in a known section" do
      pass1 = Date9jaCensusSql.measures_in(200..299)

      assert_equal 69, pass1.size
      assert_equal pass1.keys, pass1.keys.uniq
      assert_equal(
        %w[arrays country gender_compat preference_validity profile_shape profile_values publication source_types],
        pass1.values.map(&:section).uniq.sort
      )
    end

    test "every bounded-vocabulary measure carries the full emitter safety contract" do
      Date9jaCensusSql.measures_in(200..299).each_value do |measure|
        next unless measure.name.include?("bounded value distribution")

        sql = measure.note_sql
        assert_includes sql, "d.n > 24", "#{measure.name}: missing the distinct-cardinality cap"
        assert_includes sql, "UNBOUNDED distinct:", "#{measure.name}: missing the unbounded fallback"
        assert_includes sql, "'^-?[0-9]{1,9}$'", "#{measure.name}: missing the integer-code grammar"
        assert_includes sql, "'^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$'",
          "#{measure.name}: missing the letter-initial, max-four-token safe-string grammar"
        assert_includes sql, "ELSE 'OTHER'", "#{measure.name}: missing the OTHER fold"
        assert_includes sql, "length(u.", "#{measure.name}: missing the value length cap"
      end
    end

    test "no Pass-1 measure reads a redacted, sensitive or contact column" do
      forbidden = %w[
        email phone encrypted_password about_me ideal_partner_description city
        location_latitude location_longitude tribe religion denomination ethnicity
        state_of_origin nationality genotype preferred_tribes preferred_religion
        v2_onboarding_answers notification_preferences email_notification_preferences
        current_sign_in_ip last_sign_in_ip deletion_reason suspension_reason ban_reason
      ]

      Date9jaCensusSql.measures_in(200..299).each_value do |measure|
        # ord 202 legitimately names classified columns as *schema metadata* in an
        # exclusion list; it never reads their values.
        next if [ 200, 201, 202 ].include?(measure.ord)

        body = "#{measure.count_sql} #{measure.note_sql}"
        forbidden.each do |column|
          refute_match(/\b#{Regexp.escape(column)}\b/, body,
            "#{measure.ord} #{measure.name} must not reference #{column}")
        end
      end
    end

    # -- source types ---------------------------------------------------------

    test "source_types reports the real storage type of every measured column" do
      create_fixture!(gender_type: "integer", looking_for_type: "character varying")

      types = note(200).split(" ").to_h { |pair| pair.split(":", 2) }

      assert_equal "integer/int4", types.fetch("gender")
      assert_equal "character_varying/varchar", types.fetch("looking_for")
      assert_equal "ARRAY/_varchar", types.fetch("interests")
      assert_equal "boolean/bool", types.fetch("profile_hidden")
      assert_equal 36, types.size
    end

    test "source_types reports no missing columns for a complete users table" do
      create_fixture!

      assert_equal "none", note(201)
    end

    test "source_types names an expected column that the source does not have" do
      create_fixture!(omit: %w[commitment_timeline preferred_distance_km])

      assert_equal "commitment_timeline preferred_distance_km", note(201)
    end

    test "source_types reports no unclassified columns for the documented users shape" do
      create_fixture!

      assert_equal "none", note(202)
    end

    test "source_types surfaces an unclassified column such as a meeting-pace source" do
      create_fixture!(extra: { "meeting_pace" => "integer", "first_date_style" => "integer" })

      assert_equal "first_date_style meeting_pace", note(202)
    end

    # -- bounded vocabulary ---------------------------------------------------

    test "an integer-coded gender column emits its codes and NULL count" do
      create_fixture!(gender_type: "integer")
      2.times { insert!(gender: 0) }
      3.times { insert!(gender: 1) }
      insert!(gender: 2)
      4.times { insert!(gender: nil) }

      assert_equal({ "0" => 2, "1" => 3, "2" => 1, "NULL" => 4 }, buckets(210))
    end

    test "a string gender column emits the same shape, lower-cased" do
      create_fixture!(gender_type: "character varying")
      2.times { insert!(gender: "Woman") }
      insert!(gender: "man")
      insert!(gender: "NON binary")
      insert!(gender: nil)

      assert_equal({ "woman" => 2, "man" => 1, "non_binary" => 1, "NULL" => 1 },
                   buckets(210), "spaces normalise to underscores so the output stays unambiguous")
    end

    test "negative and unexpected bounded codes are still emitted as codes" do
      create_fixture!(gender_type: "integer")
      insert!(gender: -3)
      insert!(gender: 777)

      assert_equal({ "-3" => 1, "777" => 1 }, buckets(210))
    end

    test "adversarial string values fold to OTHER and are never echoed" do
      create_fixture!(gender_type: "character varying")
      adversarial = [
        "evil/haxx; DROP TABLE users;--",
        "weird_leaked_value user@secret.com",
        "SketchyModel<script>alert(1)</script>",
        "+2348012345678",
        "a" * 60
      ]
      adversarial.each { |value| insert!(gender: value) }
      insert!(gender: "woman")

      emitted = note(210)

      assert_equal({ "OTHER" => 5, "woman" => 1 }, buckets(210))
      adversarial.each do |value|
        refute_includes emitted, value
        refute_includes emitted, value.downcase
      end
      refute_includes emitted, "secret.com"
      refute_includes emitted, "DROP TABLE"
    end

    test "a high-cardinality column emits only its distinct and NULL counts" do
      create_fixture!(gender_type: "character varying")
      30.times { |index| insert!(gender: "value #{index}") }
      2.times { insert!(gender: nil) }

      emitted = note(210)

      assert_equal "UNBOUNDED distinct:30 null:2", emitted
      refute_includes emitted, "value_0"
    end

    test "a column of exactly the cardinality cap still emits its values" do
      create_fixture!(gender_type: "integer")
      24.times { |index| insert!(gender: index) }

      assert_equal 24, buckets(210).size
      refute_includes note(210), "UNBOUNDED"
    end

    test "every lifestyle and relationship column uses the same emitter" do
      create_fixture!
      insert!(smoking: 0, drinking: 1, fitness: 2, relationship_intention: 3,
              commitment_timeline: 1, wants_children: 0, marital_status: 2,
              education: 4, family_involvement_preference: 1, body_type: "athletic",
              willing_to_relocate: true, children_count: 2)
      insert!

      { 212 => { "0" => 1, "NULL" => 1 }, 213 => { "1" => 1, "NULL" => 1 },
        214 => { "2" => 1, "NULL" => 1 }, 215 => { "3" => 1, "NULL" => 1 },
        216 => { "1" => 1, "NULL" => 1 }, 217 => { "0" => 1, "NULL" => 1 },
        218 => { "2" => 1, "NULL" => 1 }, 219 => { "4" => 1, "NULL" => 1 },
        220 => { "1" => 1, "NULL" => 1 }, 221 => { "athletic" => 1, "NULL" => 1 },
        222 => { "true" => 1, "NULL" => 1 }, 223 => { "2" => 1, "NULL" => 1 } }.each do |ord, expected|
        assert_equal expected, buckets(ord), "measure #{ord} (#{Date9jaCensusSql.measure(ord).name})"
      end
    end

    # -- body_type: free text, closed allowlist ------------------------------
    #
    # body_type is NOT an enum. The onboarding control is a free-text <input>
    # with a suggestion datalist and the API stores unrecognised values verbatim
    # (Date9ja api/app/controllers/api/v1/me_controller.rb:84-99). The generic
    # label grammar would therefore let a short arbitrary phrase escape, so
    # measure 221 uses a closed allowlist instead. These tests exist to prove
    # only the six documented historical suggestions can ever leave as labels.

    test "body_type uses a closed allowlist, never the generic label grammar" do
      sql = Date9jaCensusSql.measure(221).note_sql

      assert_includes sql, "'slim', 'athletic', 'regular', 'curvy', 'muscular', 'plus_size'",
        "measure 221 must name the documented historical suggestions explicitly"
      assert_includes sql, "ELSE 'OTHER'", "measure 221 must fold unknown values to OTHER"
      refute_includes sql, "^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,3}$",
        "body_type is free text: the generic label grammar must never be applied to it"
      refute_includes sql, "d.n > 24",
        "an allowlist needs no cardinality cap; relying on one would be weaker"
    end

    test "body_type emits only allowlisted values and folds every other value to OTHER" do
      create_fixture!
      %w[slim athletic regular curvy muscular plus_size].each { |value| insert!(body_type: value) }
      insert!(body_type: "Plus Size")                    # allowlisted, case + space form
      insert!(body_type: "plus-size")                    # allowlisted, hyphen form
      insert!(body_type: "Ngozi")                        # short person-name-shaped
      insert!(body_type: "living with sickle cell")      # short health/sensitive phrase
      insert!(body_type: "just ask me")                  # short ordinary free-text phrase
      insert!(body_type: "tall dark handsome")           # punctuation-free arbitrary words
      insert!(body_type: "banana")                       # unknown single word
      insert!(body_type: "")                             # blank
      insert!                                            # NULL

      assert_equal({ "slim" => 1, "athletic" => 1, "regular" => 1, "curvy" => 1,
                     "muscular" => 1, "plus_size" => 3,
                     "OTHER" => 5, "BLANK" => 1, "NULL" => 1 }, buckets(221))
      assert_equal 13, count(221), "source_count counts present, non-blank values"
      assert_equal 13, count(225), "distinct non-blank values, no values emitted"
    end

    test "no non-allowlisted body_type token reaches the census output" do
      create_fixture!
      adversarial = [
        "Ngozi", "Adaeze Okafor", "living with sickle cell", "just ask me",
        "tall dark handsome", "recovering from surgery", "banana"
      ]
      adversarial.each { |value| insert!(body_type: value) }
      insert!(body_type: "athletic")

      emitted = census(221).join(" ").downcase
      needles = adversarial.flat_map { |value| [ value.downcase, *value.scan(/[A-Za-z]{4,}/) ] }.uniq
      needles.each do |needle|
        refute_includes emitted, needle.downcase, "measure 221 leaked #{needle.inspect}"
      end
      assert_equal({ "athletic" => 1, "OTHER" => 7 }, buckets(221))
    end

    test "a high-cardinality free-text body_type column still emits only OTHER" do
      create_fixture!
      40.times { |n| insert!(body_type: "unrepeated phrase number #{n}") }
      insert!(body_type: "curvy")

      assert_equal({ "curvy" => 1, "OTHER" => 40 }, buckets(221))
      assert_equal 41, count(225)
    end

    test "height is reported as an aggregate, never per row" do
      create_fixture!
      insert!(height: 150)
      insert!(height: 191)
      insert!(height: nil)

      assert_equal "null:1 present:2 min:150 max:191", note(224)
    end

    # -- preference validity --------------------------------------------------

    test "age and distance preference validity is measured against the D8N ceilings" do
      create_fixture!
      insert!(preferred_age_min: nil, preferred_age_max: nil, preferred_distance_km: nil)
      insert!(preferred_age_min: 17, preferred_age_max: 30, preferred_distance_km: 0)
      insert!(preferred_age_min: 25, preferred_age_max: 130, preferred_distance_km: 900)
      insert!(preferred_age_min: 40, preferred_age_max: 30, preferred_distance_km: 50)
      insert!(preferred_age_min: 121, preferred_age_max: 17, preferred_distance_km: 500)
      insert!(preferred_age_min: 24, preferred_age_max: 38, preferred_distance_km: 100)

      assert_equal 1, count(230), "preferred_age_min IS NULL"
      assert_equal 1, count(231), "preferred_age_max IS NULL"
      assert_equal 1, count(232), "both NULL"
      assert_equal 1, count(233), "min below 18"
      assert_equal 1, count(234), "min above 120"
      assert_equal 1, count(235), "max below 18"
      assert_equal 1, count(236), "max above 120"
      assert_equal 2, count(237), "inverted range"
      assert_equal 1, count(238), "valid pair"
      assert_equal 1, count(240), "distance NULL"
      assert_equal 1, count(241), "distance <= 0"
      assert_equal 1, count(242), "distance above 500"
      assert_equal 3, count(243), "distance valid (50, 500 and 100 are all inside 1..500)"
    end

    test "preference aggregate bounds expose ranges, not rows" do
      create_fixture!
      insert!(preferred_age_min: 21, preferred_age_max: 35, preferred_distance_km: 25)
      insert!(preferred_age_min: 30, preferred_age_max: 60, preferred_distance_km: 400)

      assert_equal "min_age[21..30] max_age[35..60]", note(239)
      assert_equal "distance[25..400]", note(244)
    end

    test "aggregate bounds are safe on an empty table" do
      create_fixture!

      assert_equal "min_age[n/a..n/a] max_age[n/a..n/a]", note(239)
      assert_equal "distance[n/a..n/a]", note(244)
      assert_equal "null:0 present:0 min:n/a max:n/a", note(224)
    end

    test "ProfilePreference eligibility splits the live population exactly once" do
      create_fixture!
      # eligible
      insert!(looking_for: 1, preferred_age_min: 24, preferred_age_max: 38, preferred_distance_km: 100)
      # missing looking_for
      insert!(looking_for: nil, preferred_age_min: 24, preferred_age_max: 38, preferred_distance_km: 100)
      # inverted ages
      insert!(looking_for: 1, preferred_age_min: 40, preferred_age_max: 30, preferred_distance_km: 100)
      # distance out of range
      insert!(looking_for: 1, preferred_age_min: 24, preferred_age_max: 38, preferred_distance_km: 900)
      # eligible but soft-deleted -> outside the live population entirely
      insert!(looking_for: 1, preferred_age_min: 24, preferred_age_max: 38,
              preferred_distance_km: 100, deleted_at: "2026-01-01")
      # eligible but banned -> outside the live population entirely
      insert!(looking_for: 1, preferred_age_min: 24, preferred_age_max: 38,
              preferred_distance_km: 100, banned_at: "2026-01-01")

      assert_equal 1, count(245), "eligible for a complete ProfilePreference"
      assert_equal 3, count(246), "lacking at least one required input"
    end

    test "eligibility and its complement always partition the live population" do
      create_fixture!
      # A NULL in any input makes the AND-chain NULL, not false. With a bare
      # predicate/NOT pair such a row falls out of BOTH cohorts.
      insert!(looking_for: 1, preferred_age_min: 24, preferred_age_max: 38, preferred_distance_km: 100)
      insert!(looking_for: 1, preferred_age_min: 24, preferred_age_max: 38, preferred_distance_km: nil)
      insert!(looking_for: nil, preferred_age_min: nil, preferred_age_max: nil, preferred_distance_km: nil)
      insert!(looking_for: 1, preferred_age_min: 40, preferred_age_max: 30, preferred_distance_km: 100)
      # outside the live population entirely
      insert!(looking_for: 1, preferred_age_min: 24, preferred_age_max: 38,
              preferred_distance_km: 100, deleted_at: "2026-01-01")

      live = connection.select_value(
        "SELECT count(*) FROM users WHERE deleted_at IS NULL AND banned_at IS NULL"
      )

      assert_equal 4, live
      assert_equal 1, count(245)
      assert_equal 3, count(246)
      assert_equal live, count(245) + count(246),
        "245 and 246 must partition the kept, non-banned population exactly"
    end

    test "every row with a NULL distance lands in the lacking cohort, not nowhere" do
      create_fixture!
      3.times { insert!(looking_for: 0, preferred_age_min: 25, preferred_age_max: 35, preferred_distance_km: nil) }

      assert_equal 0, count(245)
      assert_equal 3, count(246)
    end

    # -- gender / looking_for reciprocal compatibility ------------------------

    test "a shared gender and looking_for code space reports zero divergence" do
      create_fixture!
      insert!(gender: 0, looking_for: 1)
      insert!(gender: 1, looking_for: 0)

      assert_equal 0, count(250)
      assert_equal 0, count(251)
      assert_equal 2, count(252)
      assert_equal 2, count(253)
      assert_equal 2, count(254), "both distinct values appear in both columns"
      assert_equal 0, count(255)
      assert_equal 0, count(256)
      assert_equal 2, count(257)
    end

    test "a wider looking_for vocabulary is reported as divergence, not silently merged" do
      create_fixture!
      insert!(gender: 0, looking_for: 0)
      insert!(gender: 1, looking_for: 1)
      insert!(gender: 2, looking_for: 3) # 3 = an "everyone" code with no gender counterpart
      insert!(gender: nil, looking_for: nil)

      assert_equal 1, count(250), "gender NULL: cannot be a discovery candidate"
      assert_equal 1, count(251), "looking_for NULL: cannot be a discovery viewer"
      assert_equal 3, count(252)
      assert_equal 3, count(253)
      assert_equal 2, count(254)
      assert_equal 1, count(255), "gender code 2 that no viewer can ask for"
      assert_equal 1, count(256), "looking_for code 3 that is not a gender"
      assert_equal 3, count(257)
    end

    test "reciprocal-capable population excludes deleted and banned members" do
      create_fixture!
      insert!(gender: 0, looking_for: 1)
      insert!(gender: 0, looking_for: 1, deleted_at: "2026-01-01")
      insert!(gender: 0, looking_for: 1, banned_at: "2026-01-01")

      assert_equal 1, count(257)
    end

    test "the gender x looking_for cross-tab shows how pairs actually line up" do
      create_fixture!
      5.times { insert!(gender: 0, looking_for: 0) }
      3.times { insert!(gender: 1, looking_for: 1) }
      2.times { insert!(gender: 0, looking_for: 1) }
      insert!(gender: nil, looking_for: nil)

      assert_equal({ "g0/l0" => 5, "g1/l1" => 3, "g0/l1" => 2, "gNULL/lNULL" => 1 }, buckets(258))
    end

    test "the cross-tab applies the same value-safety rules to both columns" do
      create_fixture!(gender_type: "character varying", looking_for_type: "character varying")
      insert!(gender: "woman", looking_for: "man")
      insert!(gender: "identifies as wahala free since 1994", looking_for: "someone kind; ring 080")

      emitted = note(258)

      assert_equal({ "gwoman/lman" => 1, "gOTHER/lOTHER" => 1 }, buckets(258))
      refute_includes emitted, "wahala"
      refute_includes emitted, "080"
    end

    # -- name shape -----------------------------------------------------------

    # -- migration-eligible population and onboarding partition ---------------
    #
    # The population is the importer's own eligibility rule, not one invented
    # for this evidence: Date9ja::Import::IdentityImport#import_one skips
    # `soft_deleted?` and `banned?` records, which UserRecord defines as
    # `deleted_at.present?` / `banned_at.present?`.

    # Eight eligible rows plus two the importer would skip.
    #   onboarded     : same 2, differing 1, indeterminate 1  (4)
    #   not onboarded : same 1, differing 2, indeterminate 1  (4)
    def cohort_fixture!
      create_fixture!
      insert!(gender: 0, looking_for: 0, onboarding_completed_at: "2024-01-01 00:00:00")
      insert!(gender: 0, looking_for: 0, onboarding_completed_at: "2024-01-01 00:00:00")
      insert!(gender: 0, looking_for: 1, onboarding_completed_at: "2024-01-01 00:00:00")
      insert!(gender: 1, looking_for: nil, onboarding_completed_at: "2024-01-01 00:00:00")
      insert!(gender: 1, looking_for: 1)
      insert!(gender: 1, looking_for: 0)
      insert!(gender: 0, looking_for: 1)
      insert!(gender: nil, looking_for: 1)
      # excluded by the importer, and therefore by every measure below
      insert!(gender: 0, looking_for: 0, onboarding_completed_at: "2024-01-01 00:00:00",
              deleted_at: "2024-02-01 00:00:00")
      insert!(gender: 0, looking_for: 0, banned_at: "2024-02-01 00:00:00")
    end

    test "the eligible population applies the importer's own skip rules" do
      cohort_fixture!

      assert_equal 8, count(290), "soft-deleted and banned rows are not migration-eligible"
      assert_equal 8, count(291) + count(295), "onboarding splits the eligible population"
      assert_includes Date9jaCensusSql.measure(290).count_sql, "deleted_at IS NULL"
      assert_includes Date9jaCensusSql.measure(290).count_sql, "banned_at IS NULL"
    end

    test "the eligible cross-tab differs from the all-source cross-tab by exactly the skipped rows" do
      cohort_fixture!

      assert_equal({ "g0/l0" => 4, "g0/l1" => 2, "g1/l0" => 1, "g1/l1" => 1,
                     "g1/lNULL" => 1, "gNULL/l1" => 1 }, buckets(258),
        "258 is the all-source cross-tab and includes the skipped rows")
      assert_equal({ "g0/l0" => 2, "g0/l1" => 2, "g1/l0" => 1, "g1/l1" => 1,
                     "g1/lNULL" => 1, "gNULL/l1" => 1 }, buckets(259),
        "259 is the migration-eligible cross-tab")
      assert_equal 8, count(259)
    end

    test "the onboarding cohorts split the eligible population into disjoint buckets" do
      cohort_fixture!

      assert_equal 4, count(291), "eligible and onboarded"
      assert_equal 2, count(292), "onboarded, looking_for code same as gender code"
      assert_equal 1, count(293), "onboarded, looking_for code differs"
      assert_equal 1, count(294), "onboarded, one side NULL"

      assert_equal 4, count(295), "eligible and not onboarded"
      assert_equal 1, count(296), "not onboarded, same"
      assert_equal 2, count(297), "not onboarded, differs"
      assert_equal 1, count(298), "not onboarded, one side NULL"
    end

    test "the partition proof reconciles both cohorts against the eligible population" do
      cohort_fixture!

      assert_equal "eligible:8 onboarded:4=2+1+1 not_onboarded:4=1+2+1 OK", note(299)
    end

    test "a NULL on either side lands in indeterminate rather than same or differs" do
      create_fixture!
      insert!(gender: nil, looking_for: nil)
      insert!(gender: 0, looking_for: nil)
      insert!(gender: nil, looking_for: 0)

      assert_equal 3, count(295)
      assert_equal 0, count(296), "NULL is not equal to anything"
      assert_equal 0, count(297), "NULL is not unequal to anything either"
      assert_equal 3, count(298)
      assert_equal "eligible:3 onboarded:0=0+0+0 not_onboarded:3=0+0+3 OK", note(299)
    end

    test "the partition proof holds for an empty and for an all-excluded population" do
      create_fixture!
      assert_equal "eligible:0 onboarded:0=0+0+0 not_onboarded:0=0+0+0 OK", note(299)

      insert!(gender: 0, looking_for: 0, deleted_at: "2024-02-01 00:00:00")
      insert!(gender: 1, looking_for: 1, banned_at: "2024-02-01 00:00:00")

      assert_equal 0, count(290)
      assert_equal "eligible:0 onboarded:0=0+0+0 not_onboarded:0=0+0+0 OK", note(299)
    end

    test "the cohort measures never emit a row-level value" do
      cohort_fixture!

      (290..299).each do |ord|
        next unless Date9jaCensusSql.measures_in(200..299).key?(ord)

        _count, text = census(ord)
        next if text.nil?

        refute_match(/[A-Za-z]{4,}@|\+?\d{10,}/, text, "measure #{ord} emitted contact-shaped text")
      end
    end

    test "name census reports token shape and never a name" do
      create_fixture!
      insert!(full_name: "Amara", display_name: "Amara")
      insert!(full_name: "Chidi Okonkwo", display_name: "Chidi")
      insert!(full_name: "  Ngozi   Adaeze  Eze ", display_name: "Ngozi Adaeze Eze")
      insert!(full_name: "   ", display_name: "")
      insert!(full_name: nil, display_name: nil)

      assert_equal({ "null" => 1, "blank" => 1, "1_token" => 1, "2_token" => 1, "3plus_token" => 1 },
                   buckets(260))
      assert_equal({ "null" => 1, "blank" => 1, "1_token" => 2, "2_token" => 0, "3plus_token" => 1 },
                   buckets(261))

      emitted = "#{note(260)} #{note(261)}"
      %w[Amara Chidi Okonkwo Ngozi Adaeze Eze].each do |name|
        refute_includes emitted, name
        refute_includes emitted.downcase, name.downcase
      end
    end

    # -- country --------------------------------------------------------------

    test "country census classifies shape without echoing a location string" do
      create_fixture!
      insert!(country_of_residence: "NG")
      insert!(country_of_residence: "Nigeria")
      insert!(country_of_residence: "United Kingdom")
      insert!(country_of_residence: "12 Marina Street, Lagos")
      insert!(country_of_residence: "  ")
      insert!(country_of_residence: nil)

      shape = buckets(265)

      assert_equal 1, shape.fetch("null")
      assert_equal 1, shape.fetch("blank")
      assert_equal 1, shape.fetch("iso2")
      assert_equal 2, shape.fetch("name_like")
      assert_equal 1, shape.fetch("other")
      assert_equal 4, shape.fetch("distinct")
      refute_includes note(265), "Marina"
    end

    test "country allowlist buckets known countries and folds the rest to OTHER" do
      create_fixture!
      insert!(country_of_residence: "NG")
      insert!(country_of_residence: "nigeria")
      insert!(country_of_residence: "United Kingdom")
      insert!(country_of_residence: "Ruritania")
      insert!(country_of_residence: "12 Marina Street, Lagos")
      insert!(country_of_residence: nil)

      assert_equal({ "nigeria" => 2, "united_kingdom" => 1, "OTHER" => 2, "NULL" => 1 }, buckets(266))
      refute_includes note(266), "Ruritania"
      refute_includes note(266), "Marina"
    end

    # -- publication ----------------------------------------------------------

    test "publication cohorts cross-tab hidden state against onboarding" do
      create_fixture!
      insert!(profile_hidden: false, onboarding_completed_at: "2026-01-01")
      insert!(profile_hidden: false, onboarding_completed_at: nil)
      insert!(profile_hidden: true, onboarding_completed_at: "2026-01-01")
      insert!(profile_hidden: true, onboarding_completed_at: nil)
      insert!(profile_hidden: true, onboarding_completed_at: nil)

      assert_equal({ "visible/onboarded" => 1, "visible/not_onboarded" => 1,
                     "hidden/onboarded" => 1, "hidden/not_onboarded" => 2 }, buckets(270))
    end

    test "completeness score bands include an out-of-range bucket" do
      create_fixture!
      [ nil, -5, 0, 30, 65, 92, 100, 140 ].each { |score| insert!(profile_completeness_score: score) }

      assert_equal({ "NULL" => 1, "OUT_OF_RANGE" => 2, "000" => 1, "001_049" => 1,
                     "050_079" => 1, "080_099" => 1, "100" => 1 }, buckets(271))
    end

    test "candidate publication cohort excludes every non-live lifecycle state" do
      create_fixture!
      insert!(profile_hidden: false, onboarding_completed_at: "2026-01-01")
      insert!(profile_hidden: true, onboarding_completed_at: "2026-01-01")
      insert!(profile_hidden: false, onboarding_completed_at: nil)
      insert!(profile_hidden: false, onboarding_completed_at: "2026-01-01", deleted_at: "2026-02-01")
      insert!(profile_hidden: false, onboarding_completed_at: "2026-01-01", banned_at: "2026-02-01")
      insert!(profile_hidden: false, onboarding_completed_at: "2026-01-01", suspended_at: "2026-02-01")

      assert_equal 1, count(272)
    end

    # -- arrays ---------------------------------------------------------------

    test "array census reports shape and vocabulary form without element content" do
      create_fixture!
      insert!(interests: %w[afrobeats cooking travel])
      insert!(interests: %w[afrobeats])
      insert!(interests: [])
      insert!(interests: nil)
      insert!(interests: [ "I love long walks on the beach and jollof rice", "Cooking!" ])

      shape = buckets(280)

      assert_equal 1, shape.fetch("null")
      assert_equal 1, shape.fetch("empty")
      assert_equal 3, shape.fetch("nonempty")
      assert_equal 3, shape.fetch("max_card")
      assert_equal 5, shape.fetch("distinct_elems")
      # afrobeats / cooking / travel are labels; the long sentence and "Cooking!"
      # both carry sentence punctuation or excess length.
      assert_equal 3, shape.fetch("label_shaped_elems")
      assert_equal 2, shape.fetch("sentence_shaped_elems")
      assert_equal 1, shape.fetch("long_elems")

      emitted = note(280)

      refute_includes emitted, "afrobeats"
      refute_includes emitted, "jollof"
    end

    test "every array column is measured with the same shape emitter" do
      create_fixture!
      insert!(relationship_values: %w[faith family], dealbreakers: %w[smoking],
              languages_spoken: %w[english igbo], preferred_countries: %w[NG GB],
              relocation_preferences: [])

      assert_equal 2, buckets(281).fetch("distinct_elems")
      assert_equal 1, buckets(282).fetch("distinct_elems")
      assert_equal 2, buckets(283).fetch("distinct_elems")
      assert_equal 2, buckets(284).fetch("distinct_elems")
      assert_equal 2, buckets(284).fetch("label_shaped_elems"), "uppercase ISO codes are still labels"
      assert_equal 1, buckets(285).fetch("empty")
    end

    test "array census is safe when every row is NULL or empty" do
      create_fixture!
      insert!(interests: nil)
      insert!(interests: [])

      assert_equal({ "null" => 1, "empty" => 1, "nonempty" => 0, "max_card" => 0,
                     "distinct_elems" => 0, "label_shaped_elems" => 0,
                     "sentence_shaped_elems" => 0, "long_elems" => 0 },
                   buckets(280))
    end

    # -- whole-section privacy sweep ------------------------------------------

    test "no Pass-1 measure echoes free-text content from any measured column" do
      create_fixture!(gender_type: "character varying", looking_for_type: "character varying")

      # Every value here is invented. Each is shaped like something that must
      # never reach the census output: a real name, an address, a contact
      # detail, a sentence of user-generated text. Words are chosen not to
      # collide with any structural label the census emits, so the only
      # permitted exemption below is a column NAME.
      sentinels = {
        full_name: "Chidinma Adaeze Okafor",
        display_name: "chidi.okafor+signup@example.com",
        country_of_residence: "12b Marina Crescent, Yaba Quarter",
        gender: "identifies as wahala free since 1994",
        looking_for: "someone kind; ring +2348012345678",
        body_type: "5ft9 slender <script>alert(1)</script>",
        interests: [ "adores evening strolls, jollof rice", "WhatsApp me on 08012345678" ],
        relationship_values: [ "faith matters: Redeemed Christian Assembly" ],
        dealbreakers: [ "no smokers, ask my sister Ngozi" ],
        languages_spoken: [ "Igbo (Anambra dialect)" ],
        preferred_countries: [ "Ruritania & Elbonia" ],
        relocation_preferences: [ "moves if my aunt Adaeze relocates" ]
      }
      insert!(**sentinels)
      insert!(gender: "woman", looking_for: "man")

      needles = sentinels.values.flatten.flat_map do |value|
        [ value, value.downcase, *value.scan(/[A-Za-z]{4,}/) ]
      end.uniq

      Date9jaCensusSql.measures_in(200..299).each_value do |measure|
        source_count, note = census(measure.ord)
        emitted = "#{source_count} #{note}".downcase

        needles.each do |needle|
          # Column NAMES are schema metadata and legitimately appear in ord
          # 200-202; only column VALUE content is forbidden anywhere.
          next if @fixture_columns.any? { |column| column.include?(needle.downcase) }

          refute_includes emitted, needle.downcase,
            "measure #{measure.ord} (#{measure.name}) leaked #{needle.inspect}"
        end
      end
    end

    test "free-text values in a bounded column fold to OTHER rather than being emitted" do
      create_fixture!(gender_type: "character varying")
      insert!(gender: "identifies as wahala free since 1994")
      insert!(gender: "woman")

      assert_equal({ "OTHER" => 1, "woman" => 1 }, buckets(210))
    end

    test "lifecycle cross-tab keeps member pause and moderator restriction independent" do
      create_fixture!
      insert!(profile_hidden: true)
      insert!(discovery_restricted_at: Time.current, discovery_restriction_reason: "spam")
      insert!(profile_hidden: true, discovery_restricted_at: Time.current, suspended_at: Time.current)

      states = buckets(38)
      assert_equal 1, states.fetch("hidden_1/restricted_0/suspended_0/banned_0/deleted_0")
      assert_equal 1, states.fetch("hidden_0/restricted_1/suspended_0/banned_0/deleted_0")
      assert_equal 1, states.fetch("hidden_1/restricted_1/suspended_1/banned_0/deleted_0")
    end

    test "unknown enum values are surfaced without echoing their values" do
      create_fixture!
      insert!(gender: 99, looking_for: 0, relationship_intention: 77)
      insert!(gender: 0, looking_for: 1)

      assert_equal 1, count(314)
      assert_equal "gender:1 looking_for:0 relationship_intention:1 commitment_timeline:0 lifestyle:0 family:0",
        note(314)
      refute_includes note(314), "99"
      refute_includes note(314), "77"
    end

    test "array validation surfaces null elements without emitting array content" do
      create_fixture!
      insert!(languages_spoken: [ "english", nil ])

      assert_equal 1, count(315)
      refute_includes note(315).to_s, "english"
    end

    test "authoritative snapshot marks HEAD-only identity columns as absent rather than empty" do
      create_fixture!

      assert_equal 0, count(180)
      assert_includes note(180), "HEAD-only"
    end

    # -- execution-model guarantees -------------------------------------------

    test "a READ ONLY transaction rejects a write, which is what the census runs inside" do
      create_fixture!

      assert_sql_error(/read-only transaction/i) do
        connection.execute("SET TRANSACTION READ ONLY")
        connection.execute("INSERT INTO users (id) VALUES (9999)")
      end
    end

    test "the shared schema guard fails closed against a database that is not the Date9ja source" do
      assert_sql_error(/SCHEMA DRIFT/) do
        connection.execute(File.read(Rails.root.join("scripts/date9ja/schema_signature.sql")))
      end
    end
  end
end
