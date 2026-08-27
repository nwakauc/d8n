class Api::V1::MeController < ApplicationController
  requires_platform_contract
  before_action :authenticate_user!

  # Explicit confirmation guards this one-way destructive action so it can never be
  # triggered accidentally by a bare/mistaken client call.
  CLOSE_CONFIRMATION = "close".freeze

  def show
    verification = Identity::VerificationState.call(session: Current.session, brand: Current.brand)
    render json: {
      user_id: Current.user.id,
      brand: {
        slug: Current.brand.slug,
        name: Current.brand.name
      },
      session: {
        id: Current.session.id,
        expires_at: Current.session.expires_at.iso8601,
        authentication_mode: Current.authentication_source.to_s,
        csrf_token: browser_csrf_token
      },
      identifier: identifier_payload(verification),
      verification_required: verification.present? && !verification.verified,
      verification: verification_payload(verification),
      # Always "active": SessionAuthenticator only authenticates sessions backed
      # by an active BrandMembership, so a deactivated or deleted account can
      # never reach this action in the first place. The client observes
      # "deactivated" as the `account_deactivated` error from
      # POST /api/v1/auth/password/login, and "deleted" as simply being logged
      # out — no `deletion_pending` exists because closure is immediate.
      account_status: "active",
      account_controls: account_controls
    }
  end

  # Brand-level account closure. Immediately removes the current user from this
  # brand (membership tombstoned, profile discarded/anonymized, matches ended,
  # sessions revoked) and enqueues an asynchronous physical media purge. One-way:
  # the revoked session cannot retry, and re-joining requires fresh registration.
  def destroy
    return render json: { error: "confirmation_required" }, status: :unprocessable_entity unless confirmed?

    result = Accounts::CloseAccount.call(user: Current.user, brand: Current.brand)
    clear_browser_session_cookie

    render json: {
      closed: true,
      already_closed: result.already_closed,
      media_purge_state: result.closure.media_purge_state
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "account_unavailable" }, status: :not_found
  end

  private

  def identifier_payload(verification)
    return if verification.blank?

    {
      kind: verification.kind,
      verified: verification.verified,
      masked_destination: verification.masked_destination
    }
  end

  def browser_csrf_token
    return unless Current.authentication_source == :cookie

    Identity::BrowserSession.csrf_token(session: Current.session)
  end

  def verification_payload(verification)
    return if verification.blank?

    {
      code_dispatched: verification.code_dispatched,
      resend_available_in: verification.resend_available_in,
      expires_at: verification.expires_at&.iso8601
    }
  end

  def confirmed?
    params[:confirmation].to_s == CLOSE_CONFIRMATION
  end

  def account_controls
    {
      password_change: Current.platform_contract.capability_enabled?("id.account.password_change"),
      deactivation: Current.platform_contract.capability_enabled?("id.account.deactivate"),
      deletion: Current.platform_contract.capability_enabled?("id.account.close_brand_membership")
    }
  end
end
