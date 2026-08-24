class Api::V1::HookTonightController < Api::V1::InteractionController
  requires_platform_capability "match.hook_tonight"

  # Reading one's own state is capability-gated, while deactivation deliberately
  # remains available so legacy/corrective state can always be cleared safely.
  skip_before_action :authorize_platform_capability!, only: :destroy
  skip_before_action :authorize_interaction_access!, only: %i[show destroy]
  before_action -> { enforce_rate_limit!(:hook_tonight_activation) }, only: %i[create destroy]
  before_action -> { enforce_rate_limit!(:hook_tonight_discovery) }, only: :discovery
  # Discovery serializes counterpart profiles (photos), so it needs signed media URLs.
  before_action :set_active_storage_url_options, only: :discovery

  # Authoritative current availability so the client can render the correct CTA
  # ("🔥 Hook Tonight" vs "🔥 You're available tonight") without inferring
  # liveness from a stale value.
  def show
    render json: state_json(HookTonight::CurrentState.call(user: Current.user, brand: Current.brand))
  end

  # Activate (or refresh) Hook Tonight availability for the current member.
  def create
    result = HookTonight::Activate.call(
      user: Current.user, brand: Current.brand, intent: params[:intent]
    )
    render json: state_json(
      HookTonight::CurrentState::Result.new(active: true, expires_at: result.state.expires_at, intent: result.state.intent)
    ), status: :created
  rescue HookTonight::Policy::InvalidIntent
    render json: { error: "invalid_intent" }, status: :unprocessable_entity
  rescue Matching::InteractionError
    # Viewer is not an eligible/discoverable member (suspended, closed, incomplete).
    render json: { error: "discoverable_profile_required" }, status: :forbidden
  end

  # Deactivate Hook Tonight. Idempotent: repeat calls are safe no-ops.
  def destroy
    HookTonight::Deactivate.call(user: Current.user, brand: Current.brand)
    head :no_content
  end

  # The Hook Tonight discovery pool — same shape/semantics as GET /discovery,
  # narrowed to members who are live in the availability pool.
  def discovery
    result = HookTonight::Discovery.call(
      user: Current.user,
      brand: Current.brand,
      cursor: params[:cursor],
      limit: params[:limit],
      facet_params: request.query_parameters
    )
    statuses = Profiles::StatusFields.call(
      viewer: result.viewer, profiles: result.profiles, eligibility_policy: result.eligibility_policy
    )
    decorations = D8n::Platform::ResponseDecorations.call(
      viewer: result.viewer, profiles: result.profiles, decorators: result.decorators
    )
    render json: {
      profiles: result.profiles.map do |profile|
        status = statuses.fetch(profile.id, {}).merge(decorations.fetch(profile.id, {}))
        Matching::CandidateSerializer.call(profile:, strategy: result.strategy, status:)
      end,
      next_cursor: result.next_cursor
    }
  rescue HookTonight::Discovery::NotActivated
    render json: { error: "hook_tonight_required" }, status: :forbidden
  rescue Matching::Discovery::ViewerIneligible
    render json: { error: "discoverable_profile_required" }, status: :forbidden
  rescue Matching::Discovery::InvalidLimit
    render json: { error: "invalid_limit" }, status: :unprocessable_entity
  rescue Matching::Cursor::Invalid
    render json: { error: "invalid_cursor" }, status: :unprocessable_entity
  rescue Matching::StrategyRegistry::UnsupportedMode
    render json: { error: "invalid_mode" }, status: :unprocessable_entity
  rescue Matching::FacetFilter::InvalidFilter
    render json: { error: "invalid_filter" }, status: :unprocessable_entity
  rescue Matching::StrategyRegistry::UnsupportedBrand
    render json: { error: "matching_not_configured" }, status: :not_found
  end

  private

  def state_json(state)
    {
      active: state.active,
      expires_at: state.expires_at&.iso8601,
      intent: state.intent
    }
  end
end
