module Geography
  # The provider Geography::Search is configured with today: D8N's own
  # curated Place catalog (see SouthAfricaCatalog), not an external geocoding
  # vendor. No third-party geography service is wired up anywhere in D8N (see
  # Geography::Search's documentation for why) — this searches real,
  # already-selectable Place rows, so results are never fabricated and are
  # always immediately usable by PUT /api/v1/profile/place without a separate
  # normalization/upsert step.
  #
  # A future external provider (or a provider that falls back to this one)
  # would implement the same #search(query:, country_codes:) contract and
  # return the same ProviderResult shape — Geography::Search and every caller
  # above it would not change.
  class PlaceCatalogProvider
    # Country is never a selectable dating-area result on its own.
    RESULT_KINDS = %w[ region city locality ].freeze

    def self.search(query:, country_codes:)
      new.search(query:, country_codes:)
    end

    def search(query:, country_codes:)
      return [] if country_codes.blank?

      Place.selectable
        .where(country_code: country_codes, kind: Place.kinds.values_at(*RESULT_KINDS))
        .where("name ILIKE ?", "%#{sanitize_like(query)}%")
        .order(:kind, :name)
        .limit(Geography::Search::MAX_RESULTS)
        .map { |place| to_result(place) }
    end

    private

    # Escape ILIKE wildcard/escape characters in user input so a query like
    # "50%" or "a_b" is matched literally, not as a pattern.
    def sanitize_like(value)
      value.gsub(/[%_\\]/) { |char| "\\#{char}" }
    end

    def to_result(place)
      region = place.region? ? place : place.ancestors.find(&:region?)
      city = place.city? ? place : place.ancestors.find(&:city?)

      Geography::ProviderResult.new(
        place_id: place.id,
        label: place.display_path,
        area: place.name,
        city: city&.name,
        region: region&.name,
        country_code: place.country_code,
        kind: place.kind
      )
    end
  end
end
