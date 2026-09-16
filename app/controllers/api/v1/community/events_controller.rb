class Api::V1::Community::EventsController < Api::V1::Community::BaseController
  community_writes :create, :update, :destroy, :rsvp, :cancel_rsvp

  def index
    items = CommunityEvent.published.where(brand: Current.brand)
      .where("starts_at >= ?", Time.current).includes(:community_event_rsvps).order(:starts_at)
    render json: { events: items.map { |item| ::Community::Serializer.event(item) } }
  end

  def create
    event = ::Community::Submissions.event!(
      profile: member!, brand: Current.brand, attributes: event_params.to_h.symbolize_keys
    )
    render json: { event: ::Community::Serializer.event(event, owner: true) }, status: :created
  end

  def update
    record = CommunityEvent.kept.where(brand: Current.brand).find_by!(public_id: params[:event_id])
    ::Community::Submissions.update!(record:, profile: member!, attributes: event_params)
    render json: { event: ::Community::Serializer.event(record, owner: true) }
  end

  def destroy
    record = CommunityEvent.kept.where(brand: Current.brand).find_by!(public_id: params[:event_id])
    ::Community::Submissions.discard!(record:, profile: member!)
    head :no_content
  end

  def rsvp
    event = event!
    result = ::Community::Rsvp.call(profile: member!, event:)
    render json: { rsvp: { status: result.status, count: result.count, capacity: event.capacity } },
      status: result.created ? :created : :ok
  end

  def cancel_rsvp
    ::Community::Rsvp.cancel!(profile: member!, event: event!)
    head :no_content
  end

  def attendees
    event = CommunityEvent.kept.where(brand: Current.brand).find_by!(public_id: params[:event_id])
    ::Community::Access.event_organizer!(event:, profile: member!)
    rsvps = event.community_event_rsvps.kept.status_attending
      .includes(profile: :brand_membership).order(:created_at)
    render json: {
      event_id: event.public_id,
      attendees: rsvps.map { |item| ::Community::Serializer.attendee(item) }
    }
  end

  private

  def event!
    CommunityEvent.published.where(brand: Current.brand).find_by!(public_id: params[:event_id])
  end

  def event_params
    params.permit(:title, :description, :city, :venue, :starts_at, :capacity)
  end
end
