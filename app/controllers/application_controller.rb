class ApplicationController < ActionController::API
  include RateLimitable

  PlatformCapabilityRequirement = Data.define(:capability, :surface)

  class_attribute :required_platform_capability, instance_writer: false, default: nil

  before_action :set_current_context

  def self.requires_platform_capability(capability, surface: nil)
    self.required_platform_capability = PlatformCapabilityRequirement.new(
      capability: capability.to_s,
      surface: surface&.to_s
    )
  end

  private

  def set_current_context
    result = Brands::Resolver.call(request:)
    Current.brand = result.brand
    Current.locale = request.headers["Accept-Language"].to_s.split(",").first.presence
    Current.permissions = []
    Current.features = {}
    authenticate_bearer_session
  end

  def authenticate_user!
    return if Current.user.present?

    render json: { error: "unauthorized" }, status: :unauthorized
  end

  def authorize_platform_capability!
    requirement = required_platform_capability
    return if requirement.nil?

    D8n::Platform::CapabilityAccess.authorize!(
      brand: Current.brand,
      capability: requirement.capability,
      surface: requirement.surface
    )
  rescue D8n::Platform::CapabilityAccess::NotConfigured => e
    render json: { error: e.code }, status: :not_found
  end

  def authenticate_bearer_session
    token = bearer_token
    return if token.blank?

    result = Identity::SessionAuthenticator.call(brand: Current.brand, token:)
    return unless result.success?

    Current.session = result.session
    Current.user = result.user
  end

  def bearer_token
    authorization = request.headers["Authorization"].to_s
    scheme, token = authorization.split(" ", 2)
    return unless scheme&.casecmp("Bearer")&.zero?

    token.presence
  end

  # Presigned R2 retrieval URLs need no host, but the Disk service used in
  # development/test builds a routed URL that does. Derive it from the request so
  # any controller that serializes signed media URLs produces usable links.
  def set_active_storage_url_options
    ActiveStorage::Current.url_options = {
      protocol: request.protocol,
      host: request.host,
      port: request.optional_port
    }
  end
end
