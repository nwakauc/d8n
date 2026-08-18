module HookTonight
  # Authoritative "am I available tonight right now?" for the current member. The
  # backend computes liveness against the clock (via the `live` scope) so the
  # client never has to infer it from a stale activation: a lapsed or deactivated
  # state reports `active: false` even though its row still exists.
  class CurrentState
    Result = Data.define(:active, :expires_at, :intent)

    INACTIVE = Result.new(active: false, expires_at: nil, intent: nil)

    def self.call(user:, brand:)
      viewer = Profile.kept.find_by(user:, brand:)
      state = viewer && HookTonightState.live.find_by(brand:, profile: viewer)
      return INACTIVE if state.nil?

      Result.new(active: true, expires_at: state.expires_at, intent: state.intent)
    end
  end
end
