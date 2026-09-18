class Api::V1::ConversationsController < Api::V1::InteractionController
  requires_platform_capability "chat.conversation"

  before_action :set_active_storage_url_options, only: %i[index create]

  def index
    result = Messaging::ConversationList.call(
      user: Current.user,
      brand: Current.brand,
      cursor: params[:cursor],
      limit: params[:limit]
    )

    unread = Messaging::ReadState.snapshot(user: Current.user, brand: Current.brand)
    render json: {
      conversations: result.conversations.map do |conversation|
        Messaging::ConversationSerializer.call(
          conversation:,
          viewer: result.viewer,
          last_message: result.last_messages[conversation.id],
          unread_message_count: unread[:conversations].fetch(conversation.public_id, 0)
        )
      end,
      next_cursor: result.next_cursor
    }
  rescue Messaging::AccessError => e
    render json: { error: e.code }, status: :forbidden
  rescue Messaging::ConversationList::InvalidLimit
    render json: { error: "invalid_limit" }, status: :unprocessable_entity
  rescue Messaging::ConversationCursor::Invalid
    render json: { error: "invalid_cursor" }, status: :unprocessable_entity
  end

  def create
    result = Messaging::StartConversation.call(
      user: Current.user,
      brand: Current.brand,
      match_public_id: params[:match_id]
    )

    render json: {
      conversation: Messaging::ConversationSerializer.call(
        conversation: result.conversation,
        viewer: result.viewer
      ),
      created: result.created
    }, status: result.created ? :created : :ok
  rescue Messaging::AccessError => e
    render json: { error: e.code }, status: :not_found
  end
end
