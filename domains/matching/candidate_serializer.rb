module Matching
  class CandidateSerializer
    REASONS = {
      matching_shared_intent: "shared_intent",
      matching_similar_vibe: "similar_vibe",
      matching_mutual_age_fit: "mutual_age_fit"
    }.freeze

    def self.call(profile:)
      Profiles::PublicSerializer.call(profile:).merge(
        compatibility: {
          score: Integer(profile[:matching_score]),
          confidence: profile[:matching_confidence].to_f,
          reasons: REASONS.filter_map { |attribute, code| code if profile[attribute] }
        }
      )
    end
  end
end
