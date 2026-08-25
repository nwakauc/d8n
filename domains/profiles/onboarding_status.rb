module Profiles
  class OnboardingStatus
    STATES = %w[ profile_required profile_incomplete ready_to_publish complete profile_suspended ].freeze
    STEPS = %w[ profile preferences photos location options publication ].freeze

    def self.call(user:, brand:)
      profile = CurrentProfile.find(user:, brand:)
      return missing_profile_payload(brand:) if profile.blank?

      completion = Completion.call(profile:)
      {
        state: state(profile:, completion:),
        next_step: next_step(profile:, completion:),
        profile_exists: true,
        profile_complete: completion.complete?,
        profile_published: profile.active? && profile.visible?,
        completion: completion_payload(completion)
      }
    end

    def self.missing_profile_payload(brand:)
      missing = initial_missing(brand:)
      {
        state: "profile_required",
        next_step: "profile",
        profile_exists: false,
        profile_complete: false,
        profile_published: false,
        completion: { complete: false, percent: 0, missing: }
      }
    end
    private_class_method :missing_profile_payload

    def self.initial_missing(brand:)
      requirements = brand.profile_completion_requirements
      requirements.fetch("identity_fields") +
        requirements.fetch("profile_fields") +
        requirements.fetch("preference_fields").map { |field| "preferences.#{field}" } +
        requirements.fetch("collections") +
        requirements.fetch("option_groups").map { |key| "options.#{key}" }
    end
    private_class_method :initial_missing

    def self.state(profile:, completion:)
      return "profile_suspended" if profile.suspended?
      return "profile_incomplete" unless completion.complete?
      return "complete" if profile.active? && profile.visible?

      "ready_to_publish"
    end
    private_class_method :state

    def self.next_step(profile:, completion:)
      return nil if profile.suspended? || (completion.complete? && profile.active? && profile.visible?)
      return "publication" if completion.complete?

      missing_step(completion.missing.first.to_s)
    end
    private_class_method :next_step

    def self.missing_step(missing)
      return "preferences" if missing.start_with?("preferences.")
      return "options" if missing.start_with?("options.")
      return "photos" if missing == "photos"
      return "location" if missing == "location"

      "profile"
    end
    private_class_method :missing_step

    def self.completion_payload(completion)
      {
        complete: completion.complete?,
        percent: completion.percent,
        missing: completion.missing.map(&:to_s)
      }
    end
    private_class_method :completion_payload
  end
end
