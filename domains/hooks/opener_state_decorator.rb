module Hooks
  # Same viewer-relative state machine as ProfileStateDecorator (Hook/Opener
  # share the engine — see ViewerStates), under the `opener_state` key for a
  # brand whose product calls this D8N Opener rather than Hook.
  class OpenerStateDecorator
    def self.call(viewer:, profiles:)
      states = ViewerStates.call(viewer:, profiles:)
      Array(profiles).each_with_object({}) do |profile, fields|
        fields[profile.id] = { opener_state: states.fetch(profile.id, ViewerStates::UNAVAILABLE) }
      end
    end
  end
end
