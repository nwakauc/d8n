class Api::V1::MessagesController < Api::V1::InteractionController
  requires_platform_capability "chat.message.text"

  before_action -> { enforce_rate_limit!(:send_message) }, only: :create

  def index
    result = Messaging::MessageList.call(
      user: Current.user,
      brand: Current.brand,
      conversation_public_id: params[:conversation_id],
      cursor: params[:cursor],
      limit: params[:limit]
    )

    render json: {
      messages: result.messages.map { |message| Messaging::MessageSerializer.call(message:) },
      next_cursor: result.next_cursor
    }
  rescue Messaging::AccessError => e
    render json: { error: e.code }, status: :not_found
  rescue Messaging::MessageList::InvalidLimit
    render json: { error: "invalid_limit" }, status: :unprocessable_entity
  rescue Messaging::MessageCursor::Invalid
    render json: { error: "invalid_cursor" }, status: :unprocessable_entity
  end

  def create
    result = Messaging::SendMessage.call(
      user: Current.user,
      brand: Current.brand,
      conversation_public_id: params[:conversation_id],
      body: params[:body]
    )

    render json: { message: Messaging::MessageSerializer.call(message: result.message) }, status: :created
  rescue Messaging::AccessError => e
    render json: { error: e.code }, status: :not_found
  rescue Messaging::MessageError => e
    render json: { error: e.code }, status: :unprocessable_entity
  end
end
