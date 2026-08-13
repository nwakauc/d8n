class Api::V1::ProfileConfigurationController < ApplicationController
  before_action :authenticate_user!

  def show
    render json: { configuration: Profiles::Configuration.call(brand: Current.brand) }
  end
end
