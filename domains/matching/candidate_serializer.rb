module Matching
  class CandidateSerializer
    # `status` carries the viewer-relative signals (verified/online/
    # last_active_at/distance_km) computed in bulk for the whole page by
    # Profiles::StatusFields — defaulted to empty so any caller that doesn't
    # supply it still gets a valid public profile.
    def self.call(profile:, strategy:, status: {})
      Profiles::PublicSerializer.call(profile:).merge(
        compatibility: strategy.compatibility(profile:)
      ).merge(status)
    end
  end
end
