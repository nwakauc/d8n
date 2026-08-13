require "yaml"

class Api::V1::OpenapiController < ApplicationController
  CONTRACT_PATH = Rails.root.join("docs/api/openapi.yaml")

  def show
    response.headers["Cache-Control"] = "public, max-age=300"
    render json: YAML.safe_load_file(CONTRACT_PATH, aliases: false)
  end
end
