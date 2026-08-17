module Admin
  # Signed, brand-bound cursor for the moderation queue. The queue is ordered
  # oldest-first by (created_at ASC, id ASC) so the longest-waiting reports surface
  # first; the cursor pages forward into newer reports. Bound to the brand so a
  # cursor cannot be replayed against another brand's queue.
  class ReportCursor
    class Invalid < StandardError; end

    PURPOSE = "admin-report-queue-cursor"

    def self.encode(brand:, report:)
      verifier.generate(
        {
          brand: brand.slug,
          created_at: report.created_at.iso8601(6),
          id: report.id
        },
        purpose: PURPOSE
      )
    end

    def self.apply(scope:, value:, brand:)
      return scope if value.blank?

      payload = verifier.verify(value, purpose: PURPOSE).with_indifferent_access
      raise Invalid, "cursor is invalid" unless payload[:brand] == brand.slug

      created_at = Time.iso8601(payload.fetch(:created_at))
      id = Integer(payload.fetch(:id))

      scope.where(
        "reports.created_at > ? OR (reports.created_at = ? AND reports.id > ?)",
        created_at, created_at, id
      )
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError, KeyError, TypeError
      raise Invalid, "cursor is invalid"
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
