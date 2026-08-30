module Api
  module V1
    module Hq
      class AnalyticsController < BaseController
        requires_admin_capability ::Admin::Capabilities::ANALYTICS_READ

        def overview
          result = ::Hq::Analytics::Overview.call(brand: Current.brand)
          ::Hq::SensitiveReadAudit.record(
            admin_user: Current.admin_user,
            brand: Current.brand,
            event_type: "hq.analytics_overview_viewed",
            session: Current.session
          )

          render json: {
            overview: {
              brand: result.brand,
              generated_at: result.generated_at.iso8601,
              time_zone: result.time_zone,
              signups_today: result.signups_today,
              signups_this_week: result.signups_this_week,
              signups_this_month: result.signups_this_month,
              active_today: result.active_today,
              active_7d: result.active_7d,
              active_30d: result.active_30d,
              gender_split: result.gender_split,
              total_registered_members: result.total_registered_members
            }
          }
        end
      end
    end
  end
end
