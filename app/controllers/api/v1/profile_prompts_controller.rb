class Api::V1::ProfilePromptsController < ApplicationController
  before_action :authenticate_user!
  before_action -> { enforce_rate_limit!(:profile_write) }, only: :update

  # GET /api/v1/profile/prompts — the member's current answers plus the owner
  # profile (so a client can render the prompts section standalone).
  def show
    profile = Profiles::CurrentProfile.find(user: Current.user, brand: Current.brand)
    return render json: { error: "profile_required" }, status: :forbidden if profile.blank?

    render json: { prompts: Profiles::PromptPresenter.call(profile:) }
  end

  # PUT /api/v1/profile/prompts — replace the member's prompt answers (ordered).
  def update
    profile = Profiles::CurrentProfile.find(user: Current.user, brand: Current.brand)
    return render json: { error: "profile_required" }, status: :forbidden if profile.blank?

    Profiles::PromptAnswers.replace!(profile:, answers: answers_params)

    render json: { profile: Profiles::OwnerSerializer.call(profile: profile.reload) }
  rescue Profiles::PromptAnswers::InvalidAnswer => e
    render json: { error: "invalid_prompt_answers", details: e.details }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "invalid_prompt_answers", details: e.record.errors.to_hash }, status: :unprocessable_entity
  end

  private

  def answers_params
    value = params[:answers]
    unless value.is_a?(Array)
      raise Profiles::PromptAnswers::InvalidAnswer.new(base: [ "answers must be an array" ])
    end

    value.map { |entry| entry.respond_to?(:to_unsafe_h) ? entry.to_unsafe_h : entry }
  end
end
