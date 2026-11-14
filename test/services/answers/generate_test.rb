require "test_helper"

class Answers::GenerateTest < ActiveSupport::TestCase
  setup do
    setup_documents
  end

  test "numbers the found articles, asks the llm and keeps only real citation numbers" do
    create_answer_chunk(@act, "제21조", weight: 0, article_title: "개인정보의 파기", text: "제21조(개인정보의 파기) 본문")
    create_answer_chunk(@decree, "제16조", weight: 0.5, article_title: "개인정보의 파기방법")
    create_answer_chunk(@act, "제39조의6", weight: 1)
    llm = FakeLlm.new(text: "지체 없이 파기해야 합니다 [1]. 방법은 시행령을 따릅니다 [2, 9]. 근거가 없는 문장 [7].")

    result = generator(llm: llm).call(AnswerHelpers::QUESTION)

    assert_equal :answered, result.outcome
    assert_equal "지체 없이 파기해야 합니다 [1]. 방법은 시행령을 따릅니다 [2]. 근거가 없는 문장.", result.body
    assert_equal [ 9, 7 ], result.dropped_citation_numbers
    assert_equal [ 1, 2, 3 ], result.citations.map(&:number)
    assert_equal [ true, true, false ], result.citations.map(&:cited)
    assert_equal [ 1, 2 ], result.cited_citations.map(&:number)
    assert_equal "개인정보 보호법 제21조(개인정보의 파기)", result.citations.first.heading
    assert_equal "act", result.citations.first.document_type
    assert_in_delta 1.0, result.citations.first.similarity, 1e-6

    request = llm.requests.sole
    assert_equal Answers::Generate::SYSTEM_PROMPT, request[:system]
    assert_equal Answers::Generate::MAX_TOKENS, request[:max_tokens]
    prompt = request[:messages].sole.content
    assert_includes prompt, "[1] 개인정보 보호법 제21조(개인정보의 파기) — 현행\n제21조(개인정보의 파기) 본문"
    assert_includes prompt, "[2] 개인정보 보호법 시행령 제16조(개인정보의 파기방법) — 현행"
    assert_includes prompt, "<질문>\n#{AnswerHelpers::QUESTION}\n</질문>"
    assert_equal :anthropic, result.llm.provider
  end

  test "labels pending, amended and partial articles in the prompt" do
    create_answer_chunk(@act, "제2조", weight: 0, text: "현행 정의")
    create_answer_chunk(@act, "제2조", weight: 0.3, text: "개정될 정의", is_effective: false,
      article_effective_date: Date.new(2027, 3, 9))
    create_answer_chunk(@act, "제75조", weight: 0.6, part_index: 2, part_count: 3)
    llm = FakeLlm.new

    result = generator(llm: llm).call(AnswerHelpers::QUESTION)

    prompt = llm.requests.sole[:messages].sole.content
    assert_includes prompt, "[1] 개인정보 보호법 제2조 — 현행 · 2027-03-09 개정 예정"
    assert_includes prompt, "[2] 개인정보 보호법 제2조 — 시행 전 · 2027-03-09 시행"
    assert_includes prompt, "[3] 개인정보 보호법 제75조 — 현행, 일부 2/3"
    assert result.citations[0].amended?
    assert result.citations[1].pending?
  end

  test "stops without the llm when nothing is close enough" do
    create_answer_chunk(@act, "제1조", weight: nil)
    llm = FakeLlm.new

    result = generator(llm: llm).call(AnswerHelpers::QUESTION)

    assert_equal :no_basis, result.outcome
    assert_nil result.body
    assert_nil result.llm
    assert_equal [ false ], result.citations.map(&:cited)
    assert_empty llm.requests
  end

  test "stops without the llm when there are no chunks" do
    result = generator.call(AnswerHelpers::QUESTION)

    assert_equal :no_basis, result.outcome
    assert_empty result.citations
  end

  test "treats the llm's no basis marker as no basis" do
    create_answer_chunk(@act, "제1조")

    result = generator(llm: FakeLlm.new(text: "근거 없음")).call(AnswerHelpers::QUESTION)

    assert_equal :no_basis, result.outcome
    assert_nil result.body
    assert_equal "fake-model", result.llm.model
  end

  test "reports refusals" do
    create_answer_chunk(@act, "제1조")

    result = generator(llm: FakeLlm.new(text: "", stop_reason: :refusal)).call(AnswerHelpers::QUESTION)

    assert_equal :refused, result.outcome
  end

  test "keeps a truncated answer and drops a cut citation mark" do
    create_answer_chunk(@act, "제1조")

    result = generator(llm: FakeLlm.new(text: "첫 문장입니다 [1]. 둘째 문장은 [1", stop_reason: :max_tokens)).call(AnswerHelpers::QUESTION)

    assert_equal :truncated, result.outcome
    assert_equal "첫 문장입니다 [1]. 둘째 문장은", result.body
    assert result.citations.first.cited
  end

  test "reports the found articles before calling the llm and lets llm errors through" do
    create_answer_chunk(@act, "제1조")
    progress = []

    assert_raises(Llm::RateLimitError) do
      generator(llm: FakeLlm.new(error: Llm::RateLimitError.new("429")))
        .call(AnswerHelpers::QUESTION, on_progress: ->(stage, citations) { progress << [ stage, citations.map(&:number) ] })
    end
    assert_equal [ [ :generating, [ 1 ] ] ], progress
  end
end
