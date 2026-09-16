# frozen_string_literal: true

module Date9ja
  module Import
    # Reusable explicit-alias mapper for a single controlled-vocabulary Date9ja
    # value -> a D8N option code. Same fail-closed contract as LanguageMapping /
    # InterestMapping: exact after normalization, no fuzzy matching, no "closest
    # value"; an unrecognised value is left unmapped and the caller records a
    # note. The alias table is authored from the D8N option codes and their
    # everyday synonyms; the Date9ja source enum/constant is the authority that
    # extends it once available for review.
    class ControlledVocabularyMapping
      Outcome = Data.define(:status, :code) do
        def mapped? = status == :mapped
        def absent? = status == :absent
        def unmapped? = status == :unmapped
      end

      def initialize(aliases:, valid_codes:)
        @aliases = aliases.freeze
        @valid_codes = valid_codes
      end

      # `value` is a single scalar legacy value (String or nil).
      def call(value)
        name = normalize(value)
        return Outcome.new(status: :absent, code: nil) if name.nil?

        code = @aliases[name]
        return Outcome.new(status: :unmapped, code: nil) unless code && valid_codes.include?(code)

        Outcome.new(status: :mapped, code: code)
      end

      # `values` is a legacy array; returns the unique mapped codes plus whether
      # anything went unmapped (for a matching-preference array).
      MultiOutcome = Data.define(:status, :codes) do
        def mapped? = status == :mapped
        def absent? = status == :absent
        def unmapped? = status == :unmapped
      end

      def call_many(values)
        list = Array(values).filter_map { |v| normalize(v) }
        return MultiOutcome.new(status: :absent, codes: []) if list.empty?

        codes = []
        unmapped = false
        list.each do |name|
          code = @aliases[name]
          if code && valid_codes.include?(code)
            codes << code unless codes.include?(code)
          else
            unmapped = true
          end
        end
        return MultiOutcome.new(status: :unmapped, codes: []) if codes.empty?

        MultiOutcome.new(status: (unmapped ? :partial : :mapped), codes: codes)
      end

      def valid_codes
        @resolved_valid_codes ||= (@valid_codes.respond_to?(:call) ? @valid_codes.call : @valid_codes).to_set
      end

      private

      def normalize(value)
        text = value.to_s.strip.downcase.gsub(%r{[_/-]}, " ").gsub(/[^a-z0-9 ]/, "").gsub(/\s+/, " ").strip
        text.empty? ? nil : text
      end
    end
  end
end
