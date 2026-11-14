# 사용자용 질의응답 화면. 질문을 받으면 Answer를 만들고 AnswerJob에 넘긴 뒤 답변 화면으로 보낸다.
# 답변 화면은 Job이 보내는 Turbo refresh로 진행 단계와 결과를 따라 그린다.
class AnswersController < ApplicationController
  # 로그인이 없으므로 IP당 요청 수와 하루 전체 답변 수(LLM 비용 차단기)로 남용을 막는다.
  class_attribute :daily_limit, default: ENV.fetch("ANSWER_DAILY_LIMIT", 500).to_i

  EXAMPLES = [
    "탈퇴한 회원의 개인정보는 언제까지 지워야 하나요?",
    "CCTV를 설치하려면 어떤 안내판을 붙여야 하나요?",
    "동의 없이 개인정보를 제3자에게 줄 수 있는 경우가 있나요?"
  ].freeze

  rate_limit to: 5, within: 1.minute, only: %i[create retry],
    with: -> { render_form_error("질문을 너무 자주 보냈습니다. 1분 뒤에 다시 시도하세요.", :too_many_requests) }

  before_action :set_answer, only: %i[show retry]

  def new
    @answer = Answer.new
  end

  def create
    if Answer.created_today.count >= daily_limit
      return render_form_error("오늘 받을 수 있는 질문 수를 넘었습니다. 내일 다시 이용해 주세요.", :too_many_requests)
    end

    @answer = Answer.new(question: params.dig(:answer, :question), provider: requested_provider)
    if @answer.save
      AnswerJob.perform_later(@answer)
      redirect_to @answer
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    render :purged, status: :gone if @answer.purged?
  end

  def retry
    if @answer.retryable?
      @answer.retry!
      AnswerJob.perform_later(@answer)
    end
    redirect_to @answer
  end

  private

  def set_answer
    @answer = Answer.find_by!(token: params[:token])
  end

  # provider 선택은 개발 환경에서만 받는다. 운영은 LLM_PROVIDER 기본값을 쓴다.
  def requested_provider
    return unless Rails.env.local?

    params.dig(:answer, :provider).presence_in(Llm.provider_names.map(&:to_s))
  end

  def render_form_error(message, status)
    @answer = Answer.new(question: params.dig(:answer, :question))
    @answer.errors.add(:base, message)
    render :new, status: status
  end
end
