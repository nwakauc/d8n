module Matching
  module Strategies
    # Deterministic, symmetric DateZA pair compatibility. Eligibility remains a
    # separate gate; this class never turns an ineligible pair into a score.
    #
    # Only the typed DateZA v1 catalogue is read. Trust, verification, activity,
    # likes, matches, popularity and exact location are intentionally absent.
    class DatezaV1
      KEY = "dateza_v1"
      MINIMUM_COMPARABLE_WEIGHT = 35
      MAX_REASONS = 5
      DAILY_SELECTION_POOL_LIMIT = 500

      WEIGHTS = {
        relationship_intent: 20,
        has_children: 10,
        wants_children: 20,
        smoking: 10,
        drinking: 5,
        religion_importance: 8,
        social_style: 7,
        meeting_pace: 7,
        interests: 4,
        languages: 3,
        communication_style: 2,
        planning_style: 2,
        travel_frequency: 1,
        diet: 1
      }.freeze

      EXPLANATION_CODES = %w[
        shared_long_term_intent compatible_relationship_goals relationship_goal_mismatch
        compatible_family_plans family_plan_mismatch shared_no_smoking smoking_lifestyle_mismatch
        compatible_drinking_style similar_faith_importance similar_social_style
        compatible_meeting_pace shared_interests shared_languages
        compatible_communication_style compatible_planning_style similar_travel_style compatible_diet
      ].freeze

      RELATIONSHIP_FIT = {
        %w[long_term_relationship marriage].sort => 0.85,
        %w[long_term_relationship open_to_dating].sort => 0.65,
        %w[long_term_relationship friendship].sort => 0.15,
        %w[long_term_relationship still_figuring_it_out].sort => 0.45,
        %w[marriage open_to_dating].sort => 0.45,
        %w[marriage friendship].sort => 0.1,
        %w[marriage still_figuring_it_out].sort => 0.35,
        %w[open_to_dating friendship].sort => 0.5,
        %w[open_to_dating still_figuring_it_out].sort => 0.65,
        %w[friendship still_figuring_it_out].sort => 0.55
      }.freeze
      WANTS_CHILDREN_FIT = {
        %w[yes maybe].sort => 0.7,
        %w[yes no].sort => 0.0,
        %w[yes open_to_partner_with_children].sort => 0.6,
        %w[maybe no].sort => 0.4,
        %w[maybe open_to_partner_with_children].sort => 0.75,
        %w[no open_to_partner_with_children].sort => 0.8
      }.freeze

      Result = Data.define(:score, :confidence, :confidence_level, :version, :reasons) do
        def public_payload
          return if score.nil?

          { score:, confidence:, confidence_level:, version:, reasons: }
        end
      end

      class IneligiblePair < StandardError; end

      class << self
        def key = KEY

        # Stable daily selection ranks a bounded, deterministic eligible pool.
        # The allocation engine owns persistence and safety filtering; this
        # strategy owns only DateZA's pair compatibility and tie-breaking.
        def rank_daily_selection(scope:, viewer:, eligibility_policy:, limit:)
          candidates = scope.reorder(created_at: :desc, public_id: :desc)
            .includes(profile_option_selections: [ :profile_option, :profile_option_group ])
            .limit(DAILY_SELECTION_POOL_LIMIT)
            .to_a
          scorer = new(brand: viewer.brand, viewer:, eligibility_policy:)

          candidates.map do |candidate|
            compatibility = scorer.for_eligible_pair(candidate:)
            { profile: candidate, ranking_payload: { compatibility: compatibility.public_payload } }
          end.sort_by do |candidate|
            compatibility = candidate.dig(:ranking_payload, :compatibility)
            [
              compatibility&.fetch(:score) || -1,
              compatibility&.fetch(:confidence) || 0.0,
              candidate.fetch(:profile).created_at.to_f,
              candidate.fetch(:profile).public_id
            ]
          end.reverse.first(limit)
        end

        def call(brand:, viewer:, candidate:, eligibility_policy: nil)
          new(brand:, viewer:, eligibility_policy:).call(candidate:)
        end

        # Search/Discovery callers may use this only after the shared eligibility
        # scope selected the candidate. It avoids repeating one eligibility query
        # per card while retaining brand/pair validation here.
        def for_eligible_pair(brand:, viewer:, candidate:)
          new(brand:, viewer:).for_eligible_pair(candidate:)
        end

        # Profile detail has already passed the shared visibility/safety scope but
        # deliberately does not reapply ranking preferences. Calculate the same
        # presentation payload without changing eligibility or matching semantics.
        def for_visible_pair(brand:, viewer:, candidate:)
          new(brand:, viewer:).for_visible_pair(candidate:)
        end
      end

      def initialize(brand:, viewer:, eligibility_policy: nil)
        @brand = brand
        @viewer = viewer
        @eligibility_policy = eligibility_policy
        @viewer_values = values_for(viewer)
      end

      def call(candidate:)
        assert_pair_scope!(candidate)
        assert_eligible!(candidate)
        calculate(candidate)
      end

      def for_eligible_pair(candidate:)
        assert_pair_scope!(candidate)
        calculate(candidate)
      end

      def for_visible_pair(candidate:)
        assert_pair_scope!(candidate)
        calculate(candidate)
      end

      private

      attr_reader :brand, :viewer, :viewer_values, :eligibility_policy

      def assert_pair_scope!(candidate)
        valid = brand.slug == "dateza" && viewer.brand_id == brand.id &&
          candidate.brand_id == brand.id && candidate.id != viewer.id
        raise IneligiblePair, "pair is not eligible" unless valid
      end

      def assert_eligible!(candidate)
        current_viewer = ProfileParticipant.discoverable!(user: viewer.user, brand:)
        policy = eligibility_policy || StrategyRegistry.eligibility_policy_for(brand:)
        eligible = current_viewer.id == viewer.id && EligibilityScope.call(
          brand:, viewer:, policy:
        ).where(id: candidate.id).exists?
        raise IneligiblePair, "pair is not eligible" unless eligible
      rescue InteractionError
        raise IneligiblePair, "pair is not eligible"
      end

      def calculate(candidate)
        candidate_values = values_for(candidate)
        comparisons = compare(viewer_values, candidate_values)
        available_weight = comparisons.sum { |comparison| comparison.fetch(:weight) }
        confidence = (available_weight.fdiv(WEIGHTS.values.sum)).round(2)
        score = if available_weight >= MINIMUM_COMPARABLE_WEIGHT
          earned = comparisons.sum { |comparison| comparison.fetch(:weight) * comparison.fetch(:fit) }
          (earned.fdiv(available_weight) * 100).round
        end
        reasons = score ? comparisons.filter_map { |comparison| comparison[:reason] }.first(MAX_REASONS) : []

        Result.new(score:, confidence:, confidence_level: confidence_level(confidence), version: KEY, reasons:)
      end

      def compare(left, right)
        [
          matrix_comparison(:relationship_intent, left, right, RELATIONSHIP_FIT) { |fit, same, value|
            if same && %w[long_term_relationship marriage].include?(value)
              "shared_long_term_intent"
            elsif fit >= 0.55
              "compatible_relationship_goals"
            elsif fit <= 0.35
              "relationship_goal_mismatch"
            end
          },
          exact_comparison(:has_children, left, right, mismatch_fit: 0.5),
          matrix_comparison(:wants_children, left, right, WANTS_CHILDREN_FIT) do |fit|
            fit >= 0.6 ? "compatible_family_plans" : "family_plan_mismatch"
          end,
          ordered_comparison(:smoking, left, right, %w[never occasionally regularly], adjacent_fit: 0.5) do |fit, same, value|
            if same && value == "never"
              "shared_no_smoking"
            elsif fit < 0.5
              "smoking_lifestyle_mismatch"
            end
          end,
          ordered_comparison(:drinking, left, right, %w[never occasionally regularly], adjacent_fit: 0.6) do |fit|
            "compatible_drinking_style" if fit >= 0.6
          end,
          ordered_comparison(
            :religion_importance, left, right, %w[not_important somewhat_important very_important], adjacent_fit: 0.6,
            end_fit: 0.1
          ) { |fit| "similar_faith_importance" if fit >= 0.6 },
          social_style_comparison(left, right),
          meeting_pace_comparison(left, right),
          overlap_comparison(:interests, left, right, "shared_interests"),
          overlap_comparison(:languages, left, right, "shared_languages", overlap_coefficient: true),
          exact_comparison(
            :communication_style, left, right, mismatch_fit: 0.4, reason: "compatible_communication_style"
          ),
          exact_comparison(:planning_style, left, right, mismatch_fit: 0.4, reason: "compatible_planning_style"),
          exact_comparison(:travel_frequency, left, right, mismatch_fit: 0.4, reason: "similar_travel_style"),
          exact_comparison(:diet, left, right, mismatch_fit: 0.4, reason: "compatible_diet")
        ].compact
      end

      def matrix_comparison(key, left, right, matrix)
        pair = comparable_pair(key, left, right)
        return unless pair

        same = pair.first == pair.last
        fit = same ? 1.0 : matrix.fetch(pair.sort, 0.0)
        comparison(key, fit, yield(fit, same, pair.first))
      end

      def ordered_comparison(key, left, right, order, adjacent_fit:, end_fit: 0.0)
        pair = comparable_pair(key, left, right)
        return unless pair

        distance = (order.index(pair.first) - order.index(pair.last)).abs
        fit = distance.zero? ? 1.0 : (distance == 1 ? adjacent_fit : end_fit)
        comparison(key, fit, yield(fit, distance.zero?, pair.first))
      end

      def exact_comparison(key, left, right, mismatch_fit:, reason: nil)
        pair = comparable_pair(key, left, right)
        return unless pair

        same = pair.first == pair.last
        explanation = reason if same
        comparison(key, same ? 1.0 : mismatch_fit, explanation)
      end

      def social_style_comparison(left, right)
        pair = comparable_pair(:social_style, left, right)
        return unless pair

        fit = if pair.first == pair.last
          1.0
        elsif pair.include?("depends_on_the_vibe")
          0.7
        elsif pair.include?("ambivert")
          0.7
        else
          0.25
        end
        reason = "similar_social_style" if fit >= 0.7
        comparison(:social_style, fit, reason)
      end

      def meeting_pace_comparison(left, right)
        pair = comparable_pair(:meeting_pace, left, right)
        return unless pair

        order = { "chat_first" => 0, "video_call_first" => 0, "few_days" => 1, "meet_soon" => 2 }
        fit = if pair.first == pair.last
          1.0
        elsif pair.include?("go_with_the_flow")
          0.75
        else
          distance = (order.fetch(pair.first) - order.fetch(pair.last)).abs
          distance <= 1 ? 0.7 : 0.3
        end
        reason = "compatible_meeting_pace" if fit >= 0.7
        comparison(:meeting_pace, fit, reason)
      end

      def overlap_comparison(key, left, right, reason, overlap_coefficient: false)
        pair = comparable_pair(key, left, right)
        return unless pair

        intersection = (pair.first & pair.last).size
        denominator = if overlap_coefficient
          [ pair.first.size, pair.last.size ].min
        else
          (pair.first | pair.last).size
        end
        fit = intersection.fdiv(denominator)
        explanation = reason if intersection.positive?
        comparison(key, fit, explanation)
      end

      def comparable_pair(key, left, right)
        values = [ left[key], right[key] ]
        return if values.any?(&:blank?) || values.include?("prefer_not_to_say")

        values
      end

      def comparison(key, fit, reason)
        { weight: WEIGHTS.fetch(key), fit:, reason: }
      end

      def values_for(profile)
        selections = option_selections_for(profile).group_by { |selection| selection.profile_option_group.key }
        option_value = lambda do |key|
          values = selections.fetch(key.to_s, []).map { |selection| selection.profile_option.code }.sort
          key == :interests ? values : values.first
        end

        WEIGHTS.keys.to_h do |key|
          value = case key
          when :smoking, :drinking then profile.public_send(key)
          when :languages then Profiles::Languages.serialize(profile.languages).pluck(:code).sort
          else option_value.call(key)
          end
          [ key, value ]
        end
      end

      def option_selections_for(profile)
        association = profile.association(:profile_option_selections)
        records = if association.loaded?
          association.target
        else
          profile.profile_option_selections.includes(:profile_option, :profile_option_group).to_a
        end
        records.select do |selection|
          selection.deleted_at.nil? && selection.profile_option.status_active? &&
            selection.profile_option_group.status_active?
        end
      end

      def confidence_level(confidence)
        return "high" if confidence >= 0.75
        return "medium" if confidence >= 0.45

        "low"
      end
    end
  end
end
