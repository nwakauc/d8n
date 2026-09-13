module Community
  # Explicit public/owner serialization for Community records. Moderation notes,
  # reviewer identities, internal ids, and deleted-member attribution never cross
  # the public API boundary.
  module Serializer
    module_function

    def question(item, owner: false)
      {
        id: item.public_id,
        category: item.category,
        body: item.body,
        anonymous: item.anonymous,
        author: author(item.author_profile, anonymous: item.anonymous),
        closes_at: item.closes_at.iso8601,
        selected_answer_id: item.selected_answer&.public_id,
        status: (item.status if owner)
      }.compact
    end

    def answer(item, owner: false)
      {
        id: item.public_id,
        question_id: item.community_question.public_id,
        body: item.body,
        anonymous: item.anonymous,
        author: author(item.author_profile, anonymous: item.anonymous),
        status: (item.status if owner)
      }.compact
    end

    def event(item, owner: false)
      {
        id: item.public_id,
        title: item.title,
        description: item.description,
        city: item.city,
        venue: item.venue,
        starts_at: item.starts_at.iso8601,
        capacity: item.capacity,
        rsvp_count: item.community_event_rsvps.count { |rsvp| rsvp.deleted_at.nil? && rsvp.status_attending? },
        status: (item.status if owner)
      }.compact
    end

    def story(item, owner: false)
      {
        id: item.public_id,
        title: item.title,
        body: item.body,
        content_type: item.content_type,
        author: author(item.author_profile),
        status: (item.status if owner)
      }.compact
    end

    def circle(item, owner: false)
      {
        id: item.public_id,
        name: item.name,
        description: item.description,
        category: item.category,
        members_count: item.community_circle_memberships.count { |membership| membership.deleted_at.nil? && membership.status_active? },
        status: (item.status if owner)
      }.compact
    end

    def post(item)
      {
        id: item.public_id,
        body: item.body,
        author: author(item.author_profile),
        created_at: item.created_at.iso8601
      }
    end

    def attendee(rsvp)
      if former_member?(rsvp.profile)
        return { display_name: "Former member", rsvp_at: rsvp.created_at.iso8601 }
      end

      {
        id: rsvp.profile.public_id,
        display_name: rsvp.profile.display_name,
        rsvp_at: rsvp.created_at.iso8601
      }
    end

    def moderation(item)
      type = item.class.name.delete_prefix("Community").underscore
      payload = public_send(type, item, owner: true)
      profile = item.try(:author_profile) || item.try(:organizer_profile) || item.try(:creator_profile)
      payload.merge(submitted_by: { id: profile.public_id })
    end

    def author(profile, anonymous: false)
      return { display_name: "Anonymous" } if anonymous
      return { display_name: "Former member" } if former_member?(profile)

      { id: profile.public_id, display_name: profile.display_name }
    end

    def former_member?(profile)
      profile.deleted_at.present? || profile.brand_membership.deleted_at.present? || profile.brand_membership.left?
    end
    private_class_method :former_member?
  end
end
