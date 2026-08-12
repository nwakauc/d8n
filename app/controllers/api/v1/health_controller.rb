class Api::V1::HealthController < ApplicationController
  def show
    render json: {
      status: "ok",
      app: "d8n",
      api_version: "v1"
    }
  end
end
