class Api::V1::Admin::CommunityController < Api::V1::Admin::BaseController
  requires_platform_capability "community.moderation"
  requires_platform_contract
  before_action :authorize_platform_capability!
  requires_admin_capability Admin::Capabilities::COMMUNITY_READ, only: :index
  requires_admin_capability Admin::Capabilities::COMMUNITY_MODERATE, only: :update

  def index
    records = Community::Moderation.queue(type: params[:type], brand: Current.brand)
    render json: { submissions: records.map { |record| moderation_payload(record) } }
  rescue KeyError
    render json: { error: "invalid_community_type" }, status: :unprocessable_entity
  end

  def update
    result = Community::Moderation.transition!(type: params[:type], public_id: params[:id], brand: Current.brand, admin: Current.admin_user, status: params.require(:status), note: params[:moderation_note])
    record = result.record
    render json: { id: record.public_id, status: record.status, reviewed_at: record.reviewed_at&.iso8601, transitioned: result.transitioned }
  rescue Community::Moderation::InvalidTransition, KeyError
    render json: { error: "invalid_community_moderation_transition" }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "community_resource_unavailable" }, status: :not_found
  end


  private

  def moderation_payload(record)
    {
      id: record.public_id,
      type: record.class.name.delete_prefix("Community").underscore,
      status: record.status,
      submitted_at: record.created_at.iso8601,
      content: serialized_content(record)
    }
  end

  def serialized_content(record)
    Community::Serializer.moderation(record)
  end
end
