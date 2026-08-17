class ApplicationController < ActionController::API
  before_action :set_current_context

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
