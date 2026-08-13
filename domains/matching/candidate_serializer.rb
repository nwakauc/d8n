module Matching
  class CandidateSerializer
    def self.call(profile:, strategy:)
      Profiles::PublicSerializer.call(profile:).merge(
        compatibility: strategy.compatibility(profile:)
      )
    end
  end
end
