require "digest"

module Profiles
  module DemoSeed
    # Deterministic, CURATED profile content for a seeded person.
    #
    # Everything here is repeatable: the same person always yields the same bio,
    # city, interests and activity state, derived from a stable hash of their seed
    # key. Copy is hand-written (not runtime-generated) and drawn from varied pools
    # so the demo population reads like real, uneven people — some with a job and a
    # school and three prompts, many with far less. No value is invented outside
    # the brand's configured taxonomy; option codes below all exist in
    # Profiles::CapabilityCatalog / HookusProfileCatalog.
    class Content
      # A candidate is configured to be discoverable by any viewer whose OWN
      # preferences point at their gender: the seed never blocks a viewer from its
      # side. It lists every viewer gender in `interested_in`, keeps a wide age band
      # and no distance cap, so the reciprocal gender/age/distance gates in
      # Matching::EligibilityScope always pass on the candidate's side. The viewer's
      # own (unmodified) preferences still decide the rest — no discovery code or
      # real user is touched. See the rake task's completion notes.
      INTERESTED_IN = %w[ man woman person nonbinary ].freeze
      PREFERENCE_MIN_AGE = 18
      PREFERENCE_MAX_AGE = 99

      # city, country, latitude, longitude — plausible SA metros/suburbs.
      CITIES = [
        [ "Cape Town", "ZA", -33.9249, 18.4241 ],
        [ "Sea Point", "ZA", -33.9142, 18.3846 ],
        [ "Milnerton", "ZA", -33.8747, 18.4939 ],
        [ "Bellville", "ZA", -33.8986, 18.6292 ],
        [ "Stellenbosch", "ZA", -33.9321, 18.8602 ],
        [ "Johannesburg", "ZA", -26.2041, 28.0473 ],
        [ "Sandton", "ZA", -26.1076, 28.0567 ],
        [ "Rosebank", "ZA", -26.1467, 28.0436 ],
        [ "Pretoria", "ZA", -25.7479, 28.2293 ],
        [ "Centurion", "ZA", -25.8603, 28.1894 ],
        [ "Durban", "ZA", -29.8587, 31.0218 ],
        [ "Gqeberha", "ZA", -33.9608, 25.6022 ]
      ].freeze

      # Bios carry PERSONALITY only — deliberately free of a specific city or a hard
      # profession, since those live in the structured `city`/`occupation` fields
      # (assigned independently). Keeping them out of the copy avoids a Pretoria
      # profile that opens with "Cape Town girl". SA tone stays via braais,
      # amapiano, biltong, rugby, load-shedding rather than place names.
      LADIES_BIOS = [
        "Somewhere between work, the gym, and pretending I don't need another flat white.",
        "Quiet during the week, out on weekends. Here to meet people, not collect matches.",
        "I cook properly, not just two-minute noodles. Apparently that's rare.",
        "Long walks, bad reality TV, good wine. That's the whole pitch.",
        "My sleep schedule is a mess and my playlist is worse. Come along anyway.",
        "Still can't parallel park. Otherwise fairly capable.",
        "I laugh too loud and I'm not sorry. Bring snacks.",
        "Spreadsheets by day, amapiano by night. It balances out.",
        "Point me to good food and we'll get along just fine.",
        "Low-key homebody who occasionally gets talked into a night out.",
        "Patient with kids, less so with slow walkers. Sorry in advance.",
        "I run so I can eat the pizza guilt-free. Working system.",
        "Big reader, small talker. Warm up fast once I trust you.",
        "Family girl, weekend hiker, terrible at replying quickly.",
        "Weekdays are busy, Saturdays are for markets and doing nothing.",
        "I'll judge your coffee order and then order the exact same thing.",
        "Beach person. Always slightly sandy, no regrets.",
        "I'll fix your posture and roast your gym form, all for free.",
        "Chatty, curious, and far too invested in true-crime podcasts.",
        "Wine has ruined me for cheap bottles. Worth it.",
        "More fun than my job title suggests. Marginally.",
        "I plan holidays I don't take and cook recipes I actually do.",
        "Softie with a sharp sense of humour. Both are real.",
        "Busy week, quiet weekend. I need the reset to function.",
        "Broke but well-read, which has to count for something.",
        "I dance badly and confidently. That part's non-negotiable.",
        "Dog mum first, everything else a distant second.",
        "Not on here much. If we click, let's just grab a coffee.",
        "Loud family, quiet apartment. I genuinely like both.",
        "Yoga in the morning, wine in the evening. Consistency is key.",
        "Down to earth, up for most things at least once.",
        "I remember every birthday and forget where I parked. Fair trade.",
        "Curious about people. Ask me the weird questions.",
        "Half my camera roll is food, the other half is my niece."
      ].freeze

      GUYS_BIOS = [
        "Football, braais, and badly planned road trips. In that order.",
        "Still figuring out which spots around here are actually worth it.",
        "A bit private at first. Much less boring once I know you.",
        "I fix things at work and overthink them at home. Balanced guy.",
        "Gym in the morning so I can eat like it never happened.",
        "Trail runs, cold water, warmer company. That's the plan.",
        "I make a serious braai and a mediocre playlist. Come for the food.",
        "Quiet, dry sense of humour. Grows on you, or it doesn't.",
        "Ocean, curry, and Sunday afternoons doing absolutely nothing.",
        "Endless patience and genuinely questionable dance moves.",
        "Busy, but never too busy for someone worth the time.",
        "I'll lose the football argument and win the one about music.",
        "Family guy, weekend hiker, loyal to a fault.",
        "I notice the small things. Occasionally that's charming.",
        "I feed people I like. Make of that what you will.",
        "Weekdays in the city, weekends up a mountain if I can swing it.",
        "Reformed night owl. Still up too late, just guiltier about it.",
        "Rugby, more rugby, and pretending I could still play.",
        "Bad at replying, good at showing up. It evens out.",
        "Wine, dogs, and long lunches that ruin the whole afternoon.",
        "Low drama, high effort. I'd rather do than talk about doing.",
        "Music on the side, the real job pays the rent. One of them's fun.",
        "Beach, biltong, and a car that only just passes its roadworthy.",
        "I'm the friend who plans the whole trip. Someone has to."
      ].freeze

      OCCUPATIONS = [
        "Marketing", "Nurse", "Teacher", "Software developer", "Accountant",
        "Graphic designer", "Physiotherapist", "Chef", "Photographer",
        "Project manager", "Architect", "Financial analyst", "Copywriter",
        "Civil engineer", "Doctor", "Estate agent", "Sound engineer", "Barista"
      ].freeze

      SCHOOLS = [
        "University of Cape Town", "University of the Witwatersrand",
        "Stellenbosch University", "University of Pretoria",
        "University of KwaZulu-Natal", "Nelson Mandela University",
        "Rhodes University", "Cape Peninsula University of Technology"
      ].freeze

      LANGUAGE_CODES = %w[ af zu xh pt fr ].freeze
      RELATIONSHIP_INTENTS = [ "seeing what happens", "open to dating", "keeping it casual", "no rush" ].freeze
      BODY_TYPES = %w[ athletic slim average curvy muscular ].freeze
      LIFESTYLE_LEVELS = %w[ never occasionally regularly ].freeze

      # Single-select capability groups → their valid option codes.
      SINGLE_OPTION_GROUPS = {
        "diet" => %w[ anything vegetarian vegan pescatarian halal ],
        "pet_preference" => %w[ have_pets love_pets no_pets allergic ],
        "sleep_schedule" => %w[ early_bird night_owl flexible ],
        "social_energy" => %w[ homebody balanced always_out ],
        "social_style" => %w[ introverted ambivert extroverted depends_on_the_vibe ],
        "communication_style" => %w[ texting voice_notes calls in_person mixed ],
        "planning_style" => %w[ planner spontaneous mix_of_both ],
        "travel_frequency" => %w[ rarely sometimes often ],
        "preferred_time_of_day" => %w[ daytime evening late_night flexible ],
        "meeting_pace" => %w[ chat_first few_days meet_soon same_day_if_vibe_is_right go_with_the_flow ],
        "education_level" => %w[ vocational some_college undergraduate postgraduate ]
      }.freeze
      LIFESTYLE_KEYS = SINGLE_OPTION_GROUPS.keys.freeze
      PETS_OPTIONS = %w[ dog cat bird fish small_pet ].freeze
      # Skewed so most people are NOT cannabis-forward (see task: don't make
      # everyone 420 friendly).
      CANNABIS_VALUES = %w[ never never sometimes curious socially friendly ].freeze

      INTENT_CODES = %w[ hookups casual dating_vibes 420_chill nightlife relationship travel just_looking ].freeze
      VIBE_CODES = %w[
        420_friendly drinks nightlife raves music travel beach gaming fitness pets
        creative night_owl chill smoke_free foodie
      ].freeze
      INTEREST_CODES = %w[
        foodie restaurants cooking coffee wine cocktails brunch live_music festivals
        afrobeats amapiano hip_hop rnb house_music karaoke travel road_trips beach camping
        hiking nature cycling gym running yoga pilates football basketball rugby cricket
        tennis nightlife dancing bars gaming esports movies anime reading podcasts tv_series
        art photography fashion writing museums theatre history meditation spa board_games
        spontaneous_plans
      ].freeze

      PROMPT_ANSWERS = {
        "perfect_night" => [
          "Good food, no plan, and nowhere we have to be by nine.",
          "Braai, a decent playlist, and everyone leaving on time.",
          "Takeout, a series we're both behind on, phones face down.",
          "Rooftop drinks then somewhere loud enough to dance.",
          "Home by ten with wine and zero obligations."
        ],
        "win_me_over" => [
          "Be on time and have an opinion about something.",
          "Feed me and let me pick the music.",
          "Make me laugh before you make me think.",
          "Confidence without the loud part.",
          "Remember the small thing I mentioned once."
        ],
        "the_vibe" => [
          "Calm until there's a reason not to be.",
          "Low effort to be around, high effort when it counts.",
          "A bit sarcastic, mostly kind.",
          "Chill with the occasional bit of chaos.",
          "Warm, blunt, easy to talk to."
        ],
        "find_me" => [
          "At the gym or explaining why I skipped it.",
          "In the kitchen or the queue at a coffee shop.",
          "On a trail or on the couch, no in-between.",
          "At a market buying things I don't need.",
          "Overpacking for a weekend away."
        ],
        "ideal_first_meet" => [
          "Coffee that turns into a walk if it's going well.",
          "A drink somewhere we can actually hear each other.",
          "Something casual. Skip the fancy dinner.",
          "A market on a Saturday, low pressure.",
          "Sunset drinks, easy exit if we don't click."
        ],
        "cannot_stop" => [
          "The last trip I took and the next one I'm planning.",
          "A show I've now made everyone watch.",
          "Why my team keeps breaking my heart.",
          "Food. Specifically, where we should eat next.",
          "A podcast I'm far too invested in."
        ],
        "random_love" => [
          "The smell of rain on a hot day.",
          "A perfectly timed voice note.",
          "People-watching at the airport.",
          "Handwriting somehow worse than mine.",
          "Playlists made by other people."
        ],
        "make_me_laugh" => [
          "Bad puns delivered with full confidence.",
          "Dry sarcasm, no warning.",
          "A well-timed meme mid-conversation.",
          "Impressions you can't actually do.",
          "Being honest about something embarrassing."
        ],
        "guilty_pleasure" => [
          "Reality TV I pretend to hate.",
          "Fast food after the gym. Balance.",
          "Reading the last page first.",
          "Singing badly in the car, windows up.",
          "Naps that ruin my night's sleep."
        ],
        "toxic_trait" => [
          "I reply fast or in three business days, no middle.",
          "I reorganise the dishwasher you 'already loaded'.",
          "I'm always right about restaurants, never about time.",
          "I start series I'll never finish.",
          "I say 'one drink' and mean it, occasionally."
        ],
        "green_flag" => [
          "I text back. Eventually, but I do.",
          "Good with waiters and grandparents.",
          "I say what I mean without the drama.",
          "I show up when I say I will.",
          "I split the bill without the awkward dance."
        ],
        "adventure" => [
          "Booked a flight the night before, no regrets.",
          "Swam somewhere I definitely shouldn't have.",
          "Drove six hours for a specific meal.",
          "Said yes to a hike that turned out to be a mountain.",
          "Moved cities on a maybe."
        ]
      }.freeze
      PROMPT_KEYS = PROMPT_ANSWERS.keys.freeze

      Result = Data.define(
        :birthdate, :profile, :preference, :options, :prompts, :location, :activity,
        :verified, :new_here
      )

      def self.for(person, index:)
        new(person, index).call
      end

      def initialize(person, index)
        @person = person
        @index = index
        @lady = person.gender == "woman"
      end

      def call
        Result.new(
          birthdate: birthdate,
          profile: profile_attributes,
          preference: preference_attributes,
          options: option_selections,
          prompts: prompt_answers,
          location: location_attributes,
          activity: activity_state,
          verified: chance(:verified, 55),
          new_here: chance(:new_here, 30)
        )
      end

      private

      attr_reader :person, :index

      # A synthetic-but-deterministic birthday that always renders as the folder
      # age: `age` years ago minus a stable 10–330 day offset, so the most recent
      # birthday has already passed and the displayed age equals `age` exactly.
      def birthdate
        offset = 10 + (h(:dob) % 320)
        (person.age.years.ago.to_date - offset)
      end

      def profile_attributes
        city, country, = city_row
        {
          display_name: person.display_name,
          bio: bio,
          gender: person.gender,
          country_code: country,
          city: city,
          occupation: maybe(:occupation, 70) { pick(OCCUPATIONS, :occupation) },
          school_or_institution: maybe(:school, 40) { pick(SCHOOLS, :school) },
          looking_for_text: maybe(:looking_for, 35) { pick(RELATIONSHIP_INTENTS, :looking_for).capitalize },
          pronouns: @lady ? maybe(:pronouns, 25) { "she/her" } : maybe(:pronouns, 20) { "he/him" },
          height_cm: maybe(:height, 55) { height },
          body_type: maybe(:body_type, 45) { pick(BODY_TYPES, :body_type) },
          smoking: maybe(:smoking, 45) { pick(LIFESTYLE_LEVELS, :smoking) },
          drinking: maybe(:drinking, 60) { pick(LIFESTYLE_LEVELS, :drinking) },
          fitness: maybe(:fitness, 60) { pick(LIFESTYLE_LEVELS, :fitness) },
          languages: languages
        }
      end

      def preference_attributes
        {
          interested_in: INTERESTED_IN,
          min_age: PREFERENCE_MIN_AGE,
          max_age: PREFERENCE_MAX_AGE,
          max_distance_km: nil,
          relationship_intent: maybe(:rel_intent, 40) { pick(RELATIONSHIP_INTENTS, :rel_intent) }
        }
      end

      def option_selections
        selections = {
          "intents" => sample(INTENT_CODES, :intents, min: 1, max: 3),
          "vibes" => sample(VIBE_CODES, :vibes, min: 2, max: 5),
          "interests" => sample(INTEREST_CODES, :interests, min: 3, max: 7)
        }
        chosen_lifestyle_keys.each do |key|
          selections[key] = [ pick(SINGLE_OPTION_GROUPS.fetch(key), :"opt_#{key}") ]
        end
        selections["pets"] = sample(PETS_OPTIONS, :pets, min: 1, max: 2) if chance(:has_pets, 35)
        selections["cannabis"] = [ pick(CANNABIS_VALUES, :cannabis) ] if chance(:has_cannabis, 40)
        selections
      end

      def chosen_lifestyle_keys
        count = 3 + (h(:lifestyle_count) % 5) # 3..7 lifestyle groups
        LIFESTYLE_KEYS.sort_by { |key| h(:"life_#{key}") }.first(count)
      end

      def prompt_answers
        count = prompt_count
        return [] if count.zero?

        PROMPT_KEYS.sort_by { |key| h(:"prompt_#{key}") }.first(count).map do |key|
          answers = PROMPT_ANSWERS.fetch(key)
          { key: key, answer: answers[(index + h(:"pa_#{key}")) % answers.size] }
        end
      end

      # 0..3 prompts, most people with 0–1.
      def prompt_count
        roll = h(:prompt_count) % 100
        return 0 if roll < 30
        return 1 if roll < 60
        return 2 if roll < 85

        3
      end

      def location_attributes
        _, _, latitude, longitude = city_row
        # A small deterministic jitter (~±0.03°, a few km) so seeded members don't
        # stack on identical coordinates within a city.
        {
          latitude: latitude + ((h(:lat) % 61) - 30) / 1000.0,
          longitude: longitude + ((h(:lng) % 61) - 30) / 1000.0
        }
      end

      # Distribution: some online now, some active today, some this week, the rest
      # dormant — so the demo population isn't uniformly "online".
      def activity_state
        roll = h(:activity) % 100
        return :online if roll < 20
        return :active_today if roll < 45
        return :this_week if roll < 65

        :inactive
      end

      def bio
        pool = @lady ? LADIES_BIOS : GUYS_BIOS
        pool[index % pool.size]
      end

      def languages
        extras = LANGUAGE_CODES.sort_by { |code| h(:"lang_#{code}") }.first(h(:lang_count) % 3) # 0..2 extras
        codes = [ "en" ] + extras
        codes.each_with_index.map do |code, position|
          { "code" => code, "primary" => position.zero?,
            "proficiency" => position.zero? ? "native" : pick(%w[ fluent conversational ], :"prof_#{code}") }
        end
      end

      def height
        @lady ? 155 + (h(:height) % 24) : 168 + (h(:height) % 25)
      end

      def city_row
        CITIES[h(:city) % CITIES.size]
      end

      # --- deterministic helpers (stable per seed key) ---------------------------

      def h(salt)
        Digest::MD5.hexdigest("#{salt}:#{person.seed_key}")[0, 12].to_i(16)
      end

      def chance(salt, percent)
        (h(salt) % 100) < percent
      end

      def maybe(salt, percent)
        chance(salt, percent) ? yield : nil
      end

      def pick(pool, salt)
        pool[h(salt) % pool.size]
      end

      # Deterministic subset of `pool` of size min..max, order-stable.
      def sample(pool, salt, min:, max:)
        span = max - min + 1
        count = min + (h(:"count_#{salt}") % span)
        pool.sort_by { |item| h(:"#{salt}_#{item}") }.first(count)
      end
    end
  end
end
