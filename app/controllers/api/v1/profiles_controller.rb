class Api::V1::ProfilesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_active_storage_url_options, only: :show

  # Authoritative, refreshable public detail for a single member, resolved from a
  # stable public profile UUID (as surfaced by discovery). The representation is
  # identical to discovery's safe public profile, minus the ranking-only
  # compatibility payload. Availability is enforced in the domain layer
  # (Profiles::PublicProfile / Matching::VisibilityScope), never here.
  def show
    profile = Profiles::PublicProfile.call(
      user: Current.user,
      brand: Current.brand,
      public_id: params[:profile_id]
    )

    render json: { profile: Profiles::PublicSerializer.call(profile:) }
  rescue Profiles::PublicProfile::ViewerIneligible
    render json: { error: "discoverable_profile_required" }, status: :forbidden
  rescue Profiles::PublicProfile::Unavailable
    render json: { error: "profile_unavailable" }, status: :not_found
  end
end
