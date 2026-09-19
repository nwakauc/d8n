module Admin
  # Authorized correction of a member's canonical marketplace-identity fields.
  # Writes the SAME canonical D8N representation discovery/matching already
  # reads live (Profile#gender, ProfilePreference#interested_in) -- there is no
  # separate "corrected value" the runtime has to know to prefer, so the very
  # next discovery/matching query already sees the corrected value with no
  # extra recalculation step. Every correction is additively recorded
  # (AdminIdentityCorrection) with the prior and new value, actor, reason, and
  # note, distinct from the corrected record's own current value, so history is
  # never lost even though the record itself only ever holds the latest answer.
  #
  # Existing matches/conversations/messages are untouched: D8N never
  # denormalizes gender/interested_in onto those rows, so a correction cannot
  # retroactively corrupt them.
  class CorrectProfileIdentity
    FIELDS = AdminIdentityCorrection::FIELDS

    def self.call(admin_user:, brand:, profile_public_id:, field:, value:, reason:, note: nil)
      field = field.to_s
      raise ModerationError, :invalid_field unless FIELDS.include?(field)

      profile = brand.profiles.kept.find_by(public_id: profile_public_id)
      raise ModerationError, :profile_unavailable if profile.blank?

      reason_text = normalize_reason(reason)
      raise ModerationError, :invalid_reason if reason_text.blank?

      correction = nil
      profile.with_lock do
        previous_value, record = apply(field:, profile:, value:)

        correction = AdminIdentityCorrection.create!(
          brand:, profile:, admin_user:, field:,
          previous_value: { "value" => previous_value },
          new_value: { "value" => record_value(field, record) },
          reason: reason_text, note: normalize_note(note)
        )
      end

      record_audit!(admin_user:, correction:)
      Notifications::EventPublisher.profile_updated_by_admin!(correction:)
      correction
    rescue ActiveRecord::RecordInvalid => e
      raise ModerationError, :invalid_value if e.record.is_a?(Profile) || e.record.is_a?(ProfilePreference)

      raise
    end

    def self.apply(field:, profile:, value:)
      case field
      when "gender"
        previous = profile.gender
        profile.update!(gender: value.to_s)
        [ previous, profile ]
      when "interested_in"
        preference = ProfilePreference.kept.find_or_initialize_by(brand: profile.brand, profile:)
        previous = preference.interested_in
        preference.update!(interested_in: Array(value))
        [ previous, preference ]
      end
    end
    private_class_method :apply

    def self.record_value(field, record)
      field == "gender" ? record.gender : record.interested_in
    end
    private_class_method :record_value

    def self.normalize_reason(reason)
      text = reason.to_s.strip
      return if text.blank?
      raise ModerationError, :invalid_reason if text.length > 500

      text
    end
    private_class_method :normalize_reason

    def self.normalize_note(note)
      text = note.to_s.strip
      raise ModerationError, :invalid_note if text.length > 2_000

      text.presence
    end
    private_class_method :normalize_note

    def self.record_audit!(admin_user:, correction:)
      SecurityEvent.create!(
        brand: correction.brand,
        user: admin_user.user,
        event_type: "admin.identity_corrected",
        severity: :warning,
        metadata: {
          admin_user_id: admin_user.id,
          target_profile_id: correction.profile_id,
          correction_id: correction.id,
          field: correction.field,
          has_reason: correction.reason.present?,
          has_note: correction.note.present?
        }
      )
    end
    private_class_method :record_audit!
  end
end
