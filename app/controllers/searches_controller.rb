# 질문을 넣어 실제 검색(doc 질문 임베딩 → pgvector) 결과를 눈으로 확인하는 개발용 화면.
# AI 답변을 붙이기 전 검색 품질을 보기 위한 도구라 운영 환경에는 라우트가 없다.
class SearchesController < ApplicationController
  # doc의 POST /embeddings 텍스트 길이 제한과 같다. 넘으면 doc을 부르지 않고 바로 막는다.
  MAX_QUESTION_LENGTH = 10_000
  LIMITS = 1..20

  # 테스트에서 가짜 doc 클라이언트를 쓰는 검색으로 바꿀 수 있게 만드는 방법을 열어 둔다.
  class_attribute :search_factory, default: -> { Documents::Search.new }

  def show
    @question = params[:q].to_s.strip
    @limit = params.fetch(:limit, Documents::Search::DEFAULT_LIMIT).to_i.clamp(LIMITS)
    @effective_only = params[:effective_only] == "1"
    return if @question.empty?

    if @question.length > MAX_QUESTION_LENGTH
      return render_error("질문은 #{MAX_QUESTION_LENGTH.to_fs(:delimited)}자까지 입력할 수 있습니다.", :unprocessable_content)
    end

    @results = search_factory.call.call(@question, limit: @limit, effective_only: @effective_only)
  rescue Documents::Search::ModelMismatch => error
    render_error("임베딩 모델이 맞지 않습니다. documents:sync로 다시 동기화하세요. (#{error.message})", :service_unavailable)
  rescue PrivacyGenieDoc::Client::Error => error
    render_error("privacy-genie-doc에 연결할 수 없습니다. (#{error.message})", :service_unavailable)
  end

  private

  def render_error(message, status)
    @error = message
    render :show, status: status
  end
end
