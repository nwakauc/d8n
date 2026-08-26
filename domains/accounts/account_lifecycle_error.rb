module Accounts
  class AccountLifecycleError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code.to_s)
    end
  end
end
