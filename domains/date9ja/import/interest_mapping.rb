# frozen_string_literal: true

module Date9ja
  module Import
    # Reviewed Date9ja `interests` element -> D8N curated interest code
    # (Profiles::CapabilityCatalog::INTERESTS).
    #
    # Same contract as LanguageMapping: explicit and exact after case/whitespace/
    # punctuation normalization. No fuzzy matching, no "closest interest". A
    # legacy value not listed here stays unmapped and is recorded as a
    # reconciliation note (quarantined, never approximated).
    #
    # The alias table is SEEDED with each D8N code, its label, and unambiguous
    # everyday synonyms. Date9ja's element vocabulary is sanitizer-redacted, so
    # the exhaustive review that extends this table (E-4) has not run yet; until
    # it does, an unrecognised element is quarantined, never guessed.
    module InterestMapping
      Outcome = Data.define(:status, :codes) do
        def mapped? = status == :mapped
        def absent? = status == :absent
        def unmapped? = status == :unmapped
      end

      ALIASES = {
        "foodie" => "foodie", "food" => "foodie", "foodies" => "foodie",
        "restaurants" => "restaurants", "eating out" => "restaurants", "dining" => "restaurants",
        "cooking" => "cooking", "cook" => "cooking", "baking" => "cooking",
        "coffee" => "coffee", "wine" => "wine", "cocktails" => "cocktails",
        "brunch" => "brunch",
        "live music" => "live_music", "music" => "live_music", "concerts" => "live_music", "gigs" => "live_music",
        "festivals" => "festivals", "festival" => "festivals",
        "afrobeats" => "afrobeats", "afrobeat" => "afrobeats", "afro beats" => "afrobeats",
        "amapiano" => "amapiano", "hip hop" => "hip_hop", "hiphop" => "hip_hop", "rap" => "hip_hop",
        "rnb" => "rnb", "r&b" => "rnb", "r and b" => "rnb",
        "house music" => "house_music", "house" => "house_music",
        "karaoke" => "karaoke",
        "travel" => "travel", "traveling" => "travel", "travelling" => "travel", "travels" => "travel",
        "road trips" => "road_trips", "road trip" => "road_trips",
        "beach" => "beach", "beaches" => "beach",
        "camping" => "camping",
        "hiking" => "hiking", "hike" => "hiking", "tramping" => "hiking",
        "nature" => "nature", "outdoors" => "nature",
        "cycling" => "cycling", "biking" => "cycling", "bike rides" => "cycling",
        "gym" => "gym", "fitness" => "gym", "working out" => "gym", "weightlifting" => "gym",
        "running" => "running", "jogging" => "running",
        "yoga" => "yoga", "pilates" => "pilates",
        "football" => "football", "soccer" => "football",
        "basketball" => "basketball", "rugby" => "rugby", "cricket" => "cricket", "tennis" => "tennis",
        "nightlife" => "nightlife", "clubbing" => "nightlife", "partying" => "nightlife",
        "dancing" => "dancing", "dance" => "dancing",
        "bars" => "bars", "pubs" => "bars",
        "gaming" => "gaming", "video games" => "gaming", "games" => "gaming",
        "esports" => "esports", "e-sports" => "esports",
        "movies" => "movies", "film" => "movies", "films" => "movies", "cinema" => "movies",
        "anime" => "anime", "manga" => "anime",
        "reading" => "reading", "books" => "reading", "novels" => "reading",
        "podcasts" => "podcasts", "podcast" => "podcasts",
        "tv series" => "tv_series", "tv" => "tv_series", "series" => "tv_series", "netflix" => "tv_series",
        "art" => "art", "painting" => "art", "drawing" => "art",
        "photography" => "photography", "photo" => "photography",
        "fashion" => "fashion", "style" => "fashion",
        "writing" => "writing", "poetry" => "writing",
        "making music" => "music_making", "music making" => "music_making",
        "producing" => "music_making", "singing" => "music_making",
        "museums" => "museums", "theatre" => "theatre", "theater" => "theatre",
        "history" => "history",
        "meditation" => "meditation", "mindfulness" => "mindfulness", "spa" => "spa",
        "volunteering" => "volunteering", "charity" => "volunteering",
        "board games" => "board_games", "boardgames" => "board_games",
        "spontaneous plans" => "spontaneous_plans"
      }.freeze

      module_function

      def valid_codes
        @valid_codes ||= Profiles::CapabilityCatalog::INTERESTS.fetch(:options).map { |option| option.fetch(:code) }.to_set
      end

      # `values` is the raw legacy array (or nil). Returns the unique, order-
      # preserving list of mapped D8N codes and whether anything went unmapped.
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
        text = value.to_s.strip.downcase.gsub(%r{[_/]}, " ").gsub(/[^a-z0-9& ]/, "").gsub(/\s+/, " ").strip
        text.empty? ? nil : text
      end
      private_class_method :normalize
    end
  end
end
