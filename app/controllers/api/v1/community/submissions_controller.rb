class Api::V1::Community::SubmissionsController < Api::V1::Community::BaseController
  def index
    profile = member!
    render json: {
      questions: CommunityQuestion.kept.where(brand: Current.brand, author_profile: profile)
        .order(created_at: :desc).map { |item| ::Community::Serializer.question(item, owner: true) },
      answers: CommunityAnswer.kept.where(brand: Current.brand, author_profile: profile)
        .order(created_at: :desc).map { |item| ::Community::Serializer.answer(item, owner: true) },
      events: CommunityEvent.kept.where(brand: Current.brand, organizer_profile: profile)
        .includes(:community_event_rsvps).order(created_at: :desc)
        .map { |item| ::Community::Serializer.event(item, owner: true) },
      stories: CommunityStory.kept.where(brand: Current.brand, author_profile: profile)
        .order(created_at: :desc).map { |item| ::Community::Serializer.story(item, owner: true) },
      circles: CommunityCircle.kept.where(brand: Current.brand, creator_profile: profile)
        .includes(:community_circle_memberships).order(created_at: :desc)
        .map { |item| ::Community::Serializer.circle(item, owner: true) }
    }
  end
end
