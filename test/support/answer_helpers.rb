# 답변 관련 테스트의 공용 준비물: 법·시행령 문서, 질문 벡터를 아는 가짜 doc 클라이언트, 청크·답변 생성.
module AnswerHelpers
  QUESTION = "탈퇴 회원 정보는 언제 지우나요?".freeze

  def setup_documents
    @act = Document.create!(source_key: "privacy", name: "개인정보 보호법", document_type: "act", embedding_model: FakeDocClient::MODEL)
    @decree = Document.create!(source_key: "privacy_decree", name: "개인정보 보호법 시행령", document_type: "decree",
      embedding_model: FakeDocClient::MODEL)
    @doc_client = FakeDocClient.new(embeddings: { QUESTION => embedding(0 => 1) })
  end

  # weight가 클수록 질문에서 멀다. 0이면 유사도 1, nil이면 질문과 직교(유사도 0).
  def create_answer_chunk(document, article_number, weight: 0, text: nil, **attributes)
    @chunk_positions = (@chunk_positions || Hash.new(0)).tap { |positions| positions[document.id] += 1 }
    position = @chunk_positions[document.id]
    vector = weight.nil? ? embedding(1 => 1) : embedding(0 => 1, 1 => weight)
    document.document_chunks.create!(
      chunk_id: "#{document.source_key}:#{article_number}:#{position}",
      position: position, article_number: article_number,
      text: text || "#{article_number} 본문 #{position}",
      part_index: 1, part_count: 1, embedding: vector,
      **attributes
    )
  end

  def generator(llm: FakeLlm.new)
    Answers::Generate.new(search: Documents::Search.new(client: @doc_client), llm: llm)
  end

  def citation(number, cited: true, **attributes)
    Answers::Generate::Citation.new(
      number: number, cited: cited, document_type: "act", document_name: "개인정보 보호법",
      article_number: "제21조", article_title: "개인정보의 파기", chapter: nil, part_index: 1, part_count: 1,
      text: "제21조(개인정보의 파기) ① 개인정보처리자는 보유기간의 경과 등 개인정보가 불필요하게 되었을 때에는 지체 없이 파기하여야 한다.",
      status: :effective, effective_date: nil, pending_amendment_date: nil, similarity: 0.71,
      **attributes
    )
  end

  def completed_answer(outcome: :answered, body: "지체 없이 파기해야 합니다 [1].", citations: [ citation(1) ], **attributes)
    answer = Answer.create!(question: QUESTION, **attributes)
    llm = Llm::Response.new(text: body.to_s, provider: :anthropic, model: "fake-model", stop_reason: :end_turn,
      input_tokens: 120, output_tokens: 30, latency_ms: 1500)
    answer.complete!(Answers::Generate::Result.new(outcome: outcome, body: body, citations: citations,
      dropped_citation_numbers: [], llm: llm))
    answer
  end
end

class ActiveSupport::TestCase
  include AnswerHelpers
end
