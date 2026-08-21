class Api::V1::ProfileConfigurationController < ApplicationController
  before_action :authenticate_user!

  def show
    render json: {
      configuration: Profiles::Configuration.call(brand: Current.brand),
      onboarding: Profiles::OnboardingStatus.call(user: Current.user, brand: Current.brand)
    }
  end
end
