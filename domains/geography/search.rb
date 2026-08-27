module Geography
  # D8N's single entry point for "enter my area or suburb" search. Owns query
  # validation, brand/country restriction, provider selection, normalization,
  # and caching — a controller (or any future caller) only ever talks to this
  # class, never to a provider directly, so the provider can be replaced later
  # without changing the API contract.
  #
  # No external geocoding vendor is configured today: doing so requires a
  # business/cost decision (API key, usage terms) this ticket cannot make on
  # its own, so PlaceCatalogProvider — D8N's own curated Place data — is the
  # active provider. See docs/api/openapi.yaml and the T-location-search final
  # report for the recommended path to a real provider later.
  class Search
    MIN_QUERY_LENGTH = 2
    MAX_RESULTS = 8
    CACHE_TTL = 15.minutes

    class InvalidQuery < StandardError; end

    def self.call(brand:, query:)
      new(brand:, query:).call
    end

    def initialize(brand:, query:)
      @brand = brand
      @query = query.to_s.strip.squeeze(" ")
    end

    def call
      raise InvalidQuery if query.length < MIN_QUERY_LENGTH

      # Cache key holds no member/session identity — geography search results
      # are the same for every caller of a given brand asking the same
      # question, so nothing here is per-user or privacy-sensitive.
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        PlaceCatalogProvider.search(query:, country_codes:)
      end
    end

    private

    attr_reader :brand, :query

    def country_codes
      D8n::Platform::BrandRegistry.fetch(brand:).place_country_codes
    end

    def cache_key
      "geography_search/v1/#{brand.slug}/#{query.downcase}"
    end
  end
end
