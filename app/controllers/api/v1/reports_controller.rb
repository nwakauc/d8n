class Api::V1::ReportsController < ApplicationController
  before_action :authenticate_user!
  # One report abuse ceiling for every reporting surface (profile + content). The
  # generic limiter is the OUTER guard; per-target duplicate suppression is a
  # separate domain invariant handled in Trust::FileReport.
  before_action -> { enforce_rate_limit!(:report_profile) }, only: %i[create profile]

  # Generic content-level reporting: POST /api/v1/reports
  # { target_type: "message"|"profile_media"|"hook"|"profile", target_id, reason,
  #   details?, block? }. Reveals only that the report was received.
  def create
    result = Trust::FileReport.call(
      user: Current.user,
      brand: Current.brand,
      target_type: params[:target_type].to_s,
      target_id: params[:target_id],
      reason: params[:reason],
      details: params[:details],
      block: ActiveModel::Type::Boolean.new.cast(params[:block])
    )

    render json: {
      report: { status: "received" },
      created: result.created,
      blocked: result.blocked
    }, status: result.created ? :created : :ok
  rescue Trust::AccessError => e
    render json: { error: e.code }, status: access_error_status(e.code)
  rescue Matching::InteractionError => e
    render json: { error: e.code }, status: :forbidden
  end

  # Legacy, backward-compatible profile report: POST /profiles/:profile_id/report.
  # Contract is unchanged (returns { reported, created }, code `profile_unavailable`).
  def profile
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

  # Malformed caller input (bad reason / unknown target type) is 422; anything
  # about the target itself fails closed as a neutral 404 so nonexistent,
  # inaccessible, and cross-brand targets are indistinguishable (no enumeration).
  def access_error_status(code)
    case code
    when :invalid_reason, :invalid_target_type then :unprocessable_entity
    else :not_found
    end
  end
end
