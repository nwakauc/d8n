module Api
  module V1
    module Hq
      class CommandCentreController < BaseController
        requires_admin_capability ::Admin::Capabilities::ANALYTICS_READ

        def health
          result = ::Hq::CommandCentre::BrandHealthSnapshot.call(brand: Current.brand)
          audit!("hq.command_centre_health_viewed")

          render json: { brand_health: serialize_brand_health(result.brand_health) }
        end

        def brands
          result = ::Hq::CommandCentre::BrandComparison.call(admin_user: Current.admin_user)
          audit!("hq.command_centre_brands_viewed")

          render json: {
            generated_at: result.generated_at.iso8601,
            time_zone: result.time_zone,
            brands: result.brands.map { |entry| serialize_brand_entry(entry) }
          }
        end

        private

        def audit!(event_type)
          ::Hq::SensitiveReadAudit.record(
            admin_user: Current.admin_user,
            brand: Current.brand,
            event_type:,
            session: Current.session
          )
        end

        def serialize_brand_health(brand_health)
          brand_health.merge(generated_at: brand_health[:generated_at].iso8601)
        end

        def serialize_brand_entry(entry)
          payload = entry.deep_dup
          health = payload[:brand_health]
          payload[:brand_health] = health ? serialize_brand_health(health) : nil
          payload
        end
      end
    end
  end
end
