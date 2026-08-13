module Profiles
  class OwnerSerializer
    def self.call(profile:)
      new(profile:).call
    end

    def initialize(profile:)
      @profile = profile
    end

    def call
      {
        id: profile.public_id,
        brand: { slug: profile.brand.slug, name: profile.brand.name },
        display_name: profile.display_name,
        bio: profile.bio,
        birthdate: profile.birthdate&.iso8601,
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
        status: profile.status,
        visibility: profile.visibility,
        options: selected_options,
        completion: completion_payload
      }
    end

    private

    attr_reader :profile

    def selected_options
      selections = profile.profile_option_selections.kept.includes(:profile_option, :profile_option_group)

      selections.group_by { |selection| selection.profile_option_group.key }.transform_values do |group_selections|
        group_selections.sort_by { |selection| [ selection.profile_option.position, selection.profile_option.id ] }
          .map { |selection| selection.profile_option.code }
      end
    end

    def completion_payload
      completion = Completion.call(profile:)
      { complete: completion.complete?, percent: completion.percent, missing: completion.missing.map(&:to_s) }
    end
  end
end
