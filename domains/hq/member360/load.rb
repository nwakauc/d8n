module Hq
  module Member360
    # Six-section aggregation of one member's operational state, scoped to one
    # brand: Identity, Profile, Product, Comms, Safety, Activity. Every section
    # is a thin, bounded read against an existing table -- no new
    # instrumentation, no writes. Full paginated history for security events,
    # auth attempts, and enforcements lives behind their own HQ endpoints
    # (Hq::SecurityEventHistory / Hq::AuthAttemptHistory / Hq::EnforcementHistory),
    # not here -- this returns only a bounded, recent summary of each.
    class Load
      RECENT_IDENTIFIERS_LIMIT = 10
      RECENT_SESSIONS_LIMIT = 5
      RECENT_PHOTOS_LIMIT = 20
      RECENT_CONVERSATIONS_LIMIT = 5
      RECENT_NOTIFICATIONS_LIMIT = 10
      NOTIFICATION_SCAN_LIMIT = 200
      RECENT_REPORTS_LIMIT = 5
      RECENT_AUTH_ATTEMPTS_LIMIT = 5
      RECENT_SECURITY_EVENTS_LIMIT = 5

      def self.call(brand:, brand_membership:)
        new(brand:, brand_membership:).call
      end

      def initialize(brand:, brand_membership:)
        @brand = brand
        @brand_membership = brand_membership
        @user = brand_membership.user
        @profile = brand.profiles.kept.find_by(brand_membership:)
      end

      def call
        {
          identity: identity_section,
          profile: profile_section,
          product: product_section,
          comms: comms_section,
          safety: safety_section,
          activity: activity_section
        }
      end

      private

      attr_reader :brand, :brand_membership, :user, :profile

      # --- Identity ---------------------------------------------------------

      def identity_section
        identifiers = user.identity_identifiers.kept.contact.order(created_at: :asc).limit(RECENT_IDENTIFIERS_LIMIT)
        sessions = Session.where(user:, brand:).order(last_used_at: :desc).limit(RECENT_SESSIONS_LIMIT)

        {
          user_id: user.id,
          user_status: user.status,
          first_name: user.first_name,
          last_name: user.last_name,
          user_created_at: user.created_at.iso8601,
          membership_status: brand_membership.status,
          member_since: brand_membership.created_at.iso8601,
          identifiers: identifiers.map { |identifier| identifier_summary(identifier) },
          recent_sessions: sessions.map { |session| session_summary(session) }
        }
      end

      def identifier_summary(identifier)
        {
          kind: identifier.kind,
          value: identifier.normalized_value,
          verified_at: identifier.verified_at&.iso8601,
          last_seen_at: identifier.last_seen_at&.iso8601
        }
      end

      def session_summary(session)
        {
          device_name: session.device_name,
          ip_address: session.ip_address,
          last_used_at: session.last_used_at.iso8601,
          expires_at: session.expires_at.iso8601,
          revoked_at: session.revoked_at&.iso8601
        }
      end

      # --- Profile ------------------------------------------------------------

      def profile_section
        return { exists: false } if profile.blank?

        onboarding = Profiles::OnboardingStatus.call(user:, brand:)
        preference = ProfilePreference.kept.find_by(profile:)
        photos = profile.profile_photos.kept.order(:position).limit(RECENT_PHOTOS_LIMIT)

        {
          exists: true,
          public_id: profile.public_id,
          display_name: profile.display_name,
          status: profile.status,
          visibility: profile.visibility,
          gender: profile.gender,
          birthdate: profile.birthdate,
          country_code: profile.country_code,
          city: profile.city,
          created_at: profile.created_at.iso8601,
          onboarding_state: onboarding[:state],
          onboarding_next_step: onboarding[:next_step],
          onboarding_completion_percent: onboarding.dig(:completion, :percent),
          photo_count: profile.profile_photos.kept.count,
          photos: photos.map { |photo| photo_summary(photo) },
          preference: preference.blank? ? nil : preference_summary(preference)
        }
      end

      def photo_summary(photo)
        {
          id: photo.public_id,
          position: photo.position,
          status: photo.status,
          visibility: photo.visibility,
          processing_state: photo.processing_state
        }
      end

      def preference_summary(preference)
        {
          min_age: preference.min_age,
          max_age: preference.max_age,
          max_distance_km: preference.max_distance_km,
          relationship_intent: preference.relationship_intent,
          interested_in: preference.interested_in,
          country: preference.country
        }
      end

      # --- Product --------------------------------------------------------

      def product_section
        return empty_product_section if profile.blank?

        {
          likes_given: profile.likes_given.kept.count,
          likes_received: profile.likes_received.kept.count,
          matches_active: active_matches_count,
          hooks_sent: Hook.kept.where(sender_profile: profile).count,
          hooks_received: Hook.kept.where(recipient_profile: profile).count,
          hooks_live_sent: Hook.live.where(sender_profile: profile).count,
          hooks_live_received: Hook.live.where(recipient_profile: profile).count,
          hook_tonight_live: HookTonightState.live.where(brand:, profile:).exists?,
          conversations_count: profile.conversations.kept.count,
          recent_conversations: recent_conversations,
          blocks_given: profile.blocks_initiated.kept.count,
          blocks_received: profile.blocks_received.kept.count
        }
      end

      def empty_product_section
        {
          likes_given: 0, likes_received: 0, matches_active: 0, hooks_sent: 0, hooks_received: 0,
          hooks_live_sent: 0, hooks_live_received: 0, hook_tonight_live: false, conversations_count: 0,
          recent_conversations: [], blocks_given: 0, blocks_received: 0
        }
      end

      def active_matches_count
        Match.kept.status_active.where(profile_a_id: profile.id)
          .or(Match.kept.status_active.where(profile_b_id: profile.id))
          .count
      end

      def recent_conversations
        profile.conversations.kept.order(created_at: :desc).limit(RECENT_CONVERSATIONS_LIMIT).map do |conversation|
          { id: conversation.public_id, status: conversation.status, created_at: conversation.created_at.iso8601 }
        end
      end

      # --- Comms ------------------------------------------------------------

      def comms_section
        deliveries = NotificationDelivery.where(brand:, user:)
          .order(created_at: :desc)
          .limit(NOTIFICATION_SCAN_LIMIT)
          .to_a

        {
          delivery_counts_by_status: deliveries.map(&:status).tally,
          delivery_counts_by_channel: deliveries.map(&:channel).tally,
          recent_deliveries: deliveries.first(RECENT_NOTIFICATIONS_LIMIT).map { |delivery| delivery_summary(delivery) }
        }
      end

      def delivery_summary(delivery)
        {
          channel: delivery.channel,
          status: delivery.status,
          provider: delivery.provider,
          sent_at: delivery.sent_at&.iso8601,
          failed_at: delivery.failed_at&.iso8601,
          error_code: delivery.error_code,
          created_at: delivery.created_at.iso8601
        }
      end

      # --- Safety -------------------------------------------------------------

      def safety_section
        {
          reports_filed_count: profile.blank? ? 0 : Report.where(brand:, reporter_profile: profile).count,
          reports_received_count: profile.blank? ? 0 : Report.where(brand:, reported_profile: profile).count,
          recent_reports: recent_reports,
          active_enforcement: active_enforcement_summary,
          enforcement_count: AccountEnforcement.where(brand:, user:).count,
          account_closure: account_closure_summary
        }
      end

      def recent_reports
        return [] if profile.blank?

        Report.where(brand:)
          .where("reporter_profile_id = :id OR reported_profile_id = :id", id: profile.id)
          .order(created_at: :desc)
          .limit(RECENT_REPORTS_LIMIT)
          .map { |report| report_summary(report) }
      end

      def report_summary(report)
        {
          id: report.id,
          status: report.status,
          reason: report.reason,
          target_type: report.target_type,
          direction: report.reporter_profile_id == profile.id ? "filed" : "received",
          created_at: report.created_at.iso8601
        }
      end

      def active_enforcement_summary
        enforcement = AccountEnforcement.active.find_by(brand:, user:)
        return nil if enforcement.blank?

        ::Admin::EnforcementSerializer.call(enforcement:)
      end

      def account_closure_summary
        closure = AccountClosure.find_by(brand:, brand_membership:)
        return nil if closure.blank?

        { media_purge_state: closure.media_purge_state, created_at: closure.created_at.iso8601 }
      end

      # --- Activity -----------------------------------------------------------

      def activity_section
        auth_attempts = AuthAttempt.where(brand:, user:).order(created_at: :desc)
        security_events = SecurityEvent.where(brand:, user:).order(created_at: :desc)
        last_success = auth_attempts.where(result: :succeeded).first

        {
          last_login_at: last_success&.created_at&.iso8601,
          recent_auth_attempts: auth_attempts.limit(RECENT_AUTH_ATTEMPTS_LIMIT).map { |attempt| auth_attempt_summary(attempt) },
          recent_security_events: security_events.limit(RECENT_SECURITY_EVENTS_LIMIT).map { |event| security_event_summary(event) }
        }
      end

      def auth_attempt_summary(attempt)
        { kind: attempt.kind, result: attempt.result, ip_address: attempt.ip_address, created_at: attempt.created_at.iso8601 }
      end

      def security_event_summary(event)
        { event_type: event.event_type, severity: event.severity, created_at: event.created_at.iso8601 }
      end
    end
  end
end
