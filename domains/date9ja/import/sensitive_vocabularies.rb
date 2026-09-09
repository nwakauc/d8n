# frozen_string_literal: true

module Date9ja
  module Import
    # The explicit Date9ja -> D8N alias tables for the SENSITIVE identity /
    # culture / health-adjacent values. Held apart from the ordinary mappings so
    # the firewall and the review are obvious.
    #
    # Every table is fail-closed: a value it does not recognise is quarantined
    # and noted, never approximated. The tables are SEEDED from the D8N option
    # codes (Profiles::CapabilityCatalog) and their everyday synonyms; the
    # Date9ja source enum/constant is the authority that extends them, and until
    # the privacy-safe source classification runs (source_census.sql sensitive
    # measures) the unrecognised bucket is expected to be non-trivial.
    module SensitiveVocabularies
      module_function

      def option_codes(key)
        Profiles::CapabilityCatalog::OPTION_CAPABILITIES.fetch(key).fetch(:options).keys
      end

      TRIBE = ControlledVocabularyMapping.new(
        valid_codes: -> { option_codes("tribe") },
        aliases: {
          "igbo" => "igbo", "ibo" => "igbo", "yoruba" => "yoruba", "hausa" => "hausa",
          "fulani" => "fulani", "hausa fulani" => "fulani", "ijaw" => "ijaw", "izon" => "ijaw",
          "ibibio" => "ibibio", "edo" => "edo", "bini" => "edo", "kanuri" => "kanuri",
          "other" => "other", "prefer not to say" => "prefer_not_to_say", "none" => "prefer_not_to_say"
        }
      )

      ETHNICITY = ControlledVocabularyMapping.new(
        valid_codes: -> { option_codes("ethnicity") },
        aliases: {
          "igbo" => "igbo", "ibo" => "igbo", "yoruba" => "yoruba", "hausa" => "hausa",
          "fulani" => "fulani", "ijaw" => "ijaw", "ibibio" => "ibibio", "edo" => "edo", "bini" => "edo",
          "kanuri" => "kanuri", "tiv" => "tiv", "nupe" => "nupe", "igala" => "igala",
          "efik" => "efik", "urhobo" => "urhobo", "itsekiri" => "itsekiri", "annang" => "annang",
          "mixed" => "mixed", "mixed race" => "mixed", "other" => "other",
          "prefer not to say" => "prefer_not_to_say"
        }
      )

      RELIGION = ControlledVocabularyMapping.new(
        valid_codes: -> { option_codes("religion") },
        aliases: {
          "christian" => "christian", "christianity" => "christian", "catholic" => "christian",
          "protestant" => "christian", "pentecostal" => "christian",
          "muslim" => "muslim", "islam" => "muslim", "islamic" => "muslim",
          "hindu" => "hindu", "hinduism" => "hindu", "buddhist" => "buddhist", "buddhism" => "buddhist",
          "jewish" => "jewish", "judaism" => "jewish", "sikh" => "sikh", "sikhism" => "sikh",
          "traditional" => "spiritual", "african traditional" => "spiritual", "spiritual" => "spiritual",
          "agnostic" => "agnostic", "atheist" => "atheist", "none" => "atheist",
          "other" => "other", "prefer not to say" => "prefer_not_to_say"
        }
      )

      DENOMINATION = ControlledVocabularyMapping.new(
        valid_codes: -> { option_codes("denomination") },
        aliases: {
          "catholic" => "catholic", "roman catholic" => "catholic", "anglican" => "anglican",
          "church of nigeria" => "anglican", "pentecostal" => "pentecostal", "baptist" => "baptist",
          "methodist" => "methodist", "presbyterian" => "presbyterian", "orthodox" => "orthodox",
          "adventist" => "adventist", "seventh day adventist" => "adventist",
          "evangelical" => "evangelical", "non denominational" => "non_denominational",
          "nondenominational" => "non_denominational", "sunni" => "sunni", "shia" => "shia",
          "shiite" => "shia", "ahmadiyya" => "ahmadiyya", "none" => "none", "other" => "other",
          "prefer not to say" => "prefer_not_to_say"
        }
      )

      GENOTYPE = ControlledVocabularyMapping.new(
        valid_codes: -> { option_codes("genotype") },
        aliases: {
          "aa" => "aa", "as" => "as", "ss" => "ss", "ac" => "ac", "sc" => "sc", "cc" => "cc",
          "not tested" => "not_tested", "unknown" => "not_tested", "dont know" => "not_tested",
          "prefer not to say" => "prefer_not_to_say"
        }
      )

      OPENNESS_ALIASES = {
        "open" => "open", "yes" => "open", "true" => "open", "1" => "open",
        "not open" => "not_open", "no" => "not_open", "false" => "not_open", "0" => "not_open",
        "closed" => "not_open", "depends" => "depends", "maybe" => "depends", "unsure" => "depends",
        "prefer not to say" => "prefer_not_to_say"
      }.freeze

      INTERTRIBAL_MARRIAGE_OPENNESS = ControlledVocabularyMapping.new(
        valid_codes: -> { option_codes("intertribal_marriage_openness") }, aliases: OPENNESS_ALIASES
      )
      POLYGAMY_OPENNESS = ControlledVocabularyMapping.new(
        valid_codes: -> { option_codes("polygamy_openness") }, aliases: OPENNESS_ALIASES
      )

      # Matching-preference arrays -> ProfilePreference#preferred_attributes.
      # Each reuses the profile-side vocabulary (a preference for a religion is
      # stated in the same terms a member states their own).
      PREFERRED = {
        "religion" => RELIGION, "tribe" => TRIBE, "ethnicity" => ETHNICITY, "genotype" => GENOTYPE
      }.freeze
    end
  end
end
