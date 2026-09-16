# frozen_string_literal: true

module Date9ja
  module Import
    # Reviewed Date9ja `dealbreakers` element -> D8N `dealbreakers` option code
    # (Profiles::CapabilityCatalog::OPTION_CAPABILITIES).
    #
    # LOSSLESS by design: each legacy value maps to a distinct option, never
    # collapsed into a single free-text prompt. Same fail-closed contract as the
    # other curated-array mappings — an unrecognised value is quarantined and
    # noted, never approximated. The exhaustive review that extends this table
    # (E-4) is still blocked on the sanitizer classification of the elements.
    module DealbreakerMapping
      Outcome = Data.define(:status, :codes) do
        def mapped? = status == :mapped
        def absent? = status == :absent
        def unmapped? = status == :unmapped
      end

      ALIASES = {
        "smoking" => "smoking", "smoker" => "smoking", "smokes" => "smoking", "cigarettes" => "smoking",
        "heavy drinking" => "heavy_drinking", "alcohol" => "heavy_drinking", "drinking" => "heavy_drinking",
        "alcoholism" => "heavy_drinking", "drunk" => "heavy_drinking",
        "drugs" => "drugs", "drug use" => "drugs", "hard drugs" => "drugs", "substance abuse" => "drugs",
        "wants children" => "wants_children", "wants kids" => "wants_children",
        "doesnt want children" => "does_not_want_children", "doesnt want kids" => "does_not_want_children",
        "does not want children" => "does_not_want_children", "no kids" => "does_not_want_children",
        "childfree" => "does_not_want_children",
        "already has children" => "already_has_children", "has kids" => "already_has_children",
        "has children" => "already_has_children", "single parent" => "already_has_children",
        "long distance" => "long_distance", "distance" => "long_distance",
        "different faith" => "different_faith", "different religion" => "different_faith",
        "religion" => "different_faith", "non believer" => "different_faith", "atheist" => "different_faith",
        "no ambition" => "no_ambition", "lazy" => "no_ambition", "unmotivated" => "no_ambition", "no drive" => "no_ambition",
        "poor communication" => "poor_communication", "bad communication" => "poor_communication",
        "doesnt communicate" => "poor_communication",
        "dishonesty" => "dishonesty", "lying" => "dishonesty", "liar" => "dishonesty", "cheating" => "dishonesty",
        "jealousy" => "jealousy", "jealous" => "jealousy", "possessive" => "jealousy", "controlling" => "jealousy",
        "different politics" => "different_politics", "politics" => "different_politics",
        "not financially stable" => "not_financially_stable", "broke" => "not_financially_stable",
        "no job" => "not_financially_stable", "unemployed" => "not_financially_stable", "financial instability" => "not_financially_stable",
        "not open to marriage" => "against_marriage", "doesnt want marriage" => "against_marriage",
        "against marriage" => "against_marriage", "anti marriage" => "against_marriage",
        "poor hygiene" => "poor_hygiene", "bad hygiene" => "poor_hygiene", "hygiene" => "poor_hygiene"
      }.freeze

      module_function

      def valid_codes
        @valid_codes ||= Profiles::CapabilityCatalog::OPTION_CAPABILITIES
          .fetch("dealbreakers").fetch(:options).keys.to_set
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
        text = value.to_s.strip.downcase.gsub(%r{[_/-]}, " ").gsub(/['’]/, "").gsub(/[^a-z0-9 ]/, "").gsub(/\s+/, " ").strip
        text.empty? ? nil : text
      end
      private_class_method :normalize
    end
  end
end
