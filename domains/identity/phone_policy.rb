module Identity
  # Resolves brand-configured national phone parsing without putting brand-name
  # conditionals in shared Identity code. International E.164 input works for any
  # brand; a calling code is needed only to interpret a national trunk prefix.
  module PhonePolicy
    def self.country_calling_code(brand:)
      D8n::Platform::BrandRegistry.fetch(brand:).phone_country_calling_code
    rescue D8n::Platform::BrandRegistry::UnsupportedBrand
      nil
    end
  end
end
