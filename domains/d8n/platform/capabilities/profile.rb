module D8n
  module Platform
    module Capabilities
      module Profile
        DEFINITIONS = [
          CapabilityDefinition.new(key: "profile.onboarding", status: :available,
            implementations: %w[Profiles::OnboardingStatus Profiles::Completion]),
          CapabilityDefinition.new(key: "profile.scalar_fields", status: :available,
            implementations: %w[Profiles::Configuration Profiles::FieldPolicy]),
          CapabilityDefinition.new(key: "profile.options", status: :available,
            implementations: %w[Profiles::CapabilityCatalog Profiles::OptionSelections]),
          CapabilityDefinition.new(key: "profile.preferences", status: :available,
            implementations: %w[Profiles::CurrentPreferences]),
          CapabilityDefinition.new(key: "profile.prompts", status: :available,
            implementations: %w[Profiles::PromptAnswers Profiles::PromptPresenter]),
          CapabilityDefinition.new(key: "profile.interests", status: :available,
            implementations: %w[Profiles::CapabilityCatalog Profiles::OptionSelections]),
          CapabilityDefinition.new(key: "profile.languages", status: :available,
            implementations: %w[Profiles::Languages]),
          CapabilityDefinition.new(key: "profile.location", status: :available,
            implementations: %w[Profiles::CurrentLocation]),
          CapabilityDefinition.new(key: "profile.photos", status: :available,
            implementations: %w[Profiles::PhotoLibrary Profiles::PhotoUpload]),
          CapabilityDefinition.new(key: "profile.completion", status: :available,
            implementations: %w[Profiles::Completion]),
          CapabilityDefinition.new(key: "profile.publication", status: :available,
            implementations: %w[Profiles::Publication]),
          CapabilityDefinition.new(key: "profile.visibility", status: :available,
            implementations: %w[Profiles::PublicProfile Profiles::PublicSerializer])
        ].freeze

        def self.definitions = DEFINITIONS
      end
    end
  end
end
