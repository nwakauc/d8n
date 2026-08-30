module Api
  module V1
    module Hq
      class MfaController < BaseController
        skip_before_action :require_admin_mfa!

        rescue_from ::Admin::Mfa::Error, with: :render_mfa_error

        def create
          result = ::Admin::Mfa::Enrollment.start(
            admin_user: Current.admin_user,
            brand: Current.brand,
            session: Current.session
          )
          render json: {
            mfa: {
              state: "pending",
              secret: result.secret,
              provisioning_uri: result.provisioning_uri
            }
          }, status: :created
        end

        def confirm
          result = ::Admin::Mfa::Enrollment.confirm(
            admin_user: Current.admin_user,
            brand: Current.brand,
            session: Current.session,
            code: params[:code]
          )
          render json: {
            mfa: { state: "active", verified: true },
            recovery_codes: result.recovery_codes
          }
        end

        def challenge
          result = ::Admin::Mfa::Challenge.call(
            admin_user: Current.admin_user,
            brand: Current.brand,
            session: Current.session,
            code: params[:code]
          )
          render json: {
            mfa: {
              state: "active",
              verified: true,
              method: result.method,
              recovery_codes_remaining: result.recovery_codes_remaining
            }
          }
        end

        def destroy
          ::Admin::Mfa::Reset.call(
            admin_user: Current.admin_user,
            brand: Current.brand,
            session: Current.session,
            code: params[:code]
          )
          render json: { mfa: { state: "not_enrolled", verified: false } }
        end

        private

        def render_mfa_error(error)
          status = case error.code
          when "admin_mfa_rate_limited" then :too_many_requests
          when "admin_mfa_required" then :forbidden
          else :unprocessable_entity
          end
          response.set_header("Retry-After", error.retry_after.to_s) if error.retry_after
          render json: { error: error.code }, status:
        end
      end
    end
  end
end
