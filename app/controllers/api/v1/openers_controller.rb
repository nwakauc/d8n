class Api::V1::OpenersController < Api::V1::InteractionController
  requires_platform_capability "match.opener"

  # Both surfaces serialize a counterpart profile (photos), so they need signed
  # media URLs.
  before_action :set_active_storage_url_options, only: [ :index, :reply ]

  # Recipient inbox: live D8N Openers awaiting the viewer's reply/decline.
  # Shares Hooks::ReceivedInbox with HooksController — same engine, same rules.
  def index
    result = Hooks::ReceivedInbox.call(
      user: Current.user, brand: Current.brand,
      cursor: params[:cursor], limit: params[:limit]
    )

    render json: {
      openers: result.hooks.map { |hook| Hooks::HookSerializer.call(hook:) },
      next_cursor: result.next_cursor
    }
  rescue Messaging::AccessError => e
    render json: { error: e.code }, status: :forbidden
  rescue Hooks::ReceivedInbox::InvalidLimit
    render json: { error: "invalid_limit" }, status: :unprocessable_entity
  rescue Hooks::HookCursor::Invalid
    render json: { error: "invalid_cursor" }, status: :unprocessable_entity
  end

  # Send the sender's one D8N Opener to a profile, selected from the brand's
  # curated catalog (GET /api/v1/profile/configuration#openers).
  def create
    result = Hooks::SendHook.call(
      user: Current.user, brand: Current.brand,
      target_public_id: params[:profile_id], opener_key: params[:opener_key]
    )

    render json: { opener: Hooks::HookSerializer.sent(hook: result.hook) }, status: :created
  rescue Matching::InteractionError => e
    render_interaction_error(e)
  rescue Messaging::MessageError => e
    render json: { error: e.code }, status: :unprocessable_entity
  rescue Matching::StrategyRegistry::UnsupportedBrand
    render json: { error: "matching_not_configured" }, status: :not_found
  end

  # Recipient's first reply — accepts the Opener and unlocks a normal conversation.
  def reply
    result = Hooks::ReplyToHook.call(
      user: Current.user, brand: Current.brand,
      hook_public_id: params[:opener_id], message: params[:message]
    )

    render json: {
      conversation: Messaging::ConversationSerializer.call(conversation: result.conversation, viewer: result.viewer),
      message: Messaging::MessageSerializer.call(message: result.message)
    }, status: :created
  rescue Messaging::AccessError => e
    render json: { error: e.code }, status: :not_found
  rescue Messaging::MessageError => e
    render json: { error: e.code }, status: :unprocessable_entity
  end

  # Recipient declines a pending Opener.
  def decline
    Hooks::DeclineHook.call(
      user: Current.user, brand: Current.brand, hook_public_id: params[:opener_id]
    )

    head :no_content
  rescue Messaging::AccessError => e
    render json: { error: e.code }, status: :not_found
  end

  private

  def render_interaction_error(error)
    case error.code
    when :profile_unavailable
      render json: { error: error.code }, status: :not_found
    when :invalid_opener
      render json: { error: error.code }, status: :unprocessable_entity
    when :hook_rate_limited
      response.set_header("Retry-After", error.retry_after.to_s) if error.retry_after
      render json: { error: error.code }, status: :too_many_requests
    else
      render json: { error: error.code }, status: :conflict
    end
  end
end
