module Community
  class Rsvp
    Result = Data.define(:status, :count, :created)

    def self.call(profile:, event:)
      raise Access::Unavailable unless event.status_approved? && event.published_at.present? && event.starts_at.future?

      event.with_lock do
        rsvp = CommunityEventRsvp.kept.find_or_initialize_by(community_event: event, profile:)
        return Result.new(status: rsvp.status, count: attending_count(event), created: false) if rsvp.persisted? && rsvp.status_attending?
        raise Access::Unavailable if event.capacity && attending_count(event) >= event.capacity

        rsvp.brand = event.brand
        rsvp.status = :attending
        rsvp.save!
        Result.new(status: rsvp.status, count: attending_count(event), created: true)
      end
    end

    def self.cancel!(profile:, event:)
      CommunityEventRsvp.kept.find_by(community_event: event, profile:)&.update!(status: :cancelled)
    end

    def self.attending_count(event) = event.community_event_rsvps.kept.status_attending.count
  end
end
