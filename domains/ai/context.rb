module Ai
  # Deliberate, brand-owned context boundary. An assistant never obtains data by
  # querying arbitrary models; each approved brand policy returns only the data
  # a member can already see or owns in that brand.
  module Context
    def self.for(user:, brand:, membership:)
      return Date9ja.call(user:, brand:, membership:) if brand.slug == "date9ja"

      {}
    end
  end
end
