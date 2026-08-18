module HookTonight
  # Turns Hook Tonight OFF for the current member. The member immediately leaves
  # the Hook Tonight pool (the row stops being `live`); their normal profile,
  # existing Hooks, matches, and conversations are untouched.
  #
  # Idempotent by design: if there is no live state (never activated, already
  # deactivated, already lapsed, or the profile is gone), it is a silent no-op and
  # emits no event — so a client can safely fire "deactivate" repeatedly.
  class Deactivate
    def self.call(user:, brand:)
      new(user:, brand:).call
    end

    def initialize(user:, brand:)
      @user = user
      @brand = brand
    end

    def call
      # Deliberately does NOT require eligibility: a member who became suspended
      # should still be able to switch their availability off.
      viewer = Profile.kept.find_by(user:, brand:)
      return if viewer.nil?

      state = HookTonightState.live.find_by(brand:, profile: viewer)
      return if state.nil?

      state.update!(deactivated_at: Time.current)
      record_event(viewer:)
    end

    private

    attr_reader :user, :brand

    def record_event(viewer:)
      SecurityEvent.create!(
        brand:, user:,
        event_type: "hook_tonight.deactivated",
        severity: :info,
        metadata: { profile_id: viewer.id }
      )
    end
  end
end
