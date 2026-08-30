module Api
  module V1
    module Hq
      # Read-only Phase 2 Trust & Safety command surface. Existing moderation
      # writes remain under /api/v1/admin and continue to use their established
      # domain services and audit behavior.
      class TrustSafetyController < BaseController
        requires_admin_capability ::Admin::Capabilities::TRUST_SAFETY_READ

        CODE_STATUS = {
          invalid_filter: :unprocessable_entity,
          invalid_limit: :unprocessable_entity
        }.freeze

        rescue_from ::Hq::HqError, with: :render_hq_error
        rescue_from ::Hq::TrustSafety::EnforcementCursor::Invalid do
          render json: { error: "invalid_cursor" }, status: :unprocessable_entity
        end

        def overview
          result = ::Hq::TrustSafety::Overview.call(brand: Current.brand)
          audit!("hq.trust_safety_overview_viewed")

          render json: { overview: overview_payload(result) }
        end

        def repeat_offenders
          result = ::Hq::TrustSafety::RepeatOffenders.call(brand: Current.brand, limit: params[:limit])
          audit!("hq.trust_safety_repeat_offenders_viewed")

          render json: {
            repeat_offenders: result.offenders.map { |offender| offender_payload(offender) },
            minimum_reports: result.minimum_reports,
            truncated: result.truncated
          }
        end

        def enforcements
          result = ::Hq::TrustSafety::EnforcementHistory.call(
            brand: Current.brand, state: params[:state], cursor: params[:cursor], limit: params[:limit]
          )
          audit!("hq.trust_safety_enforcements_viewed", state: params[:state].presence)

          render json: {
            enforcements: result.enforcements.map { |enforcement| ::Admin::EnforcementSerializer.call(enforcement:) },
            next_cursor: result.next_cursor
          }
        end

        private

        def overview_payload(result)
          {
            brand: result.brand,
            generated_at: result.generated_at.iso8601,
            reports: {
              total: result.report_count,
              by_status: result.counts_by_status,
              awaiting_decision: result.awaiting_decision_count,
              oldest_open_report_at: result.oldest_open_report_at&.iso8601,
              oldest_open_report_age_seconds: result.oldest_open_report_age_seconds,
              by_reason: result.counts_by_reason,
              by_target_type: result.counts_by_target_type,
              sla_status: result.sla_status,
              overdue: result.overdue_count
            },
            enforcements: {
              total: result.enforcement_count,
              active: result.active_enforcement_count
            }
          }
        end

        def offender_payload(offender)
          {
            profile_id: offender.profile_id,
            display_name: offender.display_name,
            member_360_lookup: offender.member_360_lookup,
            report_count: offender.report_count,
            awaiting_decision_count: offender.awaiting_decision_count,
            latest_report_at: offender.latest_report_at.iso8601
          }
        end

        def audit!(event_type, extra = {})
          ::Hq::SensitiveReadAudit.record(
            admin_user: Current.admin_user,
            brand: Current.brand,
            event_type:,
            session: Current.session,
            extra: extra.compact
          )
        end

        def render_hq_error(error)
          render json: { error: error.code }, status: CODE_STATUS.fetch(error.code, :unprocessable_entity)
        end
      end
    end
  end
end
