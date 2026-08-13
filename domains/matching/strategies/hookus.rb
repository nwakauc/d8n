module Matching
  module Strategies
    class Hookus
      KEY = "hookus_v1"
      LOCATION_MAX_AGE = 24.hours
      DIMENSION_COUNT = 4
      REASONS = {
        matching_shared_intent: "shared_intent",
        matching_similar_vibe: "similar_vibe",
        matching_mutual_age_fit: "mutual_age_fit"
      }.freeze

      OPTION_STATS_SQL = <<~SQL.squish.freeze
        COUNT(*) FILTER (WHERE profile_option_groups.key = 'intents') AS intent_count,
        COUNT(hookus_viewer_options.profile_option_id)
          FILTER (WHERE profile_option_groups.key = 'intents') AS shared_intent_count,
        COUNT(*) FILTER (WHERE profile_option_groups.key = 'vibes') AS vibe_count,
        COUNT(hookus_viewer_options.profile_option_id)
          FILTER (WHERE profile_option_groups.key = 'vibes') AS shared_vibe_count
      SQL
      OPTION_JOIN_SQL = <<~SQL.squish.freeze
        LEFT JOIN hookus_viewer_options
          ON hookus_viewer_options.profile_option_id = profile_option_selections.profile_option_id
      SQL
      STATS_JOIN_SQL = <<~SQL.squish.freeze
        LEFT JOIN hookus_candidate_option_stats
          ON hookus_candidate_option_stats.profile_id = profiles.id
      SQL
      INTENT_AVAILABLE_SQL = <<~SQL.squish.freeze
        hookus_viewer_option_counts.intent_count > 0 AND
          COALESCE(hookus_candidate_option_stats.intent_count, 0) > 0
      SQL
      VIBE_AVAILABLE_SQL = <<~SQL.squish.freeze
        hookus_viewer_option_counts.vibe_count > 0 AND
          COALESCE(hookus_candidate_option_stats.vibe_count, 0) > 0
      SQL
      INTENT_SCORE_SQL = <<~SQL.squish.freeze
        CASE WHEN #{INTENT_AVAILABLE_SQL} THEN ROUND(
          40.0 * COALESCE(hookus_candidate_option_stats.shared_intent_count, 0) /
          LEAST(hookus_viewer_option_counts.intent_count, hookus_candidate_option_stats.intent_count)
        ) ELSE 0 END
      SQL
      VIBE_SCORE_SQL = <<~SQL.squish.freeze
        CASE WHEN #{VIBE_AVAILABLE_SQL} THEN ROUND(
          25.0 * COALESCE(hookus_candidate_option_stats.shared_vibe_count, 0) /
          LEAST(hookus_viewer_option_counts.vibe_count, hookus_candidate_option_stats.vibe_count)
        ) ELSE 0 END
      SQL

      def self.key
        KEY
      end

      def self.location_max_age
        LOCATION_MAX_AGE
      end

      def self.production_ready?
        true
      end

      def self.rank(scope:, viewer:)
        viewer_has_location = fresh_location?(viewer:)
        viewer_uses_distance = viewer.profile_preference.max_distance_km.present?
        expressions = score_expressions(viewer_has_location:, viewer_uses_distance:)
        scope = with_option_scores(scope:, viewer:)

        scope.select(
          "profiles.*",
          "#{expressions.fetch(:score)} AS matching_score",
          "#{expressions.fetch(:confidence)} AS matching_confidence",
          "(COALESCE(hookus_candidate_option_stats.shared_intent_count, 0) > 0) AS matching_shared_intent",
          "(COALESCE(hookus_candidate_option_stats.shared_vibe_count, 0) >= 2) AS matching_similar_vibe",
          "TRUE AS matching_mutual_age_fit"
        ).order(Arel.sql("matching_score DESC, profiles.created_at DESC, profiles.public_id DESC"))
      end

      def self.cursor_payload(profile:)
        { score: Integer(profile[:matching_score]) }
      end

      def self.compatibility(profile:)
        {
          score: Integer(profile[:matching_score]),
          confidence: profile[:matching_confidence].to_f,
          reasons: REASONS.filter_map { |attribute, code| code if profile[attribute] }
        }
      end

      def self.apply_cursor(scope:, payload:)
        score = Integer(payload.fetch(:score))
        raise Cursor::Invalid, "cursor is invalid" unless score.between?(0, 100)

        created_at = Time.iso8601(payload.fetch(:created_at))
        public_id = payload.fetch(:profile).to_s
        raise Cursor::Invalid, "cursor is invalid" unless public_id.match?(Profile::PUBLIC_ID_FORMAT)

        Profile.from(scope, :profiles).where(
          "profiles.matching_score < :score OR " \
            "(profiles.matching_score = :score AND " \
            "(profiles.created_at < :created_at OR " \
            "(profiles.created_at = :created_at AND profiles.public_id < :public_id)))",
          score:, created_at:, public_id:
        ).reorder(Arel.sql("profiles.matching_score DESC, profiles.created_at DESC, profiles.public_id DESC"))
      rescue ArgumentError, KeyError, TypeError
        raise Cursor::Invalid, "cursor is invalid"
      end

      def self.with_option_scores(scope:, viewer:)
        selections = public_matching_selections(brand: viewer.brand)
        viewer_options = selections.where(profile_id: viewer.id)
          .select("profile_option_selections.profile_option_id")
        viewer_counts = selections.where(profile_id: viewer.id)
          .select(<<~SQL.squish)
            COUNT(*) FILTER (WHERE profile_option_groups.key = 'intents') AS intent_count,
            COUNT(*) FILTER (WHERE profile_option_groups.key = 'vibes') AS vibe_count
          SQL
        candidate_stats = selections
          .joins(OPTION_JOIN_SQL)
          .group("profile_option_selections.profile_id")
          .select("profile_option_selections.profile_id", OPTION_STATS_SQL)

        scope.with(
          hookus_viewer_options: viewer_options,
          hookus_viewer_option_counts: viewer_counts,
          hookus_candidate_option_stats: candidate_stats
        ).joins("CROSS JOIN hookus_viewer_option_counts").joins(STATS_JOIN_SQL)
      end
      private_class_method :with_option_scores

      def self.public_matching_selections(brand:)
        ProfileOptionSelection.kept
          .where(brand:)
          .joins(:profile_option_group, :profile_option)
          .merge(ProfileOptionGroup.kept.status_active.visibility_public_profile)
          .merge(ProfileOption.kept.status_active)
          .where(profile_option_groups: { key: %w[intents vibes] })
      end
      private_class_method :public_matching_selections

      def self.score_expressions(viewer_has_location:, viewer_uses_distance:)
        distance = if viewer_has_location
          available_distance_expressions(viewer_uses_distance:)
        else
          unavailable_distance_expressions
        end
        possible = "15 + CASE WHEN #{INTENT_AVAILABLE_SQL} THEN 40 ELSE 0 END + " \
          "CASE WHEN #{VIBE_AVAILABLE_SQL} THEN 25 ELSE 0 END + #{distance.fetch(:weight)}"
        earned = "15 + #{INTENT_SCORE_SQL} + #{VIBE_SCORE_SQL} + #{distance.fetch(:score)}"
        comparable = "1 + CASE WHEN #{INTENT_AVAILABLE_SQL} THEN 1 ELSE 0 END + " \
          "CASE WHEN #{VIBE_AVAILABLE_SQL} THEN 1 ELSE 0 END + #{distance.fetch(:available_count)}"

        {
          score: "ROUND((#{earned}) * 100.0 / (#{possible}))::integer",
          confidence: "ROUND((#{comparable})::numeric / #{DIMENSION_COUNT}, 2)"
        }
      end
      private_class_method :score_expressions

      def self.fresh_location?(viewer:)
        viewer.profile_locations.kept.where(captured_at: LOCATION_MAX_AGE.ago..).exists?
      end
      private_class_method :fresh_location?

      def self.available_distance_expressions(viewer_uses_distance:)
        distance = EligibilityScope::DISTANCE_SQL
        requested = viewer_uses_distance ? "TRUE" : "profile_preferences.max_distance_km IS NOT NULL"
        available = "candidate_locations.id IS NOT NULL AND (#{requested})"
        score = <<~SQL.squish
          CASE WHEN #{available} THEN CASE
            WHEN #{distance} <= 5 THEN 10
            WHEN #{distance} <= 20 THEN 6
            WHEN #{distance} <= 50 THEN 3
            ELSE 0 END ELSE 0 END
        SQL

        {
          weight: "CASE WHEN #{available} THEN 10 ELSE 0 END",
          score:,
          available_count: "CASE WHEN #{available} THEN 1 ELSE 0 END"
        }
      end
      private_class_method :available_distance_expressions

      def self.unavailable_distance_expressions
        { weight: "0", score: "0", available_count: "0" }
      end
      private_class_method :unavailable_distance_expressions
    end
  end
end
