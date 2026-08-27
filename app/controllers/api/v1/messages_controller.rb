class Api::V1::MessagesController < Api::V1::InteractionController
  requires_platform_capability "chat.message.text"

  before_action -> { enforce_rate_limit!(:send_message) }, only: :create
  before_action -> { enforce_rate_limit!(:chat_media_attach) }, only: :create, if: :attachment_uploads_present?
  before_action :set_active_storage_url_options, only: %i[index create]

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
    authorize_media_capability! if attachment_uploads_present?

    result = Messaging::SendMessage.call(
      user: Current.user,
      brand: Current.brand,
      conversation_public_id: params[:conversation_id],
      body: params[:body],
      attachment_uploads: attachment_uploads_params,
      reply_to_message_id: params[:reply_to_message_id]
    )

    render json: { message: Messaging::MessageSerializer.call(message: result.message) }, status: :created
  rescue Messaging::AccessError => e
    render json: { error: e.code }, status: :not_found
  rescue Messaging::MessageError => e
    render json: { error: e.code }, status: :unprocessable_entity
  rescue Messaging::MessageAttachmentUpload::TooManyAttachments
    render json: {
      error: "too_many_attachments", max_count: Messaging::MessageAttachmentUpload::MAX_ATTACHMENTS_PER_MESSAGE
    }, status: :unprocessable_entity
  rescue Messaging::MessageAttachmentUpload::InvalidMediaKind
    render json: { error: "invalid_media_kind" }, status: :unprocessable_entity
  rescue Messaging::MessageAttachmentUpload::AlreadyAttached
    render json: { error: "upload_already_used" }, status: :unprocessable_entity
  rescue Messaging::MessageAttachmentUpload::MissingObject
    render json: { error: "upload_not_found" }, status: :unprocessable_entity
  rescue Messaging::MessageAttachmentUpload::InvalidObject
    render json: { error: "invalid_attachment" }, status: :unprocessable_entity
  rescue Messaging::MessageAttachmentUpload::InvalidSize, Messaging::MessageAttachmentUpload::InvalidUpload
    render json: { error: "invalid_attachment_upload" }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_message", details: e.record.errors.to_hash }, status: :unprocessable_entity
  rescue D8n::Platform::CapabilityAccess::NotConfigured => e
    render json: { error: e.code }, status: :not_found
  end

  private

  def attachment_uploads_params
    permitted = params.permit(attachment_uploads: %i[ signed_id media_kind poster_signed_id ])
    permitted[:attachment_uploads] || []
  end

  def attachment_uploads_present?
    attachment_uploads_params.present?
  end

  def authorize_media_capability!
    D8n::Platform::CapabilityAccess.authorize!(contract: Current.platform_contract, capability: "chat.message.media")
  end
end
