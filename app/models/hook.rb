class Hook < ApplicationRecord
  belongs_to :brand
  belongs_to :sender_profile, class_name: "Profile"
  belongs_to :recipient_profile, class_name: "Profile"
  # Nil until the recipient's first reply accepts the Hook (Hooks::ReplyToHook).
  belongs_to :conversation, optional: true

  # `pending` = the sender has spent their one opener and is waiting on the
  # recipient. The first reply moves it to `accepted`; `declined` is an explicit
  # recipient decline; `expired` is past its window (also enforced lazily via
  # `live`, so a stale row can never unlock). `cancelled` is reserved for a future
  # sender-withdraw flow and is unused in V1.
  enum :status, { pending: 0, accepted: 1, declined: 2, expired: 3, cancelled: 4 }, prefix: :status

  scope :kept, -> { where(deleted_at: nil) }
  # The only state in which a Hook can be replied to, declined, or shown in the
  # inbox: still pending AND not past its expiry. Expiry is evaluated here rather
  # than trusting the status column, so no background sweep is required for
  # correctness.
  scope :live, -> { kept.status_pending.where(expires_at: Time.current..) }

  validates :public_id, presence: true, uniqueness: true, format: { with: Profile::PUBLIC_ID_FORMAT }
  validates :message, presence: true, length: { maximum: Message::MAX_BODY_LENGTH }
  validates :expires_at, presence: true
  validate :profiles_match_brand
  validate :cannot_hook_self

  before_validation :ensure_public_id, on: :create
  before_validation :ensure_expires_at, on: :create

  def live?
    status_pending? && expires_at.present? && expires_at > Time.current
  end

  private

  def ensure_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def ensure_expires_at
    self.expires_at ||= Hooks::Policy::EXPIRES_IN.from_now
  end

  def profiles_match_brand
    return if sender_profile.blank? || recipient_profile.blank?
    return if sender_profile.brand_id == brand_id && recipient_profile.brand_id == brand_id

    errors.add(:base, "profiles must belong to the same brand")
  end

  def cannot_hook_self
    errors.add(:recipient_profile, "cannot be the sender profile") if sender_profile_id == recipient_profile_id
  end
end
