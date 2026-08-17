module Messaging
  # Content-validation failure for a message send (blank/oversized body). Distinct
  # from AccessError (authorization/availability) so the controller can map it to
  # 422 while access failures stay a neutral 404.
  class MessageError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code.to_s)
    end
  end
end
