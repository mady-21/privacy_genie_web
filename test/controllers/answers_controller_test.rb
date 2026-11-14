require "test_helper"

class AnswersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  teardown do
    AnswersController.daily_limit = ENV.fetch("ANSWER_DAILY_LIMIT", 500).to_i
  end

  test "the home page shows the question form, examples and scope" do
    get root_path

    assert_response :success
    assert_select "form.question-form[action=?][method=post] textarea[name=?][maxlength=?]", answers_path, "answer[question]", "1000"
    assert_select ".examples .chip", AnswersController::EXAMPLES.size
    assert_select ".scope", /벌칙\(징역·벌금\) 조문/
    assert_select ".site-notice", /법률 자문이 아닌 일반 정보입니다/
  end

  test "creating an answer masks the question, queues the job and opens the answer page" do
    assert_enqueued_with(job: AnswerJob) do
      post answers_path, params: { answer: { question: "010-1234-5678 회원 정보는 언제 지우나요?", provider: "openai" } }
    end

    answer = Answer.last
    assert_redirected_to answer_path(answer.token)
    assert_equal "[전화번호] 회원 정보는 언제 지우나요?", answer.question
    assert_equal "openai", answer.provider
  end

  test "ignores unknown providers" do
    post answers_path, params: { answer: { question: "질문", provider: "unknown" } }

    assert_nil Answer.last.provider
  end

  test "rejects blank and too long questions" do
    post answers_path, params: { answer: { question: " " } }
    assert_response :unprocessable_content
    assert_select ".notice-danger", "질문을 입력하세요."

    post answers_path, params: { answer: { question: "가" * 1001 } }
    assert_response :unprocessable_content
    assert_select ".notice-danger", "질문은 1,000자까지 입력할 수 있습니다."
    assert_equal 0, Answer.count
    assert_no_enqueued_jobs only: AnswerJob
  end

  test "stops taking questions after the daily limit" do
    AnswersController.daily_limit = 1
    Answer.create!(question: "오늘 첫 질문")

    post answers_path, params: { answer: { question: "두 번째 질문" } }

    assert_response :too_many_requests
    assert_select ".notice-danger", /오늘 받을 수 있는 질문 수를 넘었습니다/
    assert_select "textarea[name=?]", "answer[question]", text: "두 번째 질문"
    assert_equal 1, Answer.count
  end

  test "an answer in progress subscribes to updates and shows the steps" do
    answer = Answer.create!(question: "질문", status: :generating)

    get answer_path(answer)

    assert_response :success
    assert_select "turbo-cable-stream-source", 1
    assert_select "[data-controller=refresh]", 1
    assert_select ".progress-step.progress-done", "관련 조문을 찾고 있습니다"
    assert_select ".progress-step.progress-current", /조문을 근거로 답변을 쓰고 있습니다/
  end

  test "a finished answer links each citation to its article card" do
    answer = completed_answer(
      body: "지체 없이 파기해야 합니다 [1]. 시행령도 봅니다 [2].",
      citations: [
        citation(1),
        citation(2, article_number: "제16조", document_name: "개인정보 보호법 시행령", status: :pending,
          effective_date: Date.new(2027, 3, 9)),
        citation(3, cited: false, article_number: "제39조", pending_amendment_date: Date.new(2027, 7, 1))
      ]
    )

    get answer_path(answer)

    assert_response :success
    assert_select "turbo-cable-stream-source", 0
    assert_select ".answer-body a.cite[href='#citation-1']", "1"
    assert_select ".answer-body a.cite[href='#citation-2']", "2"
    assert_select ".notice-warning", /아직 시행되지 않은 조문을 인용했습니다:\s*\[2\] 2027-03-09 시행/
    assert_select ".answer-basis", /기준 법령 데이터로 답했습니다/
    assert_select ".citations > .citation", 2
    assert_select "#citation-1 h3", "개인정보 보호법 제21조(개인정보의 파기)"
    assert_select "#citation-1 .badge-effective", "현행"
    assert_select "#citation-1 .back-link[href='#answer']"
    assert_select "#citation-2 .badge-pending", "시행 전 · 2027-03-09 시행"
    assert_select "details.related summary", "함께 검색된 조문 1개"
    assert_select "details.related #citation-3 .badge-amended", "현행 · 2027-07-01 개정 예정"
    assert_select "#citation-3 .back-link", 0
  end

  test "warns when the answer cites nothing" do
    answer = completed_answer(body: "인용 없는 답변", citations: [ citation(1, cited: false) ])

    get answer_path(answer)

    assert_select ".notice-warning", /조문 인용 표시가 없습니다/
    assert_select ".citations h2", "검색된 조문"
  end

  test "a truncated answer says it was cut" do
    get answer_path(completed_answer(outcome: :truncated))

    assert_select ".notice-warning", /중간에 끊겼습니다/
    assert_select ".answer-body a.cite", 1
  end

  test "no basis explains the scope and tucks away the nearest articles" do
    get answer_path(completed_answer(outcome: :no_basis, body: nil, citations: [ citation(1, cited: false) ]))

    assert_select ".notice", /질문과 관련된 조문을 찾지 못했습니다/
    assert_select ".tips li", 3
    assert_select ".answer-body", 0
    assert_select "details.related summary", "가장 가까웠던 조문 1개"
  end

  test "a refused answer says so" do
    get answer_path(completed_answer(outcome: :refused, body: nil, citations: []))

    assert_select ".notice", /이 질문에는 답할 수 없습니다/
    assert_select ".citations", 0
  end

  test "a temporary failure offers a retry and keeps the found articles" do
    answer = Answer.create!(question: "질문")
    answer.start_generating!([ citation(1, cited: false) ])
    answer.fail!(:temporary, Llm::RateLimitError.new("429"))

    get answer_path(answer)

    assert_select ".notice-danger", /잠시 뒤 다시 시도하세요/
    assert_select "form[action=?] button", retry_answer_path(answer), text: "다시 시도"
    assert_select ".citations #citation-1"
  end

  test "a permanent failure offers no retry" do
    answer = Answer.create!(question: "질문")
    answer.fail!(:unavailable, Llm::ConfigurationError.new("키 없음"))

    get answer_path(answer)

    assert_select ".notice-danger", /지금은 답변을 만들 수 없습니다/
    assert_select "form[action=?]", retry_answer_path(answer), count: 0
  end

  test "retrying a temporary failure queues the job again" do
    answer = Answer.create!(question: "질문")
    answer.fail!(:temporary, Llm::RateLimitError.new("429"))

    assert_enqueued_with(job: AnswerJob, args: [ answer ]) do
      post retry_answer_path(answer)
    end

    assert_redirected_to answer_path(answer)
    assert answer.reload.pending?
  end

  test "retrying anything else changes nothing" do
    answer = completed_answer

    assert_no_enqueued_jobs(only: AnswerJob) { post retry_answer_path(answer) }

    assert_redirected_to answer_path(answer)
    assert answer.reload.completed?
  end

  test "unknown tokens are not found and purged answers are gone" do
    get answer_path("unknown-token")
    assert_response :not_found

    answer = completed_answer
    answer.purge!
    get answer_path(answer)
    assert_response :gone
    assert_select ".notice", /보관 기간\(90일\)이 지나/
  end
end
