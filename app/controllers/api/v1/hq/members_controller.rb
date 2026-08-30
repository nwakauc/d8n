module Api
  module V1
    module Hq
      # Member 360: look up one member within the moderator's brand by email,
      # phone, or profile id, and read their operational state. Every action
      # here is a sensitive read and is individually audited (HQ-106) -- see
      # SECURITY-AND-RBAC.md #4.
      class MembersController < BaseController
        requires_admin_capability ::Admin::Capabilities::MEMBER_SENSITIVE_READ, only: %i[index show]
        requires_admin_capability ::Admin::Capabilities::MEMBER_SECURITY_READ,
          only: %i[security_events auth_attempts enforcements]
        requires_admin_capability ::Admin::Capabilities::DISCOVERY_DIAGNOSTICS_READ,
          only: :discovery_diagnostic

        CODE_STATUS = {
          member_unavailable: :not_found,
          profile_unavailable: :not_found,
          invalid_limit: :unprocessable_entity
        }.freeze

        rescue_from ::Hq::HqError, with: :render_hq_error
        rescue_from ::Hq::Cursor::Invalid do
          render json: { error: "invalid_cursor" }, status: :unprocessable_entity
        end

        before_action :resolve_member, except: :index

        def index
          result = ::Hq::MemberDirectory.call(
            brand: Current.brand,
            cursor: params[:cursor],
            limit: params[:limit],
            status: params[:status]
          )
          memberships = result.members
          profile_ids = memberships.filter_map { |membership| membership.profile&.id }
          user_ids = memberships.map(&:user_id)
          report_counts = Report.where(brand: Current.brand, reported_profile_id: profile_ids).group(:reported_profile_id).count
          pending_photo_counts = ProfilePhoto.where(profile_id: profile_ids, status: :pending_review).group(:profile_id).count
          active_enforcements = AccountEnforcement.active.where(brand: Current.brand, user_id: user_ids).pluck(:user_id).index_with(true)
          audit!("hq.member_directory_viewed", extra: { status: params[:status].presence || "all" })

          render json: {
            members: memberships.map do |membership|
              ::Hq::MemberDirectorySerializer.call(
                membership:, report_counts:, pending_photo_counts:, active_enforcements:
              )
            end,
            next_cursor: result.next_cursor
          }
        end
        before_action :require_profile, only: :discovery_diagnostic

        def show
          sections = ::Hq::Member360::Load.call(brand: Current.brand, brand_membership: @brand_membership)
          audit!("hq.member_360_viewed")

          render json: { member: member_summary, sections: }
        end

        def security_events
          result = ::Hq::SecurityEventHistory.call(
            brand: Current.brand, user: @user, cursor: params[:cursor], limit: params[:limit]
          )
          audit!("hq.member_security_events_viewed")

          render json: {
            security_events: result.events.map { |event| ::Hq::SecurityEventSerializer.call(event:) },
            next_cursor: result.next_cursor
          }
        end

        def auth_attempts
          result = ::Hq::AuthAttemptHistory.call(
            brand: Current.brand, user: @user, cursor: params[:cursor], limit: params[:limit]
          )
          audit!("hq.member_auth_attempts_viewed")

          render json: {
            auth_attempts: result.attempts.map { |attempt| ::Hq::AuthAttemptSerializer.call(attempt:) },
            next_cursor: result.next_cursor
          }
        end

        def discovery_diagnostic
          result = ::Hq::Member360::DiscoveryDiagnostic.call(brand: Current.brand, profile: @profile)
          audit!("hq.member_discovery_diagnostic_viewed")

          render json: {
            eligible: result.eligible,
            ineligibility_reason: result.ineligibility_reason,
            stages: result.stages.map { |stage| { stage: stage.stage, description: stage.description, candidate_count: stage.candidate_count } }
          }
        end

        def enforcements
          result = ::Hq::EnforcementHistory.call(
            brand: Current.brand, user: @user, cursor: params[:cursor], limit: params[:limit]
          )
          audit!("hq.member_enforcements_viewed")

          render json: {
            enforcements: result.enforcements.map { |enforcement| ::Admin::EnforcementSerializer.call(enforcement:) },
            next_cursor: result.next_cursor
          }
        end

        private

        def resolve_member
          result = ::Hq::Identity::Lookup.call(brand: Current.brand, lookup: params[:lookup])
          raise ::Hq::HqError, :member_unavailable if result.blank?

          @user = result.user
          @brand_membership = result.brand_membership
          @profile = result.profile
        end

        def require_profile
          raise ::Hq::HqError, :profile_unavailable if @profile.blank?
        end

        def member_summary
          {
            user_id: @user.id,
            profile_id: @profile&.public_id,
            brand: Current.brand.slug,
            membership_status: @brand_membership.status
          }
        end

        def audit!(event_type, extra: {})
          ::Hq::SensitiveReadAudit.record(
            admin_user: Current.admin_user,
            brand: Current.brand,
            user: @user,
            session: Current.session,
            event_type:,
            extra:
          )
        end

        def render_hq_error(error)
          render json: { error: error.code }, status: CODE_STATUS.fetch(error.code, :unprocessable_entity)
        end
      end
    end
  end
end
