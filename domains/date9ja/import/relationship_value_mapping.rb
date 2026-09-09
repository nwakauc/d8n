# frozen_string_literal: true

module Date9ja
  module Import
    # Reviewed Date9ja `relationship_values` element -> D8N `relationship_values`
    # option code (Profiles::CapabilityCatalog::OPTION_CAPABILITIES).
    #
    # Same fail-closed contract as InterestMapping / LanguageMapping: explicit
    # and exact after normalization; an unrecognised value is quarantined and
    # noted, never approximated. Seeded with each code, its label, and everyday
    # synonyms; the exhaustive review that extends it (E-4) is still blocked on
    # the sanitizer classification of the element vocabulary.
    module RelationshipValueMapping
      Outcome = Data.define(:status, :codes) do
        def mapped? = status == :mapped
        def absent? = status == :absent
        def unmapped? = status == :unmapped
      end

      ALIASES = {
        "honesty" => "honesty", "honest" => "honesty", "truthfulness" => "honesty",
        "loyalty" => "loyalty", "loyal" => "loyalty", "faithfulness" => "loyalty", "faithful" => "loyalty",
        "trust" => "trust", "trustworthiness" => "trust",
        "communication" => "communication", "good communication" => "communication", "open communication" => "communication",
        "respect" => "respect", "mutual respect" => "respect",
        "faith" => "faith", "shared faith" => "faith", "religion" => "faith", "god" => "faith", "spirituality" => "faith",
        "family" => "family", "family oriented" => "family", "family values" => "family",
        "ambition" => "ambition", "ambitious" => "ambition", "drive" => "ambition", "hardworking" => "ambition",
        "independence" => "independence", "independent" => "independence",
        "growth" => "growth", "personal growth" => "growth", "self improvement" => "growth",
        "kindness" => "kindness", "kind" => "kindness", "compassion" => "kindness",
        "humour" => "humour", "humor" => "humour", "sense of humour" => "humour", "funny" => "humour",
        "adventure" => "adventure", "adventurous" => "adventure", "spontaneity" => "adventure",
        "stability" => "stability", "stable" => "stability", "security" => "stability",
        "generosity" => "generosity", "generous" => "generosity",
        "emotional openness" => "emotional_openness", "vulnerability" => "emotional_openness",
        "emotional availability" => "emotional_openness", "emotional intelligence" => "emotional_openness"
      }.freeze

      module_function

      def valid_codes
        @valid_codes ||= Profiles::CapabilityCatalog::OPTION_CAPABILITIES
          .fetch("relationship_values").fetch(:options).keys.to_set
      end

      def call(values)
        list = Array(values).filter_map { |value| normalize(value) }
        return Outcome.new(status: :absent, codes: []) if list.empty?

        codes = []
        unmapped = false
        list.each do |name|
          code = ALIASES[name]
          if code && valid_codes.include?(code)
            codes << code unless codes.include?(code)
          else
            unmapped = true
          end
        end

        return Outcome.new(status: :unmapped, codes: []) if codes.empty?

        Outcome.new(status: (unmapped ? :partial : :mapped), codes: codes)
      end

      def normalize(value)
        text = value.to_s.strip.downcase.gsub(%r{[_/-]}, " ").gsub(/[^a-z0-9 ]/, "").gsub(/\s+/, " ").strip
        text.empty? ? nil : text
      end
      private_class_method :normalize
    end
  end
end
