# frozen_string_literal: true

module Date9ja
  module Import
    # Reviewed Date9ja `languages_spoken` element -> D8N structured-language code
    # (Profiles::Languages / config/profiles/languages.yml).
    #
    # Deliberately explicit and exact after case/whitespace normalization: no
    # fuzzy matching, no dialect inference, no "closest language". A legacy value
    # not listed here stays unmapped and is recorded as a reconciliation note —
    # the member keeps nothing invented.
    #
    # The legacy source is a flat array with no proficiency or "primary" signal
    # (ADR 0017 / E-3), so every migrated entry is `{ code:, proficiency: nil,
    # primary: false }`. A value D8N has no taxonomy code for — most notably
    # "Pidgin" / "Nigerian Pidgin", which config/profiles/languages.yml does not
    # carry — is left unmapped rather than approximated to a neighbour.
    module LanguageMapping
      Outcome = Data.define(:status, :codes) do
        def mapped? = status == :mapped
      end

      ALIASES = {
        "english" => "en", "en" => "en",
        "french" => "fr", "francais" => "fr", "fr" => "fr",
        "spanish" => "es", "portuguese" => "pt", "german" => "de", "italian" => "it",
        "arabic" => "ar", "swahili" => "sw", "kiswahili" => "sw",
        "yoruba" => "yo", "igbo" => "ig", "ibo" => "ig", "hausa" => "ha",
        "amharic" => "am", "somali" => "so", "zulu" => "zu", "xhosa" => "xh",
        "afrikaans" => "af", "twi" => "tw", "akan" => "tw",
        "mandarin" => "zh", "chinese" => "zh", "hindi" => "hi", "urdu" => "ur",
        "russian" => "ru", "turkish" => "tr", "dutch" => "nl"
      }.freeze

      module_function

      # `values` is the raw legacy array (or nil). Returns the unique, order-
      # preserving list of D8N codes for the values that mapped, and whether any
      # value went unmapped so the caller can record a note.
      def call(values)
        list = Array(values).filter_map { |value| normalize(value) }
        return Outcome.new(status: :absent, codes: []) if list.empty?

        codes = []
        unmapped = false
        list.each do |name|
          code = ALIASES[name]
          if code && Profiles::Languages.valid_code?(code)
            codes << code unless codes.include?(code)
          else
            unmapped = true
          end
        end

        return Outcome.new(status: :unmapped, codes: codes) if codes.empty?

        Outcome.new(status: (unmapped ? :partial : :mapped), codes: codes)
      end

      def normalize(value)
        text = value.to_s.strip.downcase.gsub(/\s+/, " ")
        text.empty? ? nil : text
      end
      private_class_method :normalize
    end
  end
end
