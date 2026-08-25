class Api::V1::ProfilesController < Api::V1::InteractionController
  before_action :set_active_storage_url_options, only: :show

  # Authoritative, refreshable public detail for a single member, resolved from a
  # stable public profile UUID (as surfaced by discovery). The representation is
  # based on discovery's safe public profile plus detail-only rich sections and,
  # where the brand contract supports it, pair compatibility. Availability is
  # enforced in the domain layer
  # (Profiles::PublicProfile / Matching::VisibilityScope), never here.
  def show
    profile = Profiles::PublicProfile.call(
      user: Current.user,
      brand: Current.brand,
      public_id: params[:profile_id]
    )

    # PublicProfile has already proven the viewer is an eligible member, so this
    # is always present; it supplies the viewer-relative distance.
    viewer = Profile.kept.find_by(user: Current.user, brand: Current.brand)
    contract = profile_contract
    status = Profiles::StatusFields.call(
      viewer:, profiles: [ profile ], eligibility_policy: profile_eligibility_policy(contract)
    ).fetch(profile.id, {})
    decorations = D8n::Platform::ResponseDecorations.call(
      viewer:, profiles: [ profile ], decorators: contract&.profile&.detail_decorators || []
    ).fetch(profile.id, {})

    detail = Profiles::DetailSerializer.call(profile:, viewer:).merge(status).merge(decorations)
    detail[:verification] = { contact: { verified: status.fetch(:verified, false) } }
    compatibility = detail_compatibility(contract:, viewer:, profile:)
    detail[:compatibility] = compatibility unless compatibility == :unsupported

    render json: { profile: detail }
  rescue Profiles::PublicProfile::ViewerIneligible
    render json: { error: "discoverable_profile_required" }, status: :forbidden
  rescue Profiles::PublicProfile::Unavailable
    render json: { error: "profile_unavailable" }, status: :not_found
  end

  private

  def profile_contract
    D8n::Platform::BrandRegistry.fetch(brand: Current.brand)
  rescue D8n::Platform::BrandRegistry::UnsupportedBrand
    nil
  end

  def profile_eligibility_policy(contract)
    contract&.interaction&.eligibility_policy || Matching::EligibilityPolicy::DEFAULT
  end

  def detail_compatibility(contract:, viewer:, profile:)
    strategy = contract&.interaction&.compatibility_strategy
    return :unsupported unless strategy&.respond_to?(:for_visible_pair)

    result = strategy.for_visible_pair(brand: Current.brand, viewer:, candidate: profile)
    result.respond_to?(:public_payload) ? result.public_payload : result
  end
end
