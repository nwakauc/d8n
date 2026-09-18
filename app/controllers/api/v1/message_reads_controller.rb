class Api::V1::MessageReadsController < Api::V1::InteractionController
  requires_platform_capability "chat.conversation"

  def index
    render json: Messaging::ReadState.snapshot(user: Current.user, brand: Current.brand)
  end

  def create
    render json: Messaging::ReadState.mark!(user: Current.user, brand: Current.brand,
      conversation_public_id: params[:conversation_id], message_ids: params[:message_ids])
  rescue Messaging::AccessError => e
    render json: { error: e.code }, status: :not_found
  rescue Messaging::ReadState::InvalidMessages
    render json: { error: "invalid_message_ids" }, status: :unprocessable_entity
  end
end
