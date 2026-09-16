class Api::V1::AiConversationsController < ApplicationController
  requires_platform_capability "ai.dating_assistant"

  before_action :authenticate_user!
  requires_platform_contract
  before_action :authorize_platform_capability!
  before_action :authorize_assistant_key!
  before_action -> { enforce_rate_limit!(:ai_message) }, only: :create_message
  # Date9ja's context builder serializes introduction/member profiles through
  # Profiles::PublicSerializer, which signs photo URLs even though the AI
  # context strips them back out — needs url_options set or it raises.
  before_action :set_active_storage_url_options, only: :create_message

  def index
    render json: { conversations: service.history.map { |conversation| Ai::ConversationSerializer.summary(conversation:) } }
  rescue Ai::ConversationService::ConversationUnavailable
    render json: { error: "assistant_unavailable" }, status: :service_unavailable
  end

  def create
    conversation = service.create_conversation!(language: params[:language].presence || "english")
    render json: { conversation: Ai::ConversationSerializer.call(conversation:) }, status: :created
  rescue Ai::ConversationService::InvalidLanguage
    render json: { error: "invalid_language" }, status: :unprocessable_entity
  rescue Ai::ConversationService::ConversationUnavailable
    render json: { error: "assistant_unavailable" }, status: :service_unavailable
  end

  def show
    render json: { conversation: Ai::ConversationSerializer.call(conversation: service.conversation!(id: params[:conversation_id])) }
  rescue Ai::ConversationService::ConversationNotFound
    render json: { error: "conversation_unavailable" }, status: :not_found
  rescue Ai::ConversationService::ConversationUnavailable
    render json: { error: "assistant_unavailable" }, status: :service_unavailable
  end

  def create_message
    result = service.send_message!(id: params[:conversation_id], content: params[:message], client_message_id: params[:client_message_id], language: params[:language])
    render json: { conversation: Ai::ConversationSerializer.call(conversation: result.conversation.reload), created: result.created },
      status: result.created ? :created : :ok
  rescue ActionController::ParameterMissing, Ai::ConversationService::InvalidMessage
    render json: { error: "invalid_message" }, status: :unprocessable_entity
  rescue Ai::ConversationService::InvalidLanguage
    render json: { error: "invalid_language" }, status: :unprocessable_entity
  rescue Ai::ConversationService::ConversationNotFound
    render json: { error: "conversation_unavailable" }, status: :not_found
  rescue Ai::ConversationService::ConversationUnavailable, Ai::ProviderUnavailable
    render json: { error: "assistant_unavailable" }, status: :service_unavailable
  end

  def update
    conversation = service.update_language!(id: params[:conversation_id], language: params[:language])
    render json: { conversation: Ai::ConversationSerializer.call(conversation:) }
  rescue Ai::ConversationService::InvalidLanguage
    render json: { error: "invalid_language" }, status: :unprocessable_entity
  rescue Ai::ConversationService::ConversationNotFound
    render json: { error: "conversation_unavailable" }, status: :not_found
  rescue Ai::ConversationService::ConversationUnavailable
    render json: { error: "assistant_unavailable" }, status: :service_unavailable
  end

  private

  def service
    @service ||= Ai::ConversationService.new(user: Current.user, brand: Current.brand, assistant_key: params[:assistant_key])
  end

  def authorize_assistant_key!
    return if AiConversation::ASSISTANT_KEYS.include?(params[:assistant_key])

    render json: { error: "assistant_not_configured" }, status: :not_found
  end
end
