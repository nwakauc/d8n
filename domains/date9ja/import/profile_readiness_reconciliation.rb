# frozen_string_literal: true

module Date9ja
  module Import
    class ProfileReadinessReconciliation
      DISPOSITIONS = %i[ready intentionally_hidden remediation_required failed].freeze
      MEASURES = %i[
        source_users_considered source_ineligible eligible complete_before complete_after
        names_source_present names_mapped names_preserved names_unresolved
        countries_source_present countries_mapped countries_preserved countries_unresolved
        locations_mapped locations_preserved locations_unresolved
        age_ranges_preserved age_ranges_unresolved
        relationship_intent_satisfied relationship_intent_unresolved
        has_children_satisfied has_children_unresolved
        wants_children_satisfied wants_children_unresolved
        publications_applied publications_withdrawn native_values_preserved
        ineligible_suppression_failed
      ].freeze

      def initialize
        @counts = Hash.new(0)
        @reasons = Hash.new(0)
        @measures = Hash.new(0)
      end

      def measure!(name, value = 1)
        raise ArgumentError, "unknown measure #{name}" unless MEASURES.include?(name)

        @measures[name] += value
      end

      def disposition!(name, reasons: [])
        raise ArgumentError, "unknown disposition #{name}" unless DISPOSITIONS.include?(name)

        @counts[name] += 1
        reasons.uniq.each { |reason| @reasons[reason.to_s] += 1 }
      end

      def count(name) = @counts[name.to_sym]
      def reason_count(code) = @reasons[code.to_s]

      def balanced?
        @measures[:eligible] == DISPOSITIONS.sum { |name| @counts[name] }
      end

      def to_h
        {
          "balanced" => balanced?,
          "dispositions" => DISPOSITIONS.to_h { |name| [ name.to_s, @counts[name] ] },
          "measures" => MEASURES.to_h { |name| [ name.to_s, @measures[name] ] },
          "reason_codes" => @reasons.sort.to_h
        }
      end
    end
  end
end
