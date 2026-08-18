module HookTonight
  # Turns Hook Tonight ON for the current member: records/refreshes their single
  # "available tonight" state and stamps a fresh expiry. Eligibility is enforced
  # through the SAME gate as Liking/Hooking (Matching::ProfileParticipant), so a
  # suspended, closed, hidden, or otherwise ineligible member cannot activate —
  # and a stale activation can never outlive eligibility because discovery
  # re-checks eligibility at read time regardless.
  #
  # Re-activation reuses the one current-state row (Postgres upsert on the unique
  # (brand, profile) index) instead of accumulating history, and is safe under
  # concurrent double-activation: ON CONFLICT collapses simultaneous inserts to a
  # single row.
  class Activate
    Result = Data.define(:state)

    def self.call(user:, brand:, intent: nil)
      new(user:, brand:, intent:).call
    end

    def initialize(user:, brand:, intent:)
      @user = user
      @brand = brand
      @intent = Policy.normalize_intent(intent)
    end

    def call
      viewer = Matching::ProfileParticipant.discoverable!(user:, brand:)
      now = Time.current

      # Atomic upsert: activation is idempotent and race-free. A concurrent second
      # activation updates the same row rather than creating a duplicate, and a
      # reactivation clears any prior deactivated_at/expiry in one statement.
      HookTonightState.upsert(
        {
          brand_id: brand.id, profile_id: viewer.id, intent:,
          activated_at: now, expires_at: now + Policy::EXPIRES_IN, deactivated_at: nil,
          created_at: now, updated_at: now
        },
        unique_by: :index_hook_tonight_states_on_brand_and_profile
      )

      state = HookTonightState.find_by!(brand:, profile: viewer)
      record_event(viewer:, state:)
      Result.new(state:)
    end

    private

    attr_reader :user, :brand, :intent

    def record_event(viewer:, state:)
      SecurityEvent.create!(
        brand:, user:,
        event_type: "hook_tonight.activated",
        severity: :info,
        metadata: { profile_id: viewer.id, intent:, expires_at: state.expires_at.iso8601 }
      )
    end
  end
end
