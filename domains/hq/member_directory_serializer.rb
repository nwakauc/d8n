module Hq
  class MemberDirectorySerializer
    def self.call(membership:, report_counts: {}, pending_photo_counts: {}, active_enforcements: {}, contact_verification: {})
      profile = membership.profile
      user = membership.user

      {
        user_id: user.id,
        profile_id: profile&.public_id,
        display_name: profile&.display_name,
        user_status: user.status,
        membership_status: membership.status,
        profile_status: profile&.status,
        profile_visibility: profile&.visibility,
        joined_at: membership.created_at.iso8601,
        user_created_at: user.created_at.iso8601,
        last_active_at: membership.last_active_at&.iso8601,
        contact_verification: contact_verification.fetch(user.id, { email: false, phone: false }),
        reports_received_count: report_counts[profile&.id].to_i,
        pending_photo_count: pending_photo_counts[profile&.id].to_i,
        active_enforcement: active_enforcements[user.id].present?
      }
    end
  end
end
