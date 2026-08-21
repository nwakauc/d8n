module Profiles
  # The D8N generic profile-capability catalogue (ADR 0017).
  #
  # This is the reusable platform layer: brand-agnostic DEFINITIONS of profile
  # capabilities (controlled-vocabulary option groups, the categorized interests
  # taxonomy, and prompt definitions) plus idempotent installers. It owns NO brand
  # policy. A brand catalogue (e.g. Profiles::HookusProfileCatalog) composes a
  # subset of these capabilities, choosing per capability:
  #   * whether it is enabled at all
  #   * its display label/copy (codes stay stable; only labels change)
  #   * its public visibility (owner_only / matches_only / public_profile)
  #   * which allowed values (option codes) to offer
  # A new brand (DateZA, Date9ja, …) is added by writing its own brand catalogue
  # that calls these installers — WITHOUT editing this file.
  #
  # INVARIANT: capability keys and option/prompt codes are STABLE internal
  # identifiers with fixed cross-brand meaning (e.g. relationship_intent =>
  # "short_term_fun"). Marketing copy never leaks into a code; brands relabel.
  # Sensitive capabilities (orientation, religion, children, intimacy, cannabis)
  # default to a conservative, non-public visibility and are never auto-installed:
  # a brand must opt in explicitly.
  class CapabilityCatalog
    # Controlled single/multi-select capabilities. `visibility` is the CONSERVATIVE
    # default; a brand may widen or narrow it when enabling. Order of the options
    # hash is the presentation order.
    OPTION_CAPABILITIES = {
      "relationship_intent" => {
        label: "What are you looking for?",
        cardinality: :multiple, max_selections: 8, visibility: :public_profile,
        options: {
          "short_term_fun" => "Short-term fun",
          "casual_dating" => "Casual dating",
          "friends_with_benefits" => "Friends with benefits",
          "open_to_dating" => "Open to dating",
          "long_term_relationship" => "Long-term relationship",
          "marriage" => "Marriage",
          "friendship" => "Friendship",
          "still_figuring_it_out" => "Still figuring it out"
        }
      },
      "meeting_pace" => {
        label: "How soon do you like to meet?",
        cardinality: :single, max_selections: 1, visibility: :public_profile,
        options: {
          "chat_first" => "Chat first",
          "video_call_first" => "Video call first",
          "few_days" => "Within a few days",
          "meet_soon" => "Meet soon",
          "same_day_if_vibe_is_right" => "Same day if the vibe is right",
          "go_with_the_flow" => "Go with the flow"
        }
      },
      "diet" => {
        label: "Diet",
        cardinality: :single, max_selections: 1, visibility: :public_profile,
        options: {
          "anything" => "Anything", "vegetarian" => "Vegetarian", "vegan" => "Vegan",
          "pescatarian" => "Pescatarian", "halal" => "Halal", "kosher" => "Kosher",
          "other" => "Other", "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "pets" => {
        label: "Pets",
        cardinality: :multiple, max_selections: 8, visibility: :public_profile,
        options: {
          "dog" => "Dog", "cat" => "Cat", "bird" => "Bird", "fish" => "Fish",
          "reptile" => "Reptile", "small_pet" => "Small pet", "other" => "Other"
        }
      },
      "pet_preference" => {
        label: "Pet preference",
        cardinality: :single, max_selections: 1, visibility: :public_profile,
        options: {
          "have_pets" => "I have pets", "love_pets" => "Love pets",
          "no_pets" => "No pets", "allergic" => "Allergic",
          "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "sleep_schedule" => {
        label: "Sleep schedule",
        cardinality: :single, max_selections: 1, visibility: :public_profile,
        options: {
          "early_bird" => "Early bird", "night_owl" => "Night owl",
          "flexible" => "Flexible", "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "social_energy" => {
        label: "Social energy",
        cardinality: :single, max_selections: 1, visibility: :public_profile,
        options: {
          "homebody" => "Homebody", "balanced" => "Balanced", "always_out" => "Always out"
        }
      },
      "social_style" => {
        label: "Social style",
        cardinality: :single, max_selections: 1, visibility: :public_profile,
        options: {
          "introverted" => "Introverted", "ambivert" => "Ambivert",
          "extroverted" => "Extroverted", "depends_on_the_vibe" => "Depends on the vibe"
        }
      },
      "communication_style" => {
        label: "Communication style",
        cardinality: :single, max_selections: 1, visibility: :public_profile,
        options: {
          "texting" => "Texting", "voice_notes" => "Voice notes", "calls" => "Calls",
          "in_person" => "In person", "mixed" => "Mixed"
        }
      },
      "planning_style" => {
        label: "Planning style",
        cardinality: :single, max_selections: 1, visibility: :public_profile,
        options: {
          "planner" => "Planner", "spontaneous" => "Spontaneous", "mix_of_both" => "A mix of both"
        }
      },
      "travel_frequency" => {
        label: "How often do you travel?",
        cardinality: :single, max_selections: 1, visibility: :public_profile,
        options: {
          "rarely" => "Rarely", "sometimes" => "Sometimes", "often" => "Often",
          "digital_nomad" => "Digital nomad", "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "preferred_time_of_day" => {
        label: "When are you usually free?",
        cardinality: :single, max_selections: 1, visibility: :public_profile,
        options: {
          "daytime" => "Daytime", "evening" => "Evening",
          "late_night" => "Late night", "flexible" => "Flexible"
        }
      },
      "education_level" => {
        label: "Education",
        cardinality: :single, max_selections: 1, visibility: :public_profile,
        options: {
          "high_school" => "High school", "vocational" => "Vocational",
          "some_college" => "Some college", "undergraduate" => "Undergraduate",
          "postgraduate" => "Postgraduate", "doctorate" => "Doctorate",
          "other" => "Other", "prefer_not_to_say" => "Prefer not to say"
        }
      },
      # --- Sensitive: default to a conservative visibility; opt in per brand. ---
      "sexual_orientation" => {
        label: "Sexual orientation",
        cardinality: :single, max_selections: 1, visibility: :owner_only,
        options: {
          "straight" => "Straight", "gay" => "Gay", "lesbian" => "Lesbian",
          "bisexual" => "Bisexual", "pansexual" => "Pansexual", "asexual" => "Asexual",
          "queer" => "Queer", "questioning" => "Questioning", "other" => "Other",
          "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "cannabis" => {
        label: "Cannabis",
        cardinality: :single, max_selections: 1, visibility: :owner_only,
        options: {
          "never" => "Never", "curious" => "Curious", "sometimes" => "Sometimes",
          "socially" => "Socially", "regularly" => "Regularly",
          "friendly" => "Cannabis-friendly", "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "religion" => {
        label: "Religion",
        cardinality: :single, max_selections: 1, visibility: :owner_only,
        options: {
          "agnostic" => "Agnostic", "atheist" => "Atheist", "buddhist" => "Buddhist",
          "christian" => "Christian", "hindu" => "Hindu", "jewish" => "Jewish",
          "muslim" => "Muslim", "sikh" => "Sikh", "spiritual" => "Spiritual",
          "other" => "Other", "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "religion_importance" => {
        label: "How important is religion to you?",
        cardinality: :single, max_selections: 1, visibility: :owner_only,
        options: {
          "not_important" => "Not important", "somewhat_important" => "Somewhat important",
          "very_important" => "Very important", "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "has_children" => {
        label: "Do you have children?",
        cardinality: :single, max_selections: 1, visibility: :owner_only,
        options: {
          "yes" => "Yes", "no" => "No", "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "wants_children" => {
        label: "Do you want children?",
        cardinality: :single, max_selections: 1, visibility: :owner_only,
        options: {
          "yes" => "Yes", "maybe" => "Maybe", "no" => "No",
          "open_to_partner_with_children" => "Open to a partner with children",
          "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "physical_affection" => {
        label: "Physical affection",
        cardinality: :single, max_selections: 1, visibility: :matches_only,
        options: {
          "low" => "Low", "medium" => "Medium", "high" => "High",
          "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "public_affection" => {
        label: "Public affection",
        cardinality: :single, max_selections: 1, visibility: :matches_only,
        options: {
          "low" => "Low", "medium" => "Medium", "high" => "High",
          "prefer_not_to_say" => "Prefer not to say"
        }
      },
      "chemistry_importance" => {
        label: "How important is chemistry?",
        cardinality: :single, max_selections: 1, visibility: :matches_only,
        options: {
          "low" => "Low", "medium" => "Medium", "high" => "High",
          "prefer_not_to_say" => "Prefer not to say"
        }
      }
    }.freeze

    # The categorized interests taxonomy (single group, per-option `category`).
    # Codes are stable; brands enable a subset and relabel.
    INTERESTS = {
      key: "interests",
      label: "Interests",
      cardinality: :multiple, max_selections: 20, visibility: :public_profile,
      options: [
        { code: "foodie", label: "Foodie", category: "food" },
        { code: "restaurants", label: "Restaurants", category: "food" },
        { code: "cooking", label: "Cooking", category: "food" },
        { code: "coffee", label: "Coffee", category: "food" },
        { code: "wine", label: "Wine", category: "food" },
        { code: "cocktails", label: "Cocktails", category: "food" },
        { code: "brunch", label: "Brunch", category: "food" },
        { code: "live_music", label: "Live music", category: "music" },
        { code: "festivals", label: "Festivals", category: "music" },
        { code: "afrobeats", label: "Afrobeats", category: "music" },
        { code: "amapiano", label: "Amapiano", category: "music" },
        { code: "hip_hop", label: "Hip hop", category: "music" },
        { code: "rnb", label: "R&B", category: "music" },
        { code: "house_music", label: "House music", category: "music" },
        { code: "karaoke", label: "Karaoke", category: "music" },
        { code: "travel", label: "Travel", category: "travel" },
        { code: "road_trips", label: "Road trips", category: "travel" },
        { code: "beach", label: "Beach", category: "travel" },
        { code: "camping", label: "Camping", category: "travel" },
        { code: "hiking", label: "Hiking", category: "outdoors" },
        { code: "nature", label: "Nature", category: "outdoors" },
        { code: "cycling", label: "Cycling", category: "outdoors" },
        { code: "gym", label: "Gym", category: "fitness" },
        { code: "running", label: "Running", category: "fitness" },
        { code: "yoga", label: "Yoga", category: "fitness" },
        { code: "pilates", label: "Pilates", category: "fitness" },
        { code: "football", label: "Football", category: "sports" },
        { code: "basketball", label: "Basketball", category: "sports" },
        { code: "rugby", label: "Rugby", category: "sports" },
        { code: "cricket", label: "Cricket", category: "sports" },
        { code: "tennis", label: "Tennis", category: "sports" },
        { code: "nightlife", label: "Nightlife", category: "nightlife" },
        { code: "dancing", label: "Dancing", category: "nightlife" },
        { code: "bars", label: "Bars", category: "nightlife" },
        { code: "gaming", label: "Gaming", category: "gaming" },
        { code: "esports", label: "Esports", category: "gaming" },
        { code: "movies", label: "Movies", category: "entertainment" },
        { code: "anime", label: "Anime", category: "entertainment" },
        { code: "reading", label: "Reading", category: "entertainment" },
        { code: "podcasts", label: "Podcasts", category: "entertainment" },
        { code: "tv_series", label: "TV series", category: "entertainment" },
        { code: "art", label: "Art", category: "creative" },
        { code: "photography", label: "Photography", category: "creative" },
        { code: "fashion", label: "Fashion", category: "creative" },
        { code: "writing", label: "Writing", category: "creative" },
        { code: "music_making", label: "Making music", category: "creative" },
        { code: "museums", label: "Museums", category: "culture" },
        { code: "theatre", label: "Theatre", category: "culture" },
        { code: "history", label: "History", category: "culture" },
        { code: "meditation", label: "Meditation", category: "wellness" },
        { code: "mindfulness", label: "Mindfulness", category: "wellness" },
        { code: "spa", label: "Spa", category: "wellness" },
        { code: "volunteering", label: "Volunteering", category: "social" },
        { code: "board_games", label: "Board games", category: "social" },
        { code: "spontaneous_plans", label: "Spontaneous plans", category: "social" }
      ].freeze
    }.freeze

    # Prompt definitions (stable keys, editable copy). Brands enable a subset.
    PROMPTS = {
      "perfect_night" => { text: "A perfect night for me is…", category: "dating" },
      "win_me_over" => { text: "The quickest way to win me over…", category: "dating" },
      "green_flag" => { text: "My biggest green flag is…", category: "personality" },
      "the_vibe" => { text: "The vibe I bring is…", category: "personality" },
      "find_me" => { text: "You'll usually find me…", category: "lifestyle" },
      "toxic_trait" => { text: "My toxic trait is…", category: "fun" },
      "ideal_first_meet" => { text: "My ideal first meet is…", category: "dating" },
      "cannot_stop" => { text: "I cannot stop talking about…", category: "conversation" },
      "random_love" => { text: "A random thing I love…", category: "fun" },
      "weekend_plan" => { text: "My ideal weekend looks like…", category: "lifestyle" },
      "geek_out" => { text: "I geek out about…", category: "conversation" },
      "make_me_laugh" => { text: "The fastest way to make me laugh…", category: "fun" },
      "unwind" => { text: "I unwind by…", category: "lifestyle" },
      "two_truths" => { text: "Two truths and a lie…", category: "fun" },
      "looking_for" => { text: "Right now I'm looking for…", category: "dating" },
      "dealbreaker" => { text: "A dealbreaker for me is…", category: "dating" },
      "guilty_pleasure" => { text: "My guilty pleasure is…", category: "fun" },
      "adventure" => { text: "The most spontaneous thing I've done…", category: "spontaneity" }
    }.freeze

    class UnknownCapability < StandardError; end

    class << self
      # Enable one generic controlled-vocabulary capability for a brand, with
      # optional per-brand overrides. `only` restricts to a subset of the defined
      # option codes (defaults to all), preserving the catalogue's order.
      def enable_option_capability!(brand:, key:, position:, label: nil, visibility: nil, cardinality: nil,
        max_selections: nil, only: nil, option_labels: {})
        definition = OPTION_CAPABILITIES.fetch(key) { raise UnknownCapability, key }
        codes = only ? definition.fetch(:options).slice(*only) : definition.fetch(:options)

        install_option_group!(
          brand:, key:, position:,
          label: label || definition.fetch(:label),
          cardinality: cardinality || definition.fetch(:cardinality),
          max_selections: max_selections || definition.fetch(:max_selections),
          visibility: visibility || definition.fetch(:visibility),
          # Per-option label overrides let a brand relabel a value (e.g. "friendly"
          # => "420 friendly") without ever changing the stable code.
          options: codes.map { |code, option_label| { code:, label: option_labels.fetch(code, option_label) } }
        )
      end

      # Enable the interests taxonomy for a brand. `only` (codes) and `categories`
      # both narrow the offered set; combine to taste.
      def enable_interests!(brand:, position:, label: nil, visibility: nil, max_selections: nil, only: nil, categories: nil)
        options = INTERESTS.fetch(:options)
        options = options.select { |option| only.include?(option.fetch(:code)) } if only
        options = options.select { |option| categories.include?(option.fetch(:category)) } if categories

        install_option_group!(
          brand:, key: INTERESTS.fetch(:key), position:,
          label: label || INTERESTS.fetch(:label),
          cardinality: INTERESTS.fetch(:cardinality),
          max_selections: max_selections || INTERESTS.fetch(:max_selections),
          visibility: visibility || INTERESTS.fetch(:visibility),
          options:
        )
      end

      # Enable a subset of generic prompts for a brand (stable keys, editable copy).
      def enable_prompts!(brand:, keys:, start_position: 0, overrides: {})
        keys.each_with_index do |key, index|
          definition = PROMPTS.fetch(key) { raise UnknownCapability, key }
          override = overrides.fetch(key, {})
          install_prompt!(
            brand:, key:, position: start_position + index,
            text: override[:text] || definition.fetch(:text),
            category: override[:category] || definition[:category]
          )
        end
      end

      # Low-level, idempotent option-group upsert. Reusable by brand catalogues to
      # install BRAND-SPECIFIC groups too (not just generic capabilities), so the
      # upsert lives in exactly one place. `options` is an array of
      # { code:, label:, category?: }.
      def install_option_group!(brand:, key:, label:, cardinality:, max_selections:, visibility:, options:, position:)
        group = brand.profile_option_groups.kept.find_or_initialize_by(key:)
        group.update!(label:, cardinality:, max_selections:, visibility:, status: :active, position:)

        options.each_with_index do |definition, index|
          option = group.profile_options.kept.find_or_initialize_by(code: definition.fetch(:code))
          option.update!(
            brand:, label: definition.fetch(:label), category: definition[:category],
            status: :active, position: index
          )
        end

        group
      end

      # Low-level, idempotent prompt-definition upsert.
      def install_prompt!(brand:, key:, text:, category:, position:)
        prompt = brand.profile_prompts.kept.find_or_initialize_by(key:)
        prompt.update!(text:, category:, status: :active, position:)
        prompt
      end
    end
  end
end
