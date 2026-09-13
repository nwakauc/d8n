class Api::V1::Community::StoriesController < Api::V1::Community::BaseController
  community_writes :create, :update, :destroy

  def index
    items = CommunityStory.published.where(brand: Current.brand)
      .includes(author_profile: %i[user brand_membership]).order(published_at: :desc)
    render json: { stories: items.map { |item| ::Community::Serializer.story(item) } }
  end

  def create
    story = ::Community::Submissions.story!(
      profile: member!, brand: Current.brand, attributes: story_params.to_h.symbolize_keys
    )
    render json: { story: ::Community::Serializer.story(story, owner: true) }, status: :created
  end

  def update
    record = CommunityStory.kept.where(brand: Current.brand).find_by!(public_id: params[:story_id])
    ::Community::Submissions.update!(record:, profile: member!, attributes: story_params)
    render json: { story: ::Community::Serializer.story(record, owner: true) }
  end

  def destroy
    record = CommunityStory.kept.where(brand: Current.brand).find_by!(public_id: params[:story_id])
    ::Community::Submissions.discard!(record:, profile: member!)
    head :no_content
  end

  private

  def story_params
    params.permit(:title, :body, :content_type)
  end
end
