class Api::V1::MessageAttachmentsController < Api::V1::InteractionController
  requires_platform_capability "chat.message.media"

  # "Delete for everyone": only the sender may remove their own attachment.
  # Deleting revokes future signed URLs immediately (Messaging::MessageSerializer
  # stops issuing view/download/poster URLs for a deleted attachment) and
  # purges the underlying R2 object(s) as soon as Active Storage's purge queue
  # runs — the same revocation speed the rest of D8N media already offers.
  def destroy
    result = Messaging::DeleteAttachment.call(
      user: Current.user,
      brand: Current.brand,
      conversation_public_id: params[:conversation_id],
      message_public_id: params[:message_id],
      attachment_public_id: params[:id]
    )

    render json: { attachment: { id: result.attachment.public_id, deleted: true } }
  rescue Messaging::AccessError => e
    render json: { error: e.code }, status: :not_found
  end
end
