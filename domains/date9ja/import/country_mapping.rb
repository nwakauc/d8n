# frozen_string_literal: true

module Date9ja
  module Import
    # Reviewed Date9ja source aliases. Deliberately explicit and exact after
    # case/whitespace normalization: no fuzzy country guessing, no typo repair,
    # no subdivision→country inference, and no inference of nationality or
    # preferences. A value not listed here stays unmapped and the member's
    # `country_code` is left unset (recorded as a reconciliation note).
    #
    # The first block is the original 7-country majority + 3 (source_census.sql
    # measure 266). The second block was added 2026-09-09 from the authoritative
    # 2026-09-08 snapshot census (Profile Preservation Pass 1): every remaining
    # `country_of_residence` value in the migration-eligible cohort that is an
    # unambiguous, correctly-spelled country name. Two eligible values are still
    # deliberately unmapped — `california` (a subdivision, not a country) and
    # `nigeri` (an apparent typo) — because repairing either is a guess.
    module CountryMapping
      Outcome = Data.define(:status, :country_code) do
        def mapped? = status == :mapped
      end

      ALIASES = {
        "ng" => "NG", "nga" => "NG", "nigeria" => "NG",
        "gb" => "GB", "uk" => "GB", "gbr" => "GB", "united kingdom" => "GB",
        "us" => "US", "usa" => "US", "united states" => "US", "united states of america" => "US",
        "ca" => "CA", "can" => "CA", "canada" => "CA",
        "gh" => "GH", "gha" => "GH", "ghana" => "GH",
        "za" => "ZA", "zaf" => "ZA", "south africa" => "ZA",
        "ke" => "KE", "ken" => "KE", "kenya" => "KE",
        "ie" => "IE", "irl" => "IE", "ireland" => "IE",
        "de" => "DE", "deu" => "DE", "germany" => "DE",
        "ae" => "AE", "are" => "AE", "united arab emirates" => "AE",
        # Census-attested exact country names, 2026-09-08 snapshot, eligible cohort.
        "andorra" => "AD", "angola" => "AO", "afghanistan" => "AF",
        "australia" => "AU", "botswana" => "BW", "brazil" => "BR",
        "equatorial guinea" => "GQ", "france" => "FR", "israel" => "IL",
        "jamaica" => "JM", "japan" => "JP", "malawi" => "MW",
        "new zealand" => "NZ", "rwanda" => "RW", "somalia" => "SO", "uganda" => "UG"
      }.freeze

      # The curated ALIASES (code forms like `uk`/`usa` and census-attested
      # spellings) win; the complete ISO 3166-1 name table backfills every other
      # correctly-spelled country name so an unobserved-but-valid value is not
      # dropped (audit blocker ledger item 8). Still a closed, exact table — no
      # typo repair, no subdivision inference.
      RESOLVED = IsoCountryAliases::NAMES.merge(ALIASES).freeze

      module_function

      def call(value)
        normalized = value.to_s.strip.downcase.gsub(/\s+/, " ")
        code = RESOLVED[normalized]
        return Outcome.new(status: :unmapped, country_code: nil) if code.nil?
        unless code.match?(Profiles::FieldCatalog.format_pattern("country_code"))
          return Outcome.new(status: :unmapped, country_code: nil)
        end

        Outcome.new(status: :mapped, country_code: code)
      end
    end
  end
end
