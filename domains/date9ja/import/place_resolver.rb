# frozen_string_literal: true

module Date9ja
  module Import
    # Conservative bridge from the legacy `city` field to D8N's curated Place
    # catalogue. A source city must exactly identify one selectable Nigerian
    # city, locality, or region. Non-Nigerian and ambiguous/unavailable places
    # require member confirmation; the synthetic outside-country centroid is
    # never assigned merely to satisfy completion.
    module PlaceResolver
      module_function

      def call(city:, country_code:)
        return unless country_code == "NG"

        normalized = normalize(city)
        return if normalized.empty?

        candidates = Place.selectable.where(country_code: "NG").where.not(kind: Place.kinds.fetch("country")).select do |place|
          normalize(place.name) == normalized || normalize(place.code.tr("-", " ")) == normalized
        end

        %w[city locality region].each do |kind|
          matches = candidates.select { |place| place.kind == kind }
          return matches.first if matches.one?
          return nil if matches.many?
        end

        nil
      end

      def normalize(value)
        value.to_s.strip.downcase.gsub(/\s+/, " ")
      end
      private_class_method :normalize
    end
  end
end
