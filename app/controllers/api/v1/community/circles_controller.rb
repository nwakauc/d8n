class Api::V1::Community::CirclesController < Api::V1::Community::BaseController
  community_writes :create, :update, :destroy, :join, :leave, :create_post

  def index
    items = CommunityCircle.published.where(brand: Current.brand)
      .includes(:community_circle_memberships).order(created_at: :desc)
    render json: { circles: items.map { |item| ::Community::Serializer.circle(item) } }
  end

  def create
    circle = ::Community::Submissions.circle!(
      profile: member!, brand: Current.brand, attributes: circle_params.to_h.symbolize_keys
    )
    render json: { circle: ::Community::Serializer.circle(circle, owner: true) }, status: :created
  end

  def update
    record = CommunityCircle.kept.where(brand: Current.brand).find_by!(public_id: params[:circle_id])
    ::Community::Submissions.update!(record:, profile: member!, attributes: circle_params)
    render json: { circle: ::Community::Serializer.circle(record, owner: true) }
  end

  def destroy
    record = CommunityCircle.kept.where(brand: Current.brand).find_by!(public_id: params[:circle_id])
    ::Community::Submissions.discard!(record:, profile: member!)
    head :no_content
  end

  def join
    circle = circle!
    result = ::Community::Membership.join!(circle:, profile: member!)
    render json: { membership: { status: result.membership.status, circle_id: circle.public_id } },
      status: result.created ? :created : :ok
  end

  def leave
    ::Community::Membership.leave!(circle: circle!, profile: member!)
    head :no_content
  end

  def posts
    circle = circle!
    ::Community::Access.circle_member!(circle:, profile: member!)
    items = circle.community_posts.kept.includes(author_profile: %i[user brand_membership])
      .order(created_at: :asc)
    render json: { posts: items.map { |item| ::Community::Serializer.post(item) } }
  end

  def create_post
    circle = circle!
    profile = member!
    ::Community::Access.circle_member!(circle:, profile:)
    post = CommunityPost.create!(
      community_circle: circle, brand: Current.brand, author_profile: profile,
      body: params.require(:body).to_s.strip
    )
    render json: { post: ::Community::Serializer.post(post) }, status: :created
  end

  private

  def circle!
    CommunityCircle.published.where(brand: Current.brand).find_by!(public_id: params[:circle_id])
  end

  def circle_params
    params.permit(:name, :description, :category)
  end
end
