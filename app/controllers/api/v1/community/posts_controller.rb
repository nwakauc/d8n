class Api::V1::Community::PostsController < Api::V1::Community::BaseController
  community_writes :create_comment

  def comments
    post = post!
    ::Community::Access.circle_member!(circle: post.community_circle, profile: member!)
    items = post.community_comments.kept.includes(author_profile: %i[user brand_membership]).order(:created_at)
    render json: { comments: items.map { |item| ::Community::Serializer.post(item) } }
  end

  def create_comment
    post = post!
    profile = member!
    ::Community::Access.circle_member!(circle: post.community_circle, profile:)
    comment = CommunityComment.create!(
      community_post: post, brand: Current.brand, author_profile: profile,
      body: params.require(:body).to_s.strip
    )
    render json: { comment: ::Community::Serializer.post(comment) }, status: :created
  end

  private

  def post!
    CommunityPost.kept.where(brand: Current.brand).find_by!(public_id: params[:post_id])
  end
end
