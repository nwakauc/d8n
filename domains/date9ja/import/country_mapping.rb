# frozen_string_literal: true

module Date9ja
  module Import
    # Reviewed Date9ja source aliases from source_census.sql measure 266. This is
    # deliberately explicit and exact after case/whitespace normalization: no
    # fuzzy country guessing and no inference of nationality or preferences.
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
        "ae" => "AE", "are" => "AE", "united arab emirates" => "AE"
      }.freeze

      module_function

      def call(value)
        normalized = value.to_s.strip.downcase.gsub(/\s+/, " ")
        code = ALIASES[normalized]
        return Outcome.new(status: :unmapped, country_code: nil) if code.nil?
        unless code.match?(Profiles::FieldCatalog.format_pattern("country_code"))
          return Outcome.new(status: :unmapped, country_code: nil)
        end

        Outcome.new(status: :mapped, country_code: code)
      end
    end
  end
end
