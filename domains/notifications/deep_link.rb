module Notifications
  module DeepLink
    DATEZA_DEFAULT_BASE_URL = "https://www.date-za.com"

    def self.for(brand:, path:)
      base_url = ENV["D8N_#{brand.slug.upcase}_APP_URL"].presence
      base_url ||= DATEZA_DEFAULT_BASE_URL if brand.slug == "dateza"
      return if base_url.blank?

      "#{base_url.delete_suffix("/")}/#{path.to_s.delete_prefix("/")}"
    end
  end
end
