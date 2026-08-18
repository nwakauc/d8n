module Matching
  class InteractionError < StandardError
    attr_reader :code, :retry_after

    # `retry_after` (seconds) is optional and only set for throttling codes such as
    # `:hook_rate_limited`, letting the controller emit a Retry-After header.
    def initialize(code, retry_after: nil)
      @code = code
      @retry_after = retry_after
      super(code.to_s)
    end
  end
end
