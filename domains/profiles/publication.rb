module Profiles
  class Publication
    class Incomplete < StandardError
      attr_reader :completion

      def initialize(completion)
        @completion = completion
        super("profile is incomplete")
      end
    end

    class Unavailable < StandardError; end

    def self.activate!(user:, brand:)
      profile = Profile.kept.find_by!(user:, brand:)

      profile.with_lock do
        ensure_account_available!(profile)
        raise Unavailable, "suspended profiles cannot be activated" if profile.suspended?

        completion = Completion.call(profile:)
        raise Incomplete, completion unless completion.complete?

        profile.update!(status: :active, visibility: :visible)
      end

      profile
    end

    def self.deactivate!(user:, brand:)
      profile = Profile.kept.find_by!(user:, brand:)

      profile.with_lock do
        if profile.suspended?
          profile.update!(visibility: :hidden)
        else
          profile.update!(status: :draft, visibility: :hidden)
        end
      end

      profile
    end

    def self.unpublish_if_incomplete!(profile:)
      return profile unless profile.active?
      return profile if Completion.call(profile:).complete?

      profile.update!(status: :draft, visibility: :hidden)
      profile
    end

    def self.ensure_account_available!(profile)
      user = profile.user
      membership = profile.brand_membership
      return if user.active? && user.deleted_at.nil? && membership.active? && membership.deleted_at.nil?

      raise Unavailable, "profile account is unavailable"
    end
    private_class_method :ensure_account_available!
  end
end
