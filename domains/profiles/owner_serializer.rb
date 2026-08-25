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
      publication_completion = completion_payload
      {
        id: profile.public_id,
        brand: { slug: profile.brand.slug, name: profile.brand.name },
        status: profile.status,
        visibility: profile.visibility,
        location: location_payload,
        # The owner sees ALL their selections regardless of group visibility.
        options: selected_options,
        prompts: Profiles::PromptPresenter.call(profile:),
        counts: counts_payload,
        verification: verification_payload,
        publication: publication_payload,
        # Backward-compatible alias. New clients should use the explicitly named
        # publication_completion and profile_completion contracts.
        completion: publication_completion,
        publication_completion:,
        profile_completion: rich_completion_payload
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

    # Never latitude/longitude here — only a safe, human-readable place label
    # when the location came from a catalog selection (Profiles::CurrentPlace).
    # A raw device-GPS location has no Place to name, so it stays boolean-only.
    def location_payload
      location = ProfileLocation.kept.includes(:place).find_by(profile:)
      return { configured: false } if location.blank?
      return { configured: true } if location.place.blank?

      { configured: true, place: { name: location.place.name, display_path: location.place.display_path } }
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

    def rich_completion_payload
      completion = RichCompletion.call(profile:)
      return if completion.nil?

      {
        percent: completion.percent,
        level: completion.level,
        missing: completion.missing,
        suggestions: completion.suggestions,
        sections: completion.sections
      }
    end

    def counts_payload
      {
        photos: profile.profile_photos.kept.count,
        prompts: profile.prompt_answers.kept.count,
        interests: profile.profile_option_selections.kept
          .joins(:profile_option_group).where(profile_option_groups: { key: "interests" }).count
      }
    end

    def verification_payload
      {
        contact: {
          verified: IdentityIdentifier.kept.where(user_id: profile.user_id).where.not(verified_at: nil).exists?
        }
      }
    end

    def publication_payload
      {
        published: profile.active? && profile.visible?,
        status: profile.status,
        visibility: profile.visibility
      }
    end
  end
end
