class Api::V1::Community::QuestionsController < Api::V1::Community::BaseController
  community_writes :create, :create_answer, :update, :destroy

  def index
    items = CommunityQuestion.published.where(brand: Current.brand)
      .includes(:selected_answer, author_profile: %i[user brand_membership])
      .order(created_at: :desc)
    render json: {
      questions: items.map { |item| ::Community::Serializer.question(item) },
      categories: CommunityQuestion::CATEGORIES
    }
  end

  def create
    question = ::Community::Submissions.question!(
      profile: member!, brand: Current.brand, attributes: question_params.to_h.symbolize_keys
    )
    render json: { question: ::Community::Serializer.question(question, owner: true) }, status: :created
  end

  def answers
    items = question!.community_answers.published
      .includes(author_profile: %i[user brand_membership]).order(created_at: :asc)
    render json: { answers: items.map { |item| ::Community::Serializer.answer(item) } }
  end

  def create_answer
    answer = ::Community::Submissions.answer!(
      profile: member!, question: question!, attributes: answer_params.to_h.symbolize_keys
    )
    render json: { answer: ::Community::Serializer.answer(answer, owner: true) }, status: :created
  end

  def update
    record = CommunityQuestion.kept.where(brand: Current.brand).find_by!(public_id: params[:question_id])
    ::Community::Submissions.update!(record:, profile: member!, attributes: question_params)
    render json: { question: ::Community::Serializer.question(record, owner: true) }
  end

  def destroy
    record = CommunityQuestion.kept.where(brand: Current.brand).find_by!(public_id: params[:question_id])
    ::Community::Submissions.discard!(record:, profile: member!)
    head :no_content
  end

  private

  def question!
    CommunityQuestion.published.where(brand: Current.brand).find_by!(public_id: params[:question_id])
  end

  def question_params
    params.permit(:category, :body, :anonymous)
  end

  def answer_params
    params.permit(:body, :anonymous)
  end
end
