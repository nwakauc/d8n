class Api::V1::VersionController < ApplicationController
  skip_before_action :set_current_context

  def show
    render json: D8n::ReleaseIdentity.call
  end
end
