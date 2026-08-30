module Admin
  module Mfa
    class Error < StandardError
      attr_reader :code, :retry_after

      def initialize(code, retry_after: nil)
        @code = code.to_s
        @retry_after = retry_after
        super(@code)
      end
    end
  end
end
