module Profiles
  class Completion
    Result = Data.define(:complete?, :percent, :missing)

    SUPPORTED_PROFILE_FIELDS = %w[ display_name birthdate gender ].freeze
    SUPPORTED_PREFERENCE_FIELDS = %w[ min_age max_age interested_in max_distance_km country relationship_intent ].freeze
    SUPPORTED_COLLECTIONS = %w[ photos ].freeze

    def self.call(profile:)
      new(profile:).call
    end

    def initialize(profile:)
      @profile = profile
    end

    def call
      missing = missing_profile_fields + missing_preference_fields + missing_collections
      total = profile_fields.size + preference_fields.size + collections.size
      completed = total - missing.size

      Result.new(missing.empty?, ((completed.to_f / total) * 100).round, missing)
    end

    private

    attr_reader :profile

    def missing_profile_fields
      profile_fields.filter { |field| profile.public_send(field).blank? }.map(&:to_sym)
    end

    def missing_preference_fields
      preference = profile.profile_preference
      return preference_fields.map { |field| :"preferences.#{field}" } if preference.blank?

      preference_fields.filter_map do |field|
        :"preferences.#{field}" if preference.public_send(field).blank?
      end
    end

    def missing_collections
      return [] if profile.profile_photos.kept.exists?

      collections.map(&:to_sym)
    end

    def requirements
      @requirements ||= profile.brand.profile_completion_requirements
    end

    def profile_fields
      requirements.fetch("profile_fields")
    end

    def preference_fields
      requirements.fetch("preference_fields")
    end

    def collections
      requirements.fetch("collections")
    end
  end
end
