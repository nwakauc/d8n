module Profiles
  class OwnerSerializer
    def self.call(profile:)
      new(profile:).call
    end

    def initialize(profile:)
      @profile = profile
      @field_policy = FieldPolicy.new(brand: profile.brand)
    end

    def call
      {
        id: profile.public_id,
        brand: { slug: profile.brand.slug, name: profile.brand.name },
        status: profile.status,
        visibility: profile.visibility,
        # The owner sees ALL their selections regardless of group visibility.
        options: selected_options,
        prompts: Profiles::PromptPresenter.call(profile:),
        completion: completion_payload
      }.merge(owner_profile_fields).merge(private_identity_payload)
    end

    private

    attr_reader :profile, :field_policy

    def owner_profile_fields
      field_policy.enabled_profile_fields.index_with { |field| owner_value(field) }.symbolize_keys
    end

    def owner_value(field)
      case field
      when "birthdate" then profile.birthdate&.iso8601
      when "languages" then Profiles::Languages.serialize(profile.languages)
      else profile.public_send(field)
      end
    end

    def private_identity_payload
      field_policy.enabled_identity_fields
        .index_with { |field| profile.user.public_send(field) }.symbolize_keys
    end

    def selected_options
      selections = profile.profile_option_selections.kept.includes(:profile_option, :profile_option_group)

      selections.group_by { |selection| selection.profile_option_group.key }.transform_values do |group_selections|
        group_selections.sort_by { |selection| [ selection.profile_option.position, selection.profile_option.id ] }
          .map { |selection| selection.profile_option.code }
      end
    end

    def completion_payload
      completion = Completion.call(profile:)
      {
        complete: completion.complete?,
        percent: completion.percent,
        missing: completion.missing.map(&:to_s),
        sections: completion.sections
      }
    end
  end
end
