class MessageAttachment < ApplicationRecord
  belongs_to :brand
  belongs_to :message

  # RAW ORIGINAL: the sender's untrusted upload. Private, NEVER exposed to the
  # recipient directly (see #deliverable? and Messaging::MessageSerializer) —
  # kept internally only for reprocessing/report evidence/moderation, unlike
  # ProfilePhoto which purges it. For video it is also the source Media::
  # VideoProcessor re-derives from if the playback rendition is ever
  # regenerated.
  has_one_attached :original
  # INLINE-VIEW RENDITION: for images, a decoded/re-encoded, metadata-stripped,
  # bandwidth-friendly derivative (Media::ImageProcessor::DISPLAY_MAX_DIMENSION).
  # For video, the browser/mobile-compatible H.264/AAC MP4 playback rendition
  # (Media::VideoProcessor) — a fresh transcoded blob when the original needed
  # conversion, or the SAME blob as `original` when ffprobe confirms it was
  # already H.264/AAC/MP4 (no unnecessary transcode).
  has_one_attached :rendition
  # DOWNLOAD RENDITION: images only. A second, higher-fidelity but still fully
  # sanitized (EXIF/GPS/ICC-stripped, re-encoded) derivative served on explicit
  # "download" — the recipient never receives the sender's untouched original
  # (see Messaging::MessageSerializer). Video download continues to serve
  # `original`: compressed video bytes carry materially different privacy risk
  # than a camera photo's EXIF GPS block, and is out of this ticket's scope.
  has_one_attached :download_rendition
  # POSTER: video only. Server-generated during processing (Media::VideoProcessor
  # frame extraction, re-encoded through Media::ImageProcessor for the same
  # safety treatment as any other image) — the production source of truth. A
  # client-supplied poster (Messaging::MessageAttachmentUpload#attach_poster!)
  # may still be attached immediately at send time for a fast local preview,
  # but is always superseded here once processing completes; #deliverable?
  # requires the SERVER poster, not merely that some poster is attached.
  has_one_attached :poster

  enum :media_kind, { image: 0, video: 1 }
  enum :processing_state, { pending: 0, processing: 1, ready: 2, failed: 3 }, prefix: :processing

  scope :kept, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position, :id) }
  # Eligible for delivery to conversation participants: not deleted and every
  # derivative the media kind requires actually exists. There is no moderation
  # gate here — see class comment on
  # domains/messaging/message_attachment_upload.rb for the risk/tradeoff.
  scope :deliverable, -> { kept.processing_ready }

  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :media_kind, presence: true
  validate :message_matches_brand

  before_validation :ensure_public_id, on: :create

  def kept?
    deleted_at.nil?
  end

  # `ready` means a usable playback rendition (and, for video, a server
  # poster) actually exist — not merely that the original container passed
  # validation. Image additionally requires the sanitized download rendition,
  # so a recipient can never be offered a download link that falls back to
  # the raw original.
  def deliverable?
    return false unless kept? && processing_ready? && rendition.attached?
    return download_rendition.attached? if image?

    poster.attached?
  end

  private

  def ensure_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def message_matches_brand
    return if message.blank?
    return if message.brand_id == brand_id

    errors.add(:message, "must belong to the same brand")
  end
end
