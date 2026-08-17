class Api::V1::MeController < ApplicationController
  before_action :authenticate_user!

  # Explicit confirmation guards this one-way destructive action so it can never be
  # triggered accidentally by a bare/mistaken client call.
  CLOSE_CONFIRMATION = "close".freeze

  def show
    render json: {
      user_id: Current.user.id,
      brand: {
        slug: Current.brand.slug,
        name: Current.brand.name
      },
      session: {
        id: Current.session.id,
        expires_at: Current.session.expires_at.iso8601
      }
    }
  end

  # Brand-level account closure. Immediately removes the current user from this
  # brand (membership tombstoned, profile discarded/anonymized, matches ended,
  # sessions revoked) and enqueues an asynchronous physical media purge. One-way:
  # the revoked session cannot retry, and re-joining requires fresh registration.
  def destroy
    return render json: { error: "confirmation_required" }, status: :unprocessable_entity unless confirmed?

    result = Accounts::CloseAccount.call(user: Current.user, brand: Current.brand)

    render json: {
      closed: true,
      already_closed: result.already_closed,
      media_purge_state: result.closure.media_purge_state
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "account_unavailable" }, status: :not_found
  end

  private

  def confirmed?
    params[:confirmation].to_s == CLOSE_CONFIRMATION
  end
end
