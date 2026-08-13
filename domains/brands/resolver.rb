module Brands
  class Resolver
    Result = Data.define(:brand, :source)

    def self.call(...)
      new(...).call
    end

    def initialize(request:)
      @request = request
    end

    def call
      host = normalized_host(request.host)
      domain = BrandDomain.kept.active.joins(:brand).merge(Brand.kept.active).includes(:brand).find_by(host:)

      Result.new(brand: domain&.brand, source: domain ? :host : nil)
    end

    private

    attr_reader :request

    def normalized_host(host)
      host.to_s.strip.downcase.delete_suffix(".")
    end
  end
end
