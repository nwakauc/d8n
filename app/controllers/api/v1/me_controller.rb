class Api::V1::MeController < ApplicationController
  before_action :authenticate_user!

  def show
    render json: {
      user_id: Current.user.id,
      brand: {
        slug: Current.brand.slug,
        name: Current.brand.name
      },
      session: {
        id: Current.session.id,
        expires_at: Current.session.expires_at.iso8601
      }
    }
  end
end
