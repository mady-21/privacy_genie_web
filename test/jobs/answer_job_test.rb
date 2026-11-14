require "test_helper"

class AnswerJobTest < ActiveJob::TestCase
  setup do
    setup_documents
    create_answer_chunk(@act, "제21조", article_title: "개인정보의 파기")
    @answer = Answer.create!(question: AnswerHelpers::QUESTION)
    @original_factory = AnswerJob.generator_factory
  end

  teardown do
    AnswerJob.generator_factory = @original_factory
  end

  test "answers the question and stores the citations" do
    use_llm(FakeLlm.new(text: "지체 없이 파기해야 합니다 [1]."))

    AnswerJob.perform_now(@answer)

    @answer.reload
    assert @answer.completed?
    assert @answer.outcome_answered?
    assert_equal "지체 없이 파기해야 합니다 [1].", @answer.body
    assert_equal [ [ 1, true, "제21조" ] ], @answer.citations.map { |citation| [ citation.number, citation.cited, citation.article_number ] }
  end

  test "retries llm overload and then leaves a temporary failure with the found articles" do
    llm = use_llm(FakeLlm.new(error: Llm::ServiceUnavailableError.new("overloaded")))

    perform_enqueued_jobs { AnswerJob.perform_later(@answer) }

    @answer.reload
    assert_equal 3, llm.requests.size
    assert @answer.failed?
    assert @answer.error_temporary?
    assert @answer.retryable?
    assert_equal [ "제21조" ], @answer.citations.map(&:article_number)
  end

  test "fails at once when retrying cannot help" do
    llm = use_llm(FakeLlm.new(error: Llm::ConfigurationError.new("API 키가 없습니다")))

    perform_enqueued_jobs { AnswerJob.perform_later(@answer) }

    @answer.reload
    assert_equal 1, llm.requests.size
    assert @answer.error_unavailable?
    assert_not @answer.retryable?
    assert_match "API 키가 없습니다", @answer.error_message
  end

  test "fails at once when doc is unavailable" do
    @doc_client.define_singleton_method(:embed) { |_texts| raise PrivacyGenieDoc::Client::Error, "connection refused" }
    use_llm(FakeLlm.new)

    AnswerJob.perform_now(@answer)

    assert @answer.reload.error_unavailable?
    assert_empty @answer.citations
  end

  test "leaves finished answers alone" do
    llm = use_llm(FakeLlm.new)
    @answer.fail!(:unavailable, StandardError.new("이전 실패"))

    AnswerJob.perform_now(@answer)

    assert_empty llm.requests
    assert @answer.reload.failed?
  end

  private

  def use_llm(llm)
    client = @doc_client
    AnswerJob.generator_factory = ->(_answer) { Answers::Generate.new(search: Documents::Search.new(client: client), llm: llm) }
    llm
  end
end
