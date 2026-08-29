module Hq
  # Single typed error for the HQ API, mirroring Admin::ModerationError: the
  # controller maps `code` to an HTTP status, and cross-brand/unknown members
  # are always the same neutral `member_unavailable` -- never disclosed as
  # "exists on another brand" (no enumeration).
  class HqError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code.to_s)
    end
  end
end
