class WelcomeController < ApplicationController
  SERVICES = [
    { key: "identity", name: "D8N ID", domain: "Identity", status: "planned" },
    { key: "profiles", name: "D8N Profiles", domain: "Profiles", status: "planned" },
    { key: "matching", name: "D8N Match", domain: "Matching", status: "planned" },
    { key: "messaging", name: "D8N Chat", domain: "Messaging", status: "planned" },
    { key: "verification", name: "D8N Verify", domain: "Verification", status: "planned" },
    { key: "trust", name: "D8N Trust", domain: "Trust", status: "planned" },
    { key: "media", name: "D8N Media", domain: "Media", status: "planned" },
    { key: "billing", name: "D8N Pay", domain: "Billing", status: "planned" },
    { key: "notifications", name: "D8N Notify", domain: "Notifications", status: "planned" },
    { key: "analytics", name: "D8N Insights", domain: "Analytics", status: "planned" },
    { key: "admin", name: "D8N Admin", domain: "Admin", status: "planned" }
  ].freeze

  def index
    render json: {
      message: "Welcome to D8N API",
      app: "d8n",
      api_version: "v1",
      current_brand: current_brand_payload,
      services: SERVICES
    }
  end

  private

  def current_brand_payload
    return unless Current.brand

    {
      slug: Current.brand.slug,
      name: Current.brand.name
    }
  end
end
