module Profiles
  module DatezaDemoSeed
    # DateZA-specific profile composition layered over the shared deterministic
    # demo-person inputs (name, age, images and stable content helpers). It writes
    # only capabilities enabled by DatezaProfileCatalog.
    class Content < DemoSeed::Content
      RELATIONSHIP_INTENTS = DatezaProfileCatalog::RELATIONSHIP_INTENTS
      HAS_CHILDREN = %w[ yes no prefer_not_to_say ].freeze
      WANTS_CHILDREN = %w[ yes maybe no open_to_partner_with_children prefer_not_to_say ].freeze
      RELIGION_IMPORTANCE = %w[ not_important somewhat_important very_important prefer_not_to_say ].freeze
      SOCIAL_STYLES = %w[ introverted ambivert extroverted depends_on_the_vibe ].freeze
      MEETING_PACES = %w[ chat_first video_call_first few_days meet_soon go_with_the_flow ].freeze
      DATEZA_PROMPT_ANSWERS = {
        "green_flag" => DemoSeed::Content::PROMPT_ANSWERS.fetch("green_flag"),
        "ideal_first_meet" => DemoSeed::Content::PROMPT_ANSWERS.fetch("ideal_first_meet"),
        "looking_for" => [
          "Something genuine, steady, and fun enough that neither of us has to force it.",
          "A real connection with someone who communicates clearly and shows up.",
          "Someone kind, curious, and ready to build towards something meaningful."
        ],
        "weekend_plan" => [
          "A slow breakfast, somewhere outdoors, then dinner with good people.",
          "A market in the morning and a braai that runs later than planned.",
          "A road trip, a new restaurant, or a quiet reset at home."
        ],
        "geek_out" => [
          "Finding the best food spots before everyone else does.",
          "Music, travel plans, and a very specific podcast recommendation.",
          "The tiny details that make a place, meal, or story memorable."
        ],
        "dealbreaker" => [
          "Inconsistency dressed up as being busy.",
          "Being rude to people when there is nothing to gain from being kind.",
          "Avoiding honest conversations when they matter."
        ]
      }.freeze

      private

      def profile_attributes
        city, country, = city_row
        {
          display_name: person.display_name,
          bio: bio,
          gender: person.gender,
          country_code: country,
          city:,
          occupation: maybe(:occupation, 70) { pick(OCCUPATIONS, :occupation) },
          job_title: maybe(:job_title, 45) { pick(OCCUPATIONS, :job_title) },
          height_cm: maybe(:height, 60) { height },
          smoking: pick(LIFESTYLE_LEVELS, :smoking),
          drinking: pick(LIFESTYLE_LEVELS, :drinking),
          fitness: maybe(:fitness, 65) { pick(LIFESTYLE_LEVELS, :fitness) },
          languages: languages
        }
      end

      def preference_attributes
        {
          interested_in: INTERESTED_IN,
          min_age: PREFERENCE_MIN_AGE,
          max_age: PREFERENCE_MAX_AGE,
          max_distance_km: 100
        }
      end

      def option_selections
        {
          "relationship_intent" => [ pick(RELATIONSHIP_INTENTS, :relationship_intent) ],
          "has_children" => [ pick(HAS_CHILDREN, :has_children) ],
          "wants_children" => [ pick(WANTS_CHILDREN, :wants_children) ],
          "religion_importance" => [ pick(RELIGION_IMPORTANCE, :religion_importance) ],
          "social_style" => [ pick(SOCIAL_STYLES, :social_style) ],
          "meeting_pace" => [ pick(MEETING_PACES, :meeting_pace) ],
          "interests" => sample(DatezaProfileCatalog::INTERESTS, :interests, min: 3, max: 7)
        }
      end

      def prompt_answers
        keys = DatezaProfileCatalog::ENABLED_PROMPTS.sort_by { |key| h(:"prompt_#{key}") }.first(2)
        keys.map do |key|
          answers = DATEZA_PROMPT_ANSWERS.fetch(key)
          { key:, answer: answers[(index + h(:"prompt_answer_#{key}")) % answers.size] }
        end
      end
    end
  end
end
