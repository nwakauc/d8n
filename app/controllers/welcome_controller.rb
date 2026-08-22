class WelcomeController < ApplicationController
  # Per-service delivery status, so a caller hitting the API root can see what is
  # usable today versus still planned. Keep this honest against config/routes.rb.
  #   available      - implemented and callable now
  #   preview        - partially available; scope is intentionally limited
  #   in_development - being built; not exposed to end users yet
  #   planned        - not started
  STATUS_LEGEND = {
    "available" => "Implemented and callable now.",
    "preview" => "Partially available; scope is intentionally limited.",
    "in_development" => "Being built; not exposed to end users yet.",
    "planned" => "Not started."
  }.freeze

  SERVICES = [
    { key: "identity", name: "D8N ID", domain: "Identity", status: "available",
      detail: "Phone/email + password registration, login, recovery, sessions, and identifier verification." },
    { key: "profiles", name: "D8N Profiles", domain: "Profiles", status: "available",
      detail: "Brand-configured profiles, options, preferences, location, and publication." },
    { key: "matching", name: "D8N Match", domain: "Matching", status: "available",
      detail: "Shared eligibility, DateZA Find, and DateZA v1 compatibility are available; DateZA Discovery remains unconfigured." },
    { key: "messaging", name: "D8N Chat", domain: "Messaging", status: "preview",
      detail: "Match-gated plain-text messages are available; receipts, realtime, media, and client idempotency are not." },
    { key: "trust", name: "D8N Trust", domain: "Trust", status: "preview",
      detail: "Blocking, content reporting, report review, and brand suspension are available; public standing is not." },
    { key: "media", name: "D8N Media", domain: "Media", status: "preview",
      detail: "Owner-scoped profile photos: direct-to-R2 upload, signed retrieval, delete/purge. " \
        "Public delivery, re-encode, EXIF removal, and moderation enforcement are gated." },
    { key: "verification", name: "D8N Verify", domain: "Verification", status: "planned",
      detail: "Identity/selfie verification is not yet implemented." },
    { key: "billing", name: "D8N Pay", domain: "Billing", status: "planned" },
    { key: "notifications", name: "D8N Notify", domain: "Notifications", status: "available",
      detail: "Brand-scoped inbox/read API and DateZA welcome email foundation; production push provider and device API are gated." },
    { key: "analytics", name: "D8N Insights", domain: "Analytics", status: "planned" },
    { key: "admin", name: "D8N Admin", domain: "Admin", status: "preview",
      detail: "Brand-scoped report review and suspension APIs exist; a complete hardened admin product does not." }
  ].freeze

  def index
    render json: {
      message: "Welcome to D8N API",
      app: "d8n",
      api_version: "v1",
      environment: Rails.env,
      current_brand: current_brand_payload,
      status_legend: STATUS_LEGEND,
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
