class Api::V1::ReportsController < ApplicationController
  before_action :authenticate_user!

  def create
    result = Trust::ReportProfile.call(
      user: Current.user,
      brand: Current.brand,
      target_public_id: params[:profile_id],
      reason: params[:reason],
      note: params[:note]
    )

    render json: { reported: true, created: result.created }, status: result.created ? :created : :ok
  rescue Trust::AccessError => e
    render json: { error: e.code }, status: access_error_status(e.code)
  rescue Matching::InteractionError => e
    render json: { error: e.code }, status: :forbidden
  end

  private

  # Target problems fail closed as `profile_unavailable` (404), matching block;
  # a bad reason is the caller's malformed input (422).
  def access_error_status(code)
    code == :invalid_reason ? :unprocessable_entity : :not_found
  end
end
