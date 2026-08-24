module Hooks
  class ProfileStateDecorator
    def self.call(viewer:, profiles:)
      states = ViewerStates.call(viewer:, profiles:)
      Array(profiles).each_with_object({}) do |profile, fields|
        fields[profile.id] = { hook_state: states.fetch(profile.id, ViewerStates::UNAVAILABLE) }
      end
    end
  end
end
