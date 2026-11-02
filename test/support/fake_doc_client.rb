# PrivacyGenieDoc::Client 대신 쓰는 테스트용 클라이언트. 실제 doc 서비스와 같은 모양의 해시를 돌려준다.
class FakeDocClient
  MODEL = "nlpai-lab/KURE-v1".freeze

  attr_accessor :model
  attr_reader :documents, :embeddings, :embed_requests

  # documents: { "act" => 응답 해시 또는 예외 }, embeddings: { "질문" => 벡터 }
  def initialize(documents: {}, embeddings: {}, model: MODEL)
    @documents = documents
    @embeddings = embeddings
    @model = model
    @embed_requests = []
  end

  def document(document_type)
    response = documents.fetch(document_type)
    raise response if response.is_a?(Exception)

    response.deep_dup
  end

  def embed(texts)
    embed_requests << texts
    {
      "model" => model,
      "dimension" => DocumentChunk::EMBEDDING_DIMENSION,
      "embeddings" => texts.map { |text| embeddings.fetch(text) }
    }
  end
end
