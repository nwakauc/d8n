class ApplicationController < ActionController::API
  before_action :set_current_context

  private

  def set_current_context
    result = Brands::Resolver.call(request:)
    Current.brand = result.brand
    Current.locale = request.headers["Accept-Language"].to_s.split(",").first.presence
    Current.permissions = []
    Current.features = {}
  end
end
