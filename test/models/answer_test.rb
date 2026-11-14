require "test_helper"

class AnswerTest < ActiveSupport::TestCase
  test "masks the question before saving and remembers what was masked" do
    answer = Answer.create!(question: "  010-1234-5678로 연락한 회원 정보를 지워야 하나요?  ")

    assert_equal "[전화번호]로 연락한 회원 정보를 지워야 하나요?", answer.reload.question
    assert_equal [ "전화번호" ], answer.masked_kinds
    assert answer.pending?
  end

  test "uses an unguessable token in urls" do
    answer = Answer.create!(question: "질문")

    assert_match(/\A[A-Za-z0-9]{24}\z/, answer.token)
    assert_equal answer.token, answer.to_param
  end

  test "requires a question within the length limit" do
    assert_equal [ "질문을 입력하세요." ], Answer.new(question: "   ").tap(&:validate).errors.messages_for(:question)

    too_long = Answer.new(question: "가" * (Answer::MAX_QUESTION_LENGTH + 1))
    assert_equal [ "질문은 1,000자까지 입력할 수 있습니다." ], too_long.tap(&:validate).errors.messages_for(:question)
  end

  test "keeps the found articles while generating and replaces them when complete" do
    answer = Answer.create!(question: "질문")

    answer.start_generating!([ citation(1, cited: false), citation(2, cited: false, article_number: "제16조") ])
    assert answer.generating?
    assert_equal [ 1, 2 ], answer.citations.map(&:number)

    answer.complete!(Answers::Generate::Result.new(
      outcome: :answered, body: "답변 [2]", dropped_citation_numbers: [ 7 ],
      citations: [ citation(1, cited: false), citation(2, cited: true, article_number: "제16조",
        status: :pending, effective_date: Date.new(2027, 3, 9)) ],
      llm: Llm::Response.new(text: "답변 [2]", provider: :openai, model: "gpt", stop_reason: :end_turn,
        input_tokens: 10, output_tokens: 5, latency_ms: 900)
    ))

    answer.reload
    assert answer.completed?
    assert answer.outcome_answered?
    assert_equal "답변 [2]", answer.body
    assert_equal [ 7 ], answer.dropped_citation_numbers
    assert_equal [ "openai", "gpt", "end_turn", 10, 5, 900 ],
      [ answer.provider, answer.model, answer.stop_reason, answer.input_tokens, answer.output_tokens, answer.latency_ms ]
    assert_not_nil answer.completed_at
    assert_equal [ 2 ], answer.citations.cited.map(&:number)
    pending = answer.citations.cited.sole
    assert pending.pending?
    assert_equal "시행 전 · 2027-03-09 시행", pending.status_label
    assert_equal "개인정보 보호법 제16조(개인정보의 파기)", pending.heading
  end

  test "records failures and can be retried only after a temporary one" do
    answer = Answer.create!(question: "질문")

    answer.fail!(:unavailable, Llm::AuthenticationError.new("401"))
    assert answer.failed?
    assert_not answer.retryable?
    assert_equal "Llm::AuthenticationError: 401", answer.error_message

    answer.fail!(:temporary, Llm::RateLimitError.new("429"))
    assert answer.retryable?

    answer.retry!
    assert answer.pending?
    assert_nil answer.error_kind
    assert_nil answer.error_message
  end

  test "purges questions, answers and citations after the retention period" do
    old = completed_answer
    old.update_columns(created_at: (Answer::RETENTION + 1.day).ago)
    recent = completed_answer

    PurgeExpiredAnswersJob.perform_now

    old.reload
    assert old.purged?
    assert_nil old.question
    assert_nil old.body
    assert_empty old.citations
    assert_equal 120, old.input_tokens
    assert_not recent.reload.purged?
    assert_equal 1, recent.citations.count
  end
end
