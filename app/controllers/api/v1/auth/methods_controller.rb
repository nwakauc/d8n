class Api::V1::Auth::MethodsController < ApplicationController
  def show
    if Current.brand.blank?
      render json: { error: "brand_required" }, status: :not_found
      return
    end

    render json: {
      brand: {
        slug: Current.brand.slug,
        name: Current.brand.name
      },
      methods: Identity::AuthPolicy.available_methods(brand: Current.brand)
    }
  end
end
