module Trust
  class AccessError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code.to_s)
    end
  end
end
