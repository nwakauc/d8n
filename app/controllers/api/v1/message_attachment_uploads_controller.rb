class Api::V1::MessageAttachmentUploadsController < Api::V1::InteractionController
  requires_platform_capability "chat.message.media"

  before_action -> { enforce_rate_limit!(:chat_media_upload_intent) }, only: :create
  before_action :set_active_storage_url_options, only: :create

  # Control plane: authorize the caller against ConversationAccess (participant,
  # active match, availability, both block directions — the exact same gate
  # messages themselves use) and return a short-lived presigned PUT so the
  # client uploads bytes directly to private R2. D8N allocates the object
  # identity; the client never sees R2 credentials or chooses the object key.
  def create
    intent = Messaging::MessageAttachmentUpload.create_intent(
      user: Current.user,
      brand: Current.brand,
      conversation_public_id: params[:conversation_id],
      media_kind: upload_params[:media_kind],
      filename: upload_params[:filename],
      byte_size: upload_params.fetch(:byte_size),
      checksum: upload_params.fetch(:checksum),
      content_type: upload_params.fetch(:content_type)
    )

    render json: { upload: intent }, status: :created
  rescue Messaging::AccessError => e
    render json: { error: e.code }, status: :not_found
  rescue ActionController::ParameterMissing
    render json: { error: "upload_parameters_required" }, status: :unprocessable_entity
  rescue Messaging::MessageAttachmentUpload::InvalidMediaKind
    render json: { error: "invalid_media_kind" }, status: :unprocessable_entity
  rescue Messaging::MessageAttachmentUpload::InvalidContentType
    render json: {
      error: "unsupported_content_type",
      allowed_content_types: Messaging::MessageAttachmentUpload::ALLOWED_CONTENT_TYPES
    }, status: :unprocessable_entity
  rescue Messaging::MessageAttachmentUpload::InvalidSize
    render json: { error: "invalid_byte_size", byte_size_limits: Messaging::MessageAttachmentUpload::MAX_FILE_SIZE },
      status: :unprocessable_entity
  rescue Messaging::MessageAttachmentUpload::InvalidUpload
    render json: { error: "checksum_required" }, status: :unprocessable_entity
  end

  private

  def upload_params
    params.permit(:media_kind, :filename, :byte_size, :checksum, :content_type)
  end
end
