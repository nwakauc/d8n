module Identity
  # Computes the composite RealMe badge: confirmed email AND an approved
  # selfie AND an approved liveness video AND an approved government ID
  # (ADR 0034). This is the ONLY thing that earns the badge — a verified
  # phone or a single approved check is not RealMe completion.
  #
  # `Profiles::StatusFields` calls `.bulk` to decorate a whole discovery page
  # or profile detail without an N+1; `Api::V1::MeController` calls `.call`
  # for the single-user `/me` projection.
  class RealmeBadge
    REQUIRED_CHECK_TYPES = %w[selfie video government_id].freeze

    # e.g. {"selfie"=>"selfie", "video"=>"video", "liveness"=>"video",
    # "government_id"=>"government_id", "gov_id"=>"government_id"}
    ALIAS_TO_CANONICAL = Identity::RealmeAssertions::CHECK_TYPES.each_with_object({}) do |(canonical, aliases), acc|
      aliases.each { |alias_name| acc[alias_name] = canonical }
    end.freeze

    def self.call(user:, brand:)
      bulk(user_ids: [ user&.id ].compact, brand:).fetch(user&.id, false)
    end

    # Returns { user_id => true/false } for every id in `user_ids`, in two
    # bulk queries regardless of batch size.
    def self.bulk(user_ids:, brand:)
      user_ids = user_ids.compact.uniq
      return {} if user_ids.empty? || brand.blank?

      verified_emails = IdentityIdentifier.kept.contact.email
        .where(user_id: user_ids).where.not(verified_at: nil)
        .distinct.pluck(:user_id).to_set

      approved_check_types = VerificationAssertion.where(brand:, user_id: user_ids, status: "approved")
        .where(check_type: ALIAS_TO_CANONICAL.keys)
        .distinct.pluck(:user_id, :check_type)
        .each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |(user_id, check_type), acc|
          acc[user_id] << ALIAS_TO_CANONICAL.fetch(check_type)
        end

      user_ids.index_with do |user_id|
        verified_emails.include?(user_id) &&
          REQUIRED_CHECK_TYPES.all? { |type| approved_check_types[user_id].include?(type) }
      end
    end
  end
end
