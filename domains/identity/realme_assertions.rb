module Identity
  # Safe client projection of the current user's RealMe check_type assertions
  # (`VerificationAssertion`, see ADR 0031's `InteractionAccess` gate). This is
  # the same table the message-send gate reads — it is real, brand+user scoped
  # data, previously computed server-side only and never surfaced to clients.
  class RealmeAssertions
    CHECK_TYPES = {
      "selfie" => %w[selfie],
      "video" => %w[video liveness],
      "government_id" => %w[government_id gov_id]
    }.freeze

    STATUSES = %w[approved pending rejected].freeze

    Entry = Data.define(:check_type, :status, :submitted_at, :reviewed_at)

    def self.call(...)
      new(...).call
    end

    def initialize(user:, brand:)
      @user = user
      @brand = brand
    end

    def call
      return [] if user.blank? || brand.blank?

      CHECK_TYPES.filter_map do |canonical, aliases|
        latest = assertions.find { |a| aliases.include?(a.check_type) }
        next if latest.blank?

        Entry.new(canonical, normalize_status(latest.status), latest.submitted_at, latest.reviewed_at)
      end
    end

    private

    attr_reader :user, :brand

    def assertions
      @assertions ||= VerificationAssertion.where(brand:, user:).order(created_at: :desc)
    end

    def normalize_status(status)
      STATUSES.include?(status) ? status : "pending"
    end
  end
end
