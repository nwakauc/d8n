module Profiles
  class PublicSerializer
    def self.call(profile:)
      new(profile:).call
    end

    def initialize(profile:)
      @profile = profile
    end

    def call
      {
        id: profile.id,
        display_name: profile.display_name,
        age: age,
        bio: profile.bio,
        gender: profile.gender,
        country_code: profile.country_code,
        city: profile.city,
        occupation: profile.occupation,
        height_cm: profile.height_cm,
        body_type: profile.body_type,
        languages_spoken: profile.languages_spoken,
        smoking: profile.smoking,
        drinking: profile.drinking,
        fitness: profile.fitness,
        options: public_options
      }
    end

    private

    attr_reader :profile

    def age
      return if profile.birthdate.blank?

      today = Date.current
      today.year - profile.birthdate.year - ((today.month * 100 + today.day) < (profile.birthdate.month * 100 + profile.birthdate.day) ? 1 : 0)
    end

    def public_options
      selections = profile.profile_option_selections.kept
        .joins(:profile_option_group)
        .merge(ProfileOptionGroup.kept.visibility_public_profile)
        .includes(:profile_option, :profile_option_group)

      selections.group_by { |selection| selection.profile_option_group.key }.transform_values do |group_selections|
        group_selections.sort_by { |selection| [ selection.profile_option.position, selection.profile_option.id ] }
          .map { |selection| selection.profile_option.code }
      end
    end
  end
end
