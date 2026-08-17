module Admin
  # Single typed error for the moderation API. The controller maps `code` to an
  # HTTP status, keeping neutral semantics (cross-brand/unknown reports are simply
  # `report_unavailable`, never disclosed as "exists in another brand").
  class ModerationError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code.to_s)
    end
  end
end
