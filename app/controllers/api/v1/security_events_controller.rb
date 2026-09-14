class Api::V1::SecurityEventsController < ApplicationController
  before_action :authenticate_user!

  # A member's own recent account-security activity (sign-ins, password/email/
  # phone changes, session revocations, deactivation) — self-service equivalent
  # of the HQ admin security-event read, scoped and filtered for a member's own
  # eyes. See Accounts::MemberSecurityEvents for the event-type allowlist and
  # why `metadata` is never exposed here.
  def index
    events = Accounts::MemberSecurityEvents.call(brand: Current.brand, user: Current.user, limit: params[:limit])

    render json: { events: events.map { |event| event_payload(event) } }
  end

  private

  def event_payload(event)
    {
      id: event.id,
      event_type: event.event_type,
      occurred_at: event.created_at.iso8601,
      ip_address: event.ip_address,
      user_agent: event.user_agent
    }
  end
end
