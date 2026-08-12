module Profiles
  class Completion
    Result = Data.define(:complete?, :percent, :missing)

    REQUIRED_PROFILE_FIELDS = %i[ display_name birthdate gender ].freeze
    REQUIRED_PREFERENCE_FIELDS = %i[ min_age max_age interested_in ].freeze
    REQUIRED_COLLECTIONS = %i[ photos ].freeze

    def self.call(profile:)
      new(profile:).call
    end

    def initialize(profile:)
      @profile = profile
    end

    def call
      missing = missing_profile_fields + missing_preference_fields + missing_collections
      total = REQUIRED_PROFILE_FIELDS.size + REQUIRED_PREFERENCE_FIELDS.size + REQUIRED_COLLECTIONS.size
      completed = total - missing.size

      Result.new(missing.empty?, ((completed.to_f / total) * 100).round, missing)
    end

    private

    attr_reader :profile

    def missing_profile_fields
      REQUIRED_PROFILE_FIELDS.filter { |field| profile.public_send(field).blank? }
    end

    def missing_preference_fields
      preference = profile.profile_preference
      return REQUIRED_PREFERENCE_FIELDS.map { |field| :"preferences.#{field}" } if preference.blank?

      REQUIRED_PREFERENCE_FIELDS.filter_map do |field|
        :"preferences.#{field}" if preference.public_send(field).blank?
      end
    end

    def missing_collections
      return [] if profile.profile_photos.kept.exists?

      REQUIRED_COLLECTIONS
    end
  end
end
