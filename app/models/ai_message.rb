class AiMessage < ApplicationRecord
  MAX_CONTENT_LENGTH = 4_000

  belongs_to :ai_conversation

  enum :role, { user: 0, assistant: 1 }, prefix: true

  validates :content, presence: true, length: { maximum: MAX_CONTENT_LENGTH }
  validates :client_message_id, length: { maximum: 180 }, allow_blank: true
  validate :provider_metadata_is_assistant_only

  private

  def provider_metadata_is_assistant_only
    return if !role_assistant? || (provider.present? && model.present?)

    errors.add(:base, "assistant messages require provider and model")
  end
end
