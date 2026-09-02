require "set"

module LoadTesting
  class SyntheticDataset
    class SafetyError < StandardError; end
    class ConfigurationError < StandardError; end

    DATASET = "d8n_load_test_v1"
    DEFAULT_COUNT = 3_000
    MAX_COUNT = 5_000
    EMAIL_FORMAT = "loadtest-user-%06d@example.invalid"
    EMAIL_PATTERN = "^loadtest-user-[0-9]{6}@example[.]invalid$"
    STAGING_HOST = "staging-api.d8n.tech"
    CREATE_CONFIRMATION = "CREATE_D8N_SYNTHETIC_USERS_ON_STAGING"
    CLEANUP_CONFIRMATION = "DELETE_D8N_SYNTHETIC_USERS_FROM_STAGING"
    TAG = { "synthetic" => true, "dataset" => DATASET }.freeze

    NIGERIAN_LOCATIONS = [
      { city: "Lagos", country: "NG", latitude: 6.5244, longitude: 3.3792 },
      { city: "Abuja", country: "NG", latitude: 9.0765, longitude: 7.3986 },
      { city: "Port Harcourt", country: "NG", latitude: 4.8156, longitude: 7.0498 },
      { city: "Enugu", country: "NG", latitude: 6.4584, longitude: 7.5464 },
      { city: "Owerri", country: "NG", latitude: 5.4891, longitude: 7.0176 },
      { city: "Ibadan", country: "NG", latitude: 7.3775, longitude: 3.9470 },
      { city: "Benin City", country: "NG", latitude: 6.3350, longitude: 5.6037 }
    ].freeze
    DIASPORA_LOCATIONS = [
      { city: "Johannesburg", country: "ZA", latitude: -26.2041, longitude: 28.0473 },
      { city: "Cape Town", country: "ZA", latitude: -33.9249, longitude: 18.4241 },
      { city: "London", country: "GB", latitude: 51.5072, longitude: -0.1276 },
      { city: "Toronto", country: "CA", latitude: 43.6532, longitude: -79.3832 },
      { city: "Atlanta", country: "US", latitude: 33.7490, longitude: -84.3880 },
      { city: "Houston", country: "US", latitude: 29.7604, longitude: -95.3698 },
      { city: "Dublin", country: "IE", latitude: 53.3498, longitude: -6.2603 }
    ].freeze
    NAMES = %w[
      Ada Amaka Amina Bisola Chioma Chisom Damilola Efe Esther Fatima Ifeoma Imani Kemi
      Lerato Maya Nneka Ngozi Rukayat Sade Temi Yewande Zainab Chidi Chinedu David Dele
      Ebuka Emeka Femi Idris Ikechukwu Kunle Malik Musa Obinna Segun Tayo Uche Wale Yemi
    ].freeze
    OCCUPATIONS = [
      "Accountant", "Architect", "Chef", "Consultant", "Designer", "Developer",
      "Doctor", "Entrepreneur", "Engineer", "Lawyer", "Lecturer", "Nurse",
      "Photographer", "Product manager", "Teacher", "Trader", "Writer"
    ].freeze
    BIOS = [
      "Good conversation, good food, and a reason to put the phone away.",
      "Usually planning a weekend trip or finding a new place to eat.",
      "Calm energy, ambitious plans, and an unreasonable love of playlists.",
      "Here to meet someone kind, curious, and able to laugh at themselves.",
      "Work hard, rest properly, and never skip the jollof debate.",
      "I like live music, long walks, and people who communicate clearly.",
      "Equal parts homebody and last-minute adventure partner.",
      "Looking for chemistry without unnecessary drama."
    ].freeze
    LANGUAGES = %w[English Igbo Yoruba Hausa Pidgin French Afrikaans].freeze
    INTENTS = %w[hookups casual dating_vibes nightlife relationship travel just_looking].freeze
    VIBES = %w[
      420_friendly drinks nightlife raves music travel beach gaming fitness pets creative
      night_owl chill smoke_free foodie
    ].freeze

    Result = Data.define(
      :users,
      :profiles,
      :brand_memberships,
      :locations,
      :likes,
      :passes,
      :matches,
      :active_profiles,
      :draft_profiles
    )

    def self.synthetic_identifiers
      IdentityIdentifier.kept.email
        .where("normalized_value ~ ?", EMAIL_PATTERN)
        .where("metadata @> ?::jsonb", TAG.to_json)
    end

    def initialize(
      brand_slug: "hookus",
      count: DEFAULT_COUNT,
      password: nil,
      seed: 20_260_814,
      environment: Rails.env,
      env: ENV,
      output: $stdout
    )
      @brand_slug = brand_slug
      @count = Integer(count)
      @password = password
      @seed = Integer(seed)
      @environment = environment.to_s
      @env = env
      @output = output
    end

    def create!
      guard!(:create)
      validate_create_configuration!
      prepare_brand!
      validate_catalog!
      refuse_larger_existing_dataset!

      shared_password_hash = nil
      indexes.each_slice(100) do |batch|
        ApplicationRecord.transaction do
          batch.each do |index|
            credential = create_account!(index)
            shared_password_hash ||= create_shared_password_hash!(credential)
            apply_shared_password_hash!(credential, shared_password_hash)
            create_profile!(index, credential.user)
          end
        end
        output.puts("synthetic accounts ready: #{batch.last}/#{count}")
      end

      create_activity!
      report
    end

    def cleanup!
      guard!(:cleanup)
      load_brand!

      identifiers = synthetic_identifiers.where(user_id: brand.users.select(:id))
      user_ids = identifiers.pluck(:user_id)
      return report if user_ids.empty?

      ensure_exclusively_synthetic_identities!(identifiers:, user_ids:)
      profile_ids = Profile.where(user_id: user_ids).pluck(:id)
      credential_ids = Credential.where(user_id: user_ids).pluck(:id)
      identifier_ids = identifiers.pluck(:id)
      ensure_no_synthetic_media!(profile_ids)

      ApplicationRecord.transaction do
        # Analytics events reference profiles, users and sessions with restricting
        # foreign keys, so they must go before any of those rows (create_activity!
        # emits them via Matching/Messaging). delete_all, not destroy_all — the
        # model is append-only and raises on #destroy.
        AnalyticsEvent.where(user_id: user_ids)
          .or(AnalyticsEvent.where(profile_id: profile_ids)).delete_all
        delete_relationships!(profile_ids)
        delete_identity_activity!(user_ids:, credential_ids:, identifier_ids:)
        ProfileOptionSelection.where(profile_id: profile_ids).delete_all
        ProfileLocation.where(profile_id: profile_ids).delete_all
        ProfilePreference.where(profile_id: profile_ids).delete_all
        Profile.where(id: profile_ids).delete_all
        CredentialPasswordHash.where(credential_id: credential_ids).delete_all
        Credential.where(id: credential_ids).delete_all
        IdentityIdentifier.where(id: identifier_ids).delete_all
        BrandMembership.where(user_id: user_ids).delete_all
        User.where(id: user_ids).delete_all
      end

      report
    end

    def report
      load_brand!
      user_ids = synthetic_identifiers.where(user_id: brand.users.select(:id)).select(:user_id)
      profile_scope = Profile.where(brand:, user_id: user_ids)
      profile_ids = profile_scope.select(:id)

      Result.new(
        users: User.where(id: user_ids).count,
        profiles: profile_scope.count,
        brand_memberships: BrandMembership.where(brand:, user_id: user_ids).count,
        locations: ProfileLocation.where(profile_id: profile_ids).count,
        likes: Like.where("liker_profile_id IN (?) OR liked_profile_id IN (?)", profile_ids, profile_ids).count,
        passes: ProfilePass.where("passer_profile_id IN (?) OR passed_profile_id IN (?)", profile_ids, profile_ids).count,
        matches: Match.where("profile_a_id IN (?) OR profile_b_id IN (?)", profile_ids, profile_ids).count,
        active_profiles: profile_scope.active.visible.count,
        draft_profiles: profile_scope.draft.count
      )
    end

    private

    attr_reader :brand_slug, :count, :password, :seed, :environment, :env, :output, :brand

    def guard!(action)
      return if %w[development test].include?(environment)

      expected = action == :create ? CREATE_CONFIRMATION : CLEANUP_CONFIRMATION
      allowed = environment == "production" && env["D8N_LOAD_TEST_TARGET"] == STAGING_HOST &&
        env["D8N_LOAD_TEST_CONFIRM"] == expected
      return if allowed

      raise SafetyError,
        "synthetic #{action} is disabled outside development/test; staging requires " \
          "D8N_LOAD_TEST_TARGET=#{STAGING_HOST} and D8N_LOAD_TEST_CONFIRM=#{expected}"
    end

    def validate_create_configuration!
      raise ConfigurationError, "count must be between 1 and #{MAX_COUNT}" unless count.between?(1, MAX_COUNT)
      raise ConfigurationError, "D8N_LOAD_TEST_PASSWORD is required" if password.blank?
      raise ConfigurationError, "load-test password does not meet D8N requirements" unless Identity::PasswordEngine.valid?(password:)
    end

    def load_brand!
      return @brand if @brand

      @brand = Brand.kept.active.find_by!(slug: brand_slug)
      if environment == "production" && !brand.brand_domains.kept.active.exists?(host: STAGING_HOST)
        raise SafetyError, "#{brand.slug} is not mapped to the required staging host"
      end

      @brand
    end

    def prepare_brand!
      @brand = Brand.kept.active.find_by(slug: brand_slug)
      if @brand.nil?
        if environment == "production" && brand_slug != "hookus"
          raise ConfigurationError, "staging synthetic data may provision only the hookus brand"
        end

        @brand = Brand.create!(slug: brand_slug, name: brand_slug == "hookus" ? "HookUs" : brand_slug.titleize)
      end

      Profiles::HookusProfileCatalog.install!(brand:) if brand.slug == "hookus"
      ensure_staging_domain! if environment == "production"
      brand
    end

    def ensure_staging_domain!
      domain = BrandDomain.kept.find_by(host: STAGING_HOST)
      if domain && domain.brand_id != brand.id
        raise ConfigurationError, "#{STAGING_HOST} already belongs to another brand"
      end

      domain ||= BrandDomain.new(host: STAGING_HOST, brand:)
      domain.update!(status: :active, deleted_at: nil)
    end

    def validate_catalog!
      catalog = brand.profile_option_groups.kept.status_active.includes(:profile_options).index_by(&:key)
      expected = { "intents" => INTENTS, "vibes" => VIBES }
      missing = expected.filter_map do |key, codes|
        group = catalog[key]
        key if group.blank? || (codes - group.profile_options.select(&:status_active?).map(&:code)).any?
      end
      return if missing.empty?

      raise ConfigurationError, "HookUs profile catalog is incomplete: #{missing.join(', ')}"
    end

    def refuse_larger_existing_dataset!
      existing_numbers = synthetic_identifiers.pluck(:normalized_value).filter_map do |email|
        email[/\Aloadtest-user-(\d{6})@example\.invalid\z/, 1]&.to_i
      end
      return unless existing_numbers.any? { |number| number > count }

      raise ConfigurationError,
        "a larger synthetic dataset already exists; clean it before creating only #{count} users"
    end

    def indexes
      1..count
    end

    def create_account!(index)
      email = format(EMAIL_FORMAT, index)
      identifier = IdentityIdentifier.kept.email.find_by(normalized_value: email)
      if identifier && identifier.metadata.slice(*TAG.keys) != TAG
        raise ConfigurationError, "identifier collision for #{email}; existing record is not tagged synthetic"
      end

      user = identifier&.user || User.create!(status: :active)
      user.update!(status: :active, deleted_at: nil)
      identifier ||= user.identity_identifiers.create!(
        kind: :email,
        normalized_value: email,
        metadata: TAG,
        verified_at: nil,
        last_seen_at: Time.current
      )
      identifier.update!(metadata: identifier.metadata.merge(TAG), deleted_at: nil)

      credential = Credential.kept.find_or_initialize_by(
        user:,
        identity_identifier: identifier,
        kind: :password
      )
      credential.update!(status: :active, verified_at: nil, deleted_at: nil)
      membership = BrandMembership.kept.find_or_initialize_by(user:, brand:)
      membership.update!(status: :active, deleted_at: nil)
      credential
    end

    def create_shared_password_hash!(credential)
      Identity::PasswordEngine.set!(credential:, password:)
      credential.reload.credential_password_hash.password_hash
    end

    def apply_shared_password_hash!(credential, shared_password_hash)
      password_record = CredentialPasswordHash.find_or_initialize_by(credential:)
      password_record.update!(
        credential_kind: Credential.kinds.fetch("password"),
        password_hash: shared_password_hash,
        password_changed_at: Time.current
      )
    end

    def create_profile!(index, user)
      details = profile_details(index)
      profile = Profiles::CurrentProfile.upsert!(
        user:,
        brand:,
        attributes: details.fetch(:profile).merge(metadata: TAG)
      )
      Profiles::CurrentPreferences.upsert!(
        user:,
        brand:,
        attributes: details.fetch(:preferences).merge(metadata: TAG)
      )
      Profiles::OptionSelections.replace!(profile:, selections: details.fetch(:options))
      update_location!(index:, user:, profile:, location: details.fetch(:location))

      if complete_index?(index)
        Profiles::Publication.activate!(user:, brand:)
      else
        Profiles::Publication.deactivate!(user:, brand:)
      end
    end

    def profile_details(index)
      random = Random.new(seed + index)
      location = location_for(index, random)
      gender = gender_for(index)
      age = age_for(index, random)
      interested_in = interested_in_for(index, gender)
      complete = complete_index?(index)

      {
        profile: {
          display_name: "#{NAMES[index % NAMES.length]} LT#{format('%04d', index)}",
          bio: complete || index.even? ? BIOS[index % BIOS.length] : nil,
          birthdate: age.years.ago.to_date - random.rand(0..364).days,
          gender:,
          country_code: location.fetch(:country),
          city: location.fetch(:city),
          occupation: OCCUPATIONS[index % OCCUPATIONS.length],
          height_cm: 150 + random.rand(0..45),
          body_type: %w[slim average athletic curvy plus_size][index % 5],
          languages_spoken: languages_for(index),
          smoking: %w[never never never occasionally regularly][index % 5],
          drinking: %w[never occasionally occasionally regularly][index % 4],
          fitness: %w[never occasionally regularly occasionally][index % 4]
        },
        preferences: {
          min_age: [ Profile::MINIMUM_AGE, age - 8 - (index % 4) ].max,
          max_age: [ 65, age + 10 + (index % 5) ].min,
          interested_in:,
          max_distance_km: [ nil, nil, 25, 50, 100, 250 ][index % 6],
          country: index % 4 == 0 ? nil : location.fetch(:country),
          relationship_intent: %w[casual dating relationship open_to_seeing][index % 4]
        },
        options: options_for(index, complete),
        location: index % 10 == 0 ? nil : location
      }
    end

    def location_for(index, random)
      locations = index % 4 == 0 ? DIASPORA_LOCATIONS : NIGERIAN_LOCATIONS
      base = locations[index % locations.length]
      base.merge(
        latitude: base.fetch(:latitude) + random.rand(-0.035..0.035),
        longitude: base.fetch(:longitude) + random.rand(-0.035..0.035)
      )
    end

    def gender_for(index)
      percentile = index % 100
      return "woman" if percentile < 47
      return "man" if percentile < 94

      "nonbinary"
    end

    def age_for(index, random)
      index % 10 < 8 ? random.rand(18..44) : random.rand(45..60)
    end

    def interested_in_for(index, gender)
      return %w[woman man nonbinary] if gender == "nonbinary" || index % 5 == 0
      return [ gender ] if index % 7 == 0

      [ gender == "woman" ? "man" : "woman" ]
    end

    def languages_for(index)
      primary = index % 4 == 0 ? "English" : %w[Igbo Yoruba Hausa Pidgin][index % 4]
      [ "English", primary, LANGUAGES[index % LANGUAGES.length] ].uniq
    end

    def options_for(index, complete)
      intent_count = 1 + (index % 3)
      vibe_count = 2 + (index % 5)
      {
        "intents" => complete || index.even? ? INTENTS.rotate(index).first(intent_count) : [],
        "vibes" => complete || index % 3 != 0 ? VIBES.rotate(index).first(vibe_count) : []
      }
    end

    def complete_index?(index)
      index % 20 >= 3
    end

    def update_location!(index:, user:, profile:, location:)
      if location
        Profiles::CurrentLocation.upsert!(
          user:,
          brand:,
          attributes: {
            latitude: location.fetch(:latitude),
            longitude: location.fetch(:longitude),
            accuracy_meters: 100 + (index % 2_000),
            captured_at: index % 11 == 0 ? 2.days.ago : Time.current
          }
        )
      elsif ProfileLocation.kept.exists?(profile:)
        Profiles::CurrentLocation.soft_delete!(user:, brand:)
      end
    end

    def create_activity!
      profiles = Profile.where(brand:, user_id: synthetic_user_ids).active.visible
        .includes(:profile_preference, :profile_locations).order(:id).to_a
      return if profiles.size < 2

      shuffled = profiles.shuffle(random: Random.new(seed))
      states = interaction_states(profiles.map(&:id))
      ApplicationRecord.transaction { create_matches!(shuffled, states) }

      shuffled.each_with_index.each_slice(50) do |batch|
        ApplicationRecord.transaction do
          batch.each do |viewer, index|
            candidates = compatible_candidates(viewer, shuffled, index)
            create_likes!(viewer, candidates, index % 5, states)
            create_passes!(viewer, candidates.reverse, index % 9, states)
          end
        end
        output.puts("synthetic activity ready: #{[ batch.last.last + 1, profiles.size ].min}/#{profiles.size}")
      end
    end

    def interaction_states(profile_ids)
      {
        likes: Like.where(brand:, liker_profile_id: profile_ids, liked_profile_id: profile_ids)
          .pluck(:liker_profile_id, :liked_profile_id).to_set,
        passes: ProfilePass.where(brand:, passer_profile_id: profile_ids, passed_profile_id: profile_ids)
          .pluck(:passer_profile_id, :passed_profile_id).to_set,
        matches: Match.where(brand:, profile_a_id: profile_ids, profile_b_id: profile_ids)
          .pluck(:profile_a_id, :profile_b_id).to_set
      }
    end

    def create_matches!(profiles, states)
      target = [ [ count / 15, 1 ].max, 250 ].min
      profiles.each_with_index do |viewer, index|
        break if states.fetch(:matches).size >= target

        candidate = compatible_candidates(viewer, profiles, index).find do |profile|
          pair = Match.canonical_pair(viewer.id, profile.id)
          !states.fetch(:matches).include?(pair) &&
            !states.fetch(:passes).include?([ viewer.id, profile.id ]) &&
            !states.fetch(:passes).include?([ profile.id, viewer.id ])
        end
        next unless candidate

        create_like_record!(viewer, candidate, states)
        create_like_record!(candidate, viewer, states)
        profile_a_id, profile_b_id = Match.canonical_pair(viewer.id, candidate.id)
        Match.find_or_create_by!(brand:, profile_a_id:, profile_b_id:) { |match| match.status = :active }
        states.fetch(:matches).add([ profile_a_id, profile_b_id ])
      end
    end

    def create_likes!(viewer, candidates, target, states)
      created = 0
      candidates.each do |candidate|
        break if created >= target

        pair = Match.canonical_pair(viewer.id, candidate.id)
        directed = [ viewer.id, candidate.id ]
        reverse = [ candidate.id, viewer.id ]
        next if states.fetch(:matches).include?(pair) || states.fetch(:passes).include?(directed)
        next if states.fetch(:likes).include?(directed) || states.fetch(:likes).include?(reverse)

        create_like_record!(viewer, candidate, states)
        created += 1
      end
    end

    def create_like_record!(viewer, candidate, states)
      directed = [ viewer.id, candidate.id ]
      return if states.fetch(:likes).include?(directed)

      Like.create!(brand:, liker_profile: viewer, liked_profile: candidate, kind: :like)
      states.fetch(:likes).add(directed)
    end

    def create_passes!(viewer, candidates, target, states)
      created = 0
      candidates.each do |candidate|
        break if created >= target

        pair = Match.canonical_pair(viewer.id, candidate.id)
        directed = [ viewer.id, candidate.id ]
        next if states.fetch(:matches).include?(pair)
        next if states.fetch(:likes).include?(directed) || states.fetch(:passes).include?(directed)

        ProfilePass.create!(brand:, passer_profile: viewer, passed_profile: candidate)
        states.fetch(:passes).add(directed)
        created += 1
      end
    end

    def compatible_candidates(viewer, profiles, start_index)
      ordered = profiles.rotate(start_index + 1)
      ordered.filter { |candidate| candidate.id != viewer.id && compatible?(viewer, candidate) }.first(30)
    end

    def compatible?(viewer, candidate)
      viewer_preference = viewer.profile_preference
      candidate_preference = candidate.profile_preference
      return false unless viewer_preference.interested_in.include?(candidate.gender)
      return false unless candidate_preference.interested_in.include?(viewer.gender)

      viewer_age = age(viewer)
      candidate_age = age(candidate)
      return false unless candidate_age.between?(viewer_preference.min_age, viewer_preference.max_age)
      return false unless viewer_age.between?(candidate_preference.min_age, candidate_preference.max_age)

      within_distance?(viewer, candidate, viewer_preference.max_distance_km) &&
        within_distance?(candidate, viewer, candidate_preference.max_distance_km)
    end

    def within_distance?(viewer, candidate, max_distance_km)
      return true if max_distance_km.nil?

      viewer_location = fresh_location(viewer)
      candidate_location = fresh_location(candidate)
      return false unless viewer_location && candidate_location

      haversine_km(viewer_location, candidate_location) <= max_distance_km
    end

    def fresh_location(profile)
      profile.profile_locations.find do |location|
        location.deleted_at.nil? && location.captured_at >= eligibility_policy.location_max_age.ago
      end
    end

    def eligibility_policy
      @eligibility_policy ||= D8n::Platform::BrandRegistry.fetch(brand:).interaction.eligibility_policy
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      Matching::EligibilityPolicy::DEFAULT
    end

    def haversine_km(first, second)
      latitude_delta = radians(second.latitude.to_f - first.latitude.to_f)
      longitude_delta = radians(second.longitude.to_f - first.longitude.to_f)
      first_latitude = radians(first.latitude.to_f)
      second_latitude = radians(second.latitude.to_f)
      value = Math.sin(latitude_delta / 2)**2 +
        Math.cos(first_latitude) * Math.cos(second_latitude) * Math.sin(longitude_delta / 2)**2
      6_371.0 * 2 * Math.asin(Math.sqrt(value))
    end

    def radians(degrees)
      degrees * Math::PI / 180
    end

    def age(profile)
      today = Date.current
      birthday_passed = (today.month * 100 + today.day) >= (profile.birthdate.month * 100 + profile.birthdate.day)
      today.year - profile.birthdate.year - (birthday_passed ? 0 : 1)
    end

    def synthetic_identifiers
      self.class.synthetic_identifiers
    end

    def synthetic_user_ids
      synthetic_identifiers.where(user_id: brand.users.select(:id)).select(:user_id)
    end

    def ensure_no_synthetic_media!(profile_ids)
      return unless ProfilePhoto.where(profile_id: profile_ids).exists?

      raise SafetyError, "synthetic profiles have media; remove it through the media deletion workflow first"
    end

    def ensure_exclusively_synthetic_identities!(identifiers:, user_ids:)
      tagged_identifier_ids = identifiers.select(:id)
      return unless IdentityIdentifier.where(user_id: user_ids).where.not(id: tagged_identifier_ids).exists?

      raise SafetyError, "a synthetic user has an untagged identity; refusing automatic cleanup"
    end

    def delete_relationships!(profile_ids)
      match_ids = Match.where("profile_a_id IN (?) OR profile_b_id IN (?)", profile_ids, profile_ids).pluck(:id)
      conversation_ids = Conversation.where(match_id: match_ids).pluck(:id)
      ConversationParticipant.where(conversation_id: conversation_ids).delete_all
      Conversation.where(id: conversation_ids).delete_all
      ProfileBlock.where("blocker_profile_id IN (?) OR blocked_profile_id IN (?)", profile_ids, profile_ids).delete_all
      Like.where("liker_profile_id IN (?) OR liked_profile_id IN (?)", profile_ids, profile_ids).delete_all
      ProfilePass.where("passer_profile_id IN (?) OR passed_profile_id IN (?)", profile_ids, profile_ids).delete_all
      Match.where(id: match_ids).delete_all
    end

    def delete_identity_activity!(user_ids:, credential_ids:, identifier_ids:)
      synthetic_email = "loadtest-user-%@example.invalid"
      Session.where(user_id: user_ids).delete_all
      NotificationDelivery.where(user_id: user_ids).delete_all
      Notification.where(user_id: user_ids).delete_all
      NotificationEvent.where(user_id: user_ids).delete_all
      NotificationPreference.where(user_id: user_ids).delete_all
      DeviceRegistration.where(user_id: user_ids).delete_all
      SecurityEvent.where(user_id: user_ids).delete_all
      AuthAttempt.where(user_id: user_ids).or(AuthAttempt.where(credential_id: credential_ids))
        .or(AuthAttempt.where(identity_identifier_id: identifier_ids))
        .or(AuthAttempt.where("identifier LIKE ?", synthetic_email)).delete_all
      OtpChallenge.where(identity_identifier_id: identifier_ids)
        .or(OtpChallenge.where("identifier LIKE ?", synthetic_email)).delete_all
    end
  end
end
