module Api
  module V1
    module Hq
      class SecurityAlertsController < BaseController
        requires_admin_capability ::Admin::Capabilities::SECURITY_ALERTS_READ

        def index
          events = SecurityEvent.where(brand: Current.brand)
            .where(severity: %i[warning high critical])
            .order(created_at: :desc, id: :desc)
            .limit(limit)
          ::Hq::SensitiveReadAudit.record(
            admin_user: Current.admin_user, brand: Current.brand,
            event_type: "hq.security_alerts_viewed", session: Current.session
          )
          render json: { alerts: events.map { |event| ::Hq::SecurityEventSerializer.call(event:) } }
        end

        private

        def limit
          value = params[:limit].presence || 50
          Integer(value).clamp(1, 100)
        rescue ArgumentError, TypeError
          50
        end
      end
    end
  end
end
