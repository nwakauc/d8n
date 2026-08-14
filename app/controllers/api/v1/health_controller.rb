class Api::V1::HealthController < ApplicationController
  skip_before_action :set_current_context

  def show
    readiness = Infrastructure::Readiness.call
    unless readiness.ready?
      Rails.logger.error(
        "readiness_check_failed dependencies=#{readiness.failed_dependencies.join(',')}"
      )
    end

    render json: {
      status: readiness.ready? ? "ok" : "degraded",
      app: "d8n",
      api_version: "v1",
      checks: readiness.checks
    }, status: readiness.ready? ? :ok : :service_unavailable
  end
end
