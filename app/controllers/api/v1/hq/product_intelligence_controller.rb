module Api
  module V1
    module Hq
      class ProductIntelligenceController < BaseController
        requires_admin_capability ::Admin::Capabilities::ANALYTICS_READ

        def funnel
          result = ::Hq::ProductIntelligence::Funnel.call(brand: Current.brand, window: window_param)
          audit!("hq.product_intelligence_funnel_viewed")
          render json: { funnel: serialize(result) }
        rescue ArgumentError => error
          render json: { error: "invalid_window", detail: error.message }, status: :bad_request
        end

        def trends
          result = ::Hq::ProductIntelligence::Trends.call(brand: Current.brand, window: window_param)
          audit!("hq.product_intelligence_trends_viewed")
          render json: { trends: serialize(result) }
        rescue ArgumentError => error
          render json: { error: "invalid_window", detail: error.message }, status: :bad_request
        end

        private

        def window_param
          params.fetch(:window, "last_7d")
        end

        def serialize(result)
          result.to_h.merge(generated_at: result.generated_at.iso8601)
        end

        def audit!(event_type)
          ::Hq::SensitiveReadAudit.record(
            admin_user: Current.admin_user,
            brand: Current.brand,
            event_type:,
            session: Current.session
          )
        end
      end
    end
  end
end
