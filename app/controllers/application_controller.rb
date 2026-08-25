class ApplicationController < ActionController::API
  include ActionController::Cookies
  include RateLimitable

  PlatformCapabilityRequirement = Data.define(:capability, :surface)

  class_attribute :required_platform_capability, instance_writer: false, default: nil

  before_action :set_current_context
  before_action :verify_browser_session_csrf!

  def self.requires_platform_capability(capability, surface: nil)
    self.required_platform_capability = PlatformCapabilityRequirement.new(
      capability: capability.to_s,
      surface: surface&.to_s
    )
  end

  def self.requires_platform_contract(**options)
    before_action :authorize_platform_contract!, **options
  end

  private

  def set_current_context
    result = Brands::Resolver.call(request:)
    Current.brand = result.brand
    Current.locale = request.headers["Accept-Language"].to_s.split(",").first.presence
    Current.permissions = []
    Current.features = {}
    authenticate_session
  end

  def authenticate_user!
    return if Current.user.present?

    render json: { error: authentication_error_code }, status: :unauthorized
  end

  def authorize_platform_contract!
    Current.platform_contract = D8n::Platform::BrandRegistry.fetch(brand: Current.brand)
  rescue D8n::Platform::BrandRegistry::UnsupportedBrand => e
    render json: { error: e.code }, status: :not_found
  end

  def authorize_platform_capability!
    requirement = required_platform_capability
    return if requirement.nil?

    D8n::Platform::CapabilityAccess.authorize!(
      contract: Current.platform_contract,
      capability: requirement.capability,
      surface: requirement.surface
    )
  rescue D8n::Platform::CapabilityAccess::NotConfigured => e
    render json: { error: e.code }, status: :not_found
  end

  def authenticate_session
    source, token = authentication_credential
    return if token.blank?

    result = Identity::SessionAuthenticator.call(brand: Current.brand, token:)
    Current.authentication_source = source
    Current.authentication_error = result.error
    unless result.success?
      clear_browser_session_cookie if source == :cookie
      return
    end

    Current.session = result.session
    Current.user = result.user
  end

  def authentication_credential
    authorization = request.headers["Authorization"].to_s
    return [ :bearer, bearer_token ] if authorization.present?

    [ :cookie, cookies[Identity::BrowserSession::COOKIE_NAME] ]
  end

  def bearer_token
    authorization = request.headers["Authorization"].to_s
    scheme, token = authorization.split(" ", 2)
    return unless scheme&.casecmp("Bearer")&.zero?

    token.presence
  end

  def verify_browser_session_csrf!
    return unless Current.session
    return unless Identity::BrowserSession.csrf_required?(
      request:, authentication_source: Current.authentication_source
    )
    return if Identity::BrowserSession.valid_csrf_token?(
      session: Current.session,
      token: request.headers[Identity::BrowserSession::CSRF_HEADER]
    )

    render json: { error: "csrf_token_invalid" }, status: :forbidden
  end

  def persist_browser_session(raw_token:, session:)
    return unless Identity::BrowserSession.enabled?(brand: Current.brand)
    return unless Identity::BrowserSession.origin_allowed?(request:)

    cookies[Identity::BrowserSession::COOKIE_NAME] = Identity::BrowserSession.cookie_options(
      expires_at: session.expires_at
    ).merge(value: raw_token)
    {
      persisted: true,
      csrf_token: Identity::BrowserSession.csrf_token(session:)
    }
  end

  def clear_browser_session_cookie
    cookies.delete(
      Identity::BrowserSession::COOKIE_NAME,
      **Identity::BrowserSession.cookie_options
    )
  end

  def authentication_error_code
    return "session_expired" if Current.authentication_source == :cookie && Current.authentication_error == :expired_session
    return "session_revoked" if Current.authentication_source == :cookie && Current.authentication_error == :revoked_session

    "unauthorized"
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
