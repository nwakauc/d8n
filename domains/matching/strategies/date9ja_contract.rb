module Matching
  module Strategies
    # Deterministic, symmetric Date9ja pair compatibility. Shared eligibility
    # remains the safety/tenant gate; this strategy ranks only eligible pairs.
    # Hemoglobin genotype is a critical check outside the weighted score.
    class Date9jaContract
      KEY = "date9ja_v1"
      MINIMUM_COMPARABLE_WEIGHT = 44
      MINIMUM_COMPARABLE_DIMENSIONS = 3
      MAX_REASONS = 5
      DAILY_SELECTION_POOL_LIMIT = 500

      WEIGHTS = {
        religion: 30, tribe: 20, relocation: 20, relationship_intent: 10,
        age_range: 10, commitment_timeline: 5, wants_children: 5,
        faith_practice: 8, money_providing: 8, conflict: 8
      }.freeze

      EXPLANATION_CODES = %w[
        aligned_faith_outlook culturally_compatible compatible_settlement_plans
        aligned_relationship_goals mutual_age_fit compatible_commitment_timing
        aligned_family_plans compatible_money_expectations compatible_conflict_styles
      ].freeze

      KNOWN_GENOTYPES = %w[aa as ss ac sc cc].freeze
      UNASSESSED_GENOTYPES = %w[not_tested prefer_not_to_say].freeze
      # Alleles are canonicalized alphabetically below, so HbSC is represented
      # internally as `cs` even though the profile answer is stored as `sc`.
      SICKLE_CELL_DISEASE_OUTCOMES = %w[ss cs].freeze
      OTHER_HEMOGLOBIN_DISEASE_OUTCOMES = %w[cc].freeze
      TIMELINE_ORDER = %w[asap within_1_year one_to_two_years two_to_three_years not_sure].freeze
      FAITH_ORDER = %w[central_daily practice_regularly practice_flexibly not_a_factor].freeze
      CONFLICT_ORDER = %w[talk_now cool_off_first trusted_mediator avoid_until_passes].freeze
      MONEY_FIT = {
        %w[both_one_purse joint_and_personal].sort => 0.5,
        %w[both_one_purse earner_carries_more].sort => 0.5,
        %w[joint_and_personal split_bills].sort => 0.5,
        %w[joint_and_personal earner_carries_more].sort => 0.5,
        %w[split_bills earner_carries_more].sort => 0.5
      }.freeze

      Result = Data.define(:score, :confidence, :confidence_level, :version, :reasons, :critical_checks) do
        def public_payload
          { score:, confidence:, confidence_level:, version:, reasons:, critical_checks: }
        end

        def blocking_inherited_risk?
          %w[elevated_sickle_cell_risk other_hemoglobin_risk].include?(
            critical_checks.dig(:hemoglobin_genotype, :status)
          )
        end
      end

      class IneligiblePair < StandardError; end

      class << self
        def key = KEY
        def production_ready? = true

        # Explore remains newest-first. Its bounded page is pair-scored after
        # loading, avoiding an unbounded Ruby sort of the tenant population.
        def rank(scope:, viewer:, eligibility_policy:)
          scope.select("profiles.*").order("profiles.created_at DESC", "profiles.public_id DESC")
        end

        def cursor_payload(profile:) = {}

        def apply_cursor(scope:, payload:)
          created_at = Time.iso8601(payload.fetch(:created_at))
          public_id = payload.fetch(:profile).to_s
          raise Cursor::Invalid, "cursor is invalid" unless public_id.match?(Profile::PUBLIC_ID_FORMAT)

          scope.where(
            "profiles.created_at < ? OR (profiles.created_at = ? AND profiles.public_id < ?)",
            created_at, created_at, public_id
          )
        rescue ArgumentError, KeyError, TypeError
          raise Cursor::Invalid, "cursor is invalid"
        end

        # Required by the shared feed contract. Pair-aware callers supply the
        # actual payload; absence means not calculated, never zero compatibility.
        def compatibility(profile:)
          profile.has_attribute?(:matching_score) ? profile[:matching_score] : nil
        end

        def rank_daily_selection(scope:, viewer:, eligibility_policy:, limit:)
          candidates = scope.reorder(created_at: :desc, public_id: :desc)
            .includes(:profile_preference, profile_option_selections: [ :profile_option, :profile_option_group ])
            .limit(DAILY_SELECTION_POOL_LIMIT).to_a
          scorer = new(brand: viewer.brand, viewer:, eligibility_policy:)
          ranked = candidates.map do |candidate|
            { profile: candidate, compatibility: scorer.for_eligible_pair(candidate:) }
          end

          # Unknown/not-tested passes through. A calculable inherited-disease
          # outcome is withheld from curated marriage-first introductions.
          ranked.reject! { |entry| entry.fetch(:compatibility).blocking_inherited_risk? }
          ranked.sort_by! do |entry|
            result = entry.fetch(:compatibility)
            [ result.score || -1, result.confidence, entry.fetch(:profile).created_at.to_f,
              entry.fetch(:profile).public_id ]
          end
          ranked.reverse.first(limit).map do |entry|
            { profile: entry.fetch(:profile), ranking_payload: { compatibility: entry.fetch(:compatibility).public_payload } }
          end
        end

        # A genotype answer can become available after today's allocation was
        # frozen. Recalculate at delivery so `not_assessed` stops passing as
        # soon as both members have a supported answer.
        def refresh_daily_candidate(brand:, viewer:, candidate:, eligibility_policy:)
          result = new(brand:, viewer:, eligibility_policy:).for_eligible_pair(candidate:)
          return if result.blocking_inherited_risk?

          { compatibility: result.public_payload }
        end

        def call(brand:, viewer:, candidate:, eligibility_policy: nil)
          new(brand:, viewer:, eligibility_policy:).call(candidate:)
        end

        def for_eligible_pair(brand:, viewer:, candidate:)
          new(brand:, viewer:).for_eligible_pair(candidate:)
        end

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
        valid = brand.slug == "date9ja" && viewer.brand_id == brand.id &&
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
        score = if available_weight >= MINIMUM_COMPARABLE_WEIGHT &&
            comparisons.size >= MINIMUM_COMPARABLE_DIMENSIONS
          earned = comparisons.sum { |comparison| comparison.fetch(:weight) * comparison.fetch(:fit) }
          (earned.fdiv(available_weight) * 100).round
        end
        reasons = score ? comparisons.filter_map { |comparison| comparison[:reason] }.first(MAX_REASONS) : []

        Result.new(
          score:, confidence:, confidence_level: confidence_level(confidence), version: KEY, reasons:,
          critical_checks: { hemoglobin_genotype: genotype_check(viewer_values[:genotype], candidate_values[:genotype]) }
        )
      end

      def compare(left, right)
        [
          exact_comparison(:religion, left, right, reason: "aligned_faith_outlook"),
          tribe_comparison(left, right), relocation_comparison(left, right),
          exact_comparison(:relationship_intent, left, right, reason: "aligned_relationship_goals"),
          age_comparison(left, right),
          ordered_comparison(:commitment_timeline, left, right, TIMELINE_ORDER, adjacent_fit: 0.4,
            reason: "compatible_commitment_timing"),
          children_comparison(left, right),
          ordered_comparison(:faith_practice, left, right, FAITH_ORDER, adjacent_fit: 0.5,
            reason: "aligned_faith_outlook"),
          matrix_comparison(:money_providing, left, right, MONEY_FIT, reason: "compatible_money_expectations"),
          ordered_comparison(:conflict, left, right, CONFLICT_ORDER, adjacent_fit: 0.5,
            reason: "compatible_conflict_styles")
        ].compact
      end

      def exact_comparison(key, left, right, reason:)
        pair = comparable_pair(key, left, right)
        return unless pair

        same = pair.first == pair.last
        comparison(key, same ? 1.0 : 0.0, same ? reason : nil)
      end

      def tribe_comparison(left, right)
        pair = comparable_pair(:tribe, left, right)
        return unless pair

        fit = if pair.first == pair.last
          1.0
        elsif left[:intertribal_marriage_openness] == "open" &&
            right[:intertribal_marriage_openness] == "open"
          0.75
        else
          0.0
        end
        comparison(:tribe, fit, fit >= 0.75 ? "culturally_compatible" : nil)
      end

      def relocation_comparison(left, right)
        countries = [ left[:country_code], right[:country_code] ]
        return if countries.any?(&:blank?)

        left_open = relocation_matches?(left, countries.last)
        right_open = relocation_matches?(right, countries.first)
        fit = if countries.first == countries.last || (left_open && right_open)
          1.0
        elsif left_open || right_open
          0.5
        else
          0.0
        end
        comparison(:relocation, fit, fit == 1.0 ? "compatible_settlement_plans" : nil)
      end

      def relocation_matches?(values, country_code)
        return false unless values[:willing_to_relocate]

        values[:relocation_preferences].any? do |destination|
          Date9ja::Import::CountryMapping.call(destination).country_code == country_code
        end
      end

      def age_comparison(left, right)
        preferences = [ left[:min_age], left[:max_age], right[:min_age], right[:max_age] ]
        return if preferences.all?(&:blank?)

        left_fits = age_within?(left[:age], right[:min_age], right[:max_age])
        right_fits = age_within?(right[:age], left[:min_age], left[:max_age])
        fit = left_fits && right_fits ? 1.0 : (left_fits || right_fits ? 0.5 : 0.0)
        comparison(:age_range, fit, fit == 1.0 ? "mutual_age_fit" : nil)
      end

      def age_within?(age, minimum, maximum)
        return true if minimum.blank? && maximum.blank?
        return false if age.blank?

        (minimum.blank? || age >= minimum) && (maximum.blank? || age <= maximum)
      end

      def children_comparison(left, right)
        pair = comparable_pair(:wants_children, left, right)
        return unless pair

        fit = if pair.first == pair.last
          1.0
        elsif pair.include?("open") || pair.include?("maybe")
          0.6
        else
          0.0
        end
        comparison(:wants_children, fit, fit == 1.0 ? "aligned_family_plans" : nil)
      end

      def ordered_comparison(key, left, right, order, adjacent_fit:, reason:)
        pair = comparable_pair(key, left, right)
        return unless pair

        indexes = pair.map { |value| order.index(value) }
        fit = if pair.first == pair.last
          1.0
        elsif indexes.none?(&:nil?) && (indexes.first - indexes.last).abs == 1
          adjacent_fit
        else
          0.0
        end
        comparison(key, fit, fit == 1.0 ? reason : nil)
      end

      def matrix_comparison(key, left, right, matrix, reason:)
        pair = comparable_pair(key, left, right)
        return unless pair

        fit = pair.first == pair.last ? 1.0 : matrix.fetch(pair.sort, 0.0)
        comparison(key, fit, fit == 1.0 ? reason : nil)
      end

      def comparable_pair(key, left, right)
        values = [ left[key], right[key] ]
        return if values.any?(&:blank?) || values.include?("prefer_not_to_say")

        values
      end

      def comparison(key, fit, reason)
        { weight: WEIGHTS.fetch(key), fit:, reason: }
      end

      def genotype_check(first, second)
        values = [ first, second ]
        if values.any?(&:blank?) || values.any? { |value| UNASSESSED_GENOTYPES.include?(value) }
          return { status: "not_assessed", evidence_level: "incomplete" }
        end
        unless values.all? { |value| KNOWN_GENOTYPES.include?(value) }
          return { status: "clinical_review_required", evidence_level: "self_reported" }
        end

        outcomes = values.first.chars.product(values.last.chars).map { |alleles| alleles.sort.join }
        sickle_probability = probability(outcomes, SICKLE_CELL_DISEASE_OUTCOMES)
        other_probability = probability(outcomes, OTHER_HEMOGLOBIN_DISEASE_OUTCOMES)
        status = if sickle_probability.positive?
          "elevated_sickle_cell_risk"
        elsif other_probability.positive?
          "other_hemoglobin_risk"
        else
          "no_elevated_risk_identified"
        end
        {
          status:, evidence_level: "self_reported",
          sickle_cell_disease_probability: sickle_probability,
          other_hemoglobin_disease_probability: other_probability
        }
      end

      def probability(outcomes, disease_outcomes)
        (outcomes.count { |outcome| disease_outcomes.include?(outcome) }.fdiv(outcomes.size)).round(2)
      end

      def values_for(profile)
        selections = option_selections_for(profile).group_by { |selection| selection.profile_option_group.key }
        value = ->(key) { selections.fetch(key.to_s, []).map { |selection| selection.profile_option.code }.sort.first }
        preference = profile.profile_preference
        {
          religion: value.call(:religion), tribe: value.call(:tribe),
          intertribal_marriage_openness: value.call(:intertribal_marriage_openness),
          relationship_intent: value.call(:relationship_intent),
          commitment_timeline: value.call(:commitment_timeline),
          wants_children: value.call(:wants_children), faith_practice: value.call(:faith_practice),
          money_providing: value.call(:money_providing), conflict: value.call(:conflict),
          genotype: value.call(:genotype), country_code: profile.country_code,
          willing_to_relocate: profile.willing_to_relocate,
          relocation_preferences: Array(profile.relocation_preferences),
          age: age(profile.birthdate), min_age: preference&.min_age, max_age: preference&.max_age
        }
      end

      def option_selections_for(profile)
        association = profile.association(:profile_option_selections)
        records = association.loaded? ? association.target : profile.profile_option_selections
          .includes(:profile_option, :profile_option_group).to_a
        records.select do |selection|
          selection.deleted_at.nil? && selection.profile_option.status_active? &&
            selection.profile_option_group.status_active?
        end
      end

      def age(birthdate)
        return if birthdate.blank?

        today = Date.current
        today.year - birthdate.year - ((today.month * 100 + today.day) <
          (birthdate.month * 100 + birthdate.day) ? 1 : 0)
      end

      def confidence_level(confidence)
        return "high" if confidence >= 0.75
        return "medium" if confidence >= 0.45

        "low"
      end
    end
  end
end
