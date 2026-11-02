module Documents
  # 질문을 privacy-genie-doc으로 임베딩한 뒤, 같은 모델로 적재한 청크 중 가까운 것을 pgvector로 찾는다.
  # 아직 시행 전인 조문(is_effective=false)도 결과에 넣되 status로 구분한다.
  class Search
    DEFAULT_LIMIT = 5
    # 같은 글자의 현행본·미시행본을 하나로 합치면 후보가 줄어들므로 넉넉히 뽑는다.
    CANDIDATE_FACTOR = 3

    class ModelMismatch < StandardError; end

    Result = Data.define(:chunk, :distance, :pending_amendment_date) do
      # 벡터가 정규화되어 있어 코사인 거리 = 1 - 코사인 유사도다.
      def similarity = 1 - distance
      def status = chunk.is_effective ? :effective : :pending
      def effective_date = chunk.article_effective_date
    end

    def initialize(client: PrivacyGenieDoc::Client.new)
      @client = client
    end

    def call(question, limit: DEFAULT_LIMIT, effective_only: false)
      response = @client.embed([ question ])
      model = response["model"]
      vector = response["embeddings"]&.first
      check_question_vector!(response, vector)

      scope = DocumentChunk.where(document: searchable_documents(model))
      scope = scope.effective if effective_only
      candidates = scope
        .includes(:document)
        .nearest_neighbors(:embedding, vector, distance: "cosine")
        .limit(limit * CANDIDATE_FACTOR)
        .to_a

      results = drop_identical_pending(candidates).first(limit)
      pending_dates = pending_amendment_dates(results)
      results.map do |chunk|
        Result.new(
          chunk: chunk,
          distance: chunk.neighbor_distance,
          pending_amendment_date: chunk.is_effective ? pending_dates[[ chunk.document_id, chunk.article_number ]] : nil
        )
      end
    end

    private

    def check_question_vector!(response, vector)
      if response["dimension"] != DocumentChunk::EMBEDDING_DIMENSION || vector&.size != DocumentChunk::EMBEDDING_DIMENSION
        raise ModelMismatch, "질문 벡터가 #{DocumentChunk::EMBEDDING_DIMENSION}차원이 아닙니다: #{response['dimension']}"
      end
    end

    # 질문과 다른 모델로 적재된 문서는 거리를 비교할 수 없으므로 뺀다. 남는 문서가 없으면 재동기화가 필요하다.
    def searchable_documents(model)
      with_chunks = Document.where(id: DocumentChunk.select(:document_id))
      stale = with_chunks.where("embedding_model IS DISTINCT FROM ?", model).pluck(:source_key)
      return Document.where(embedding_model: model) if stale.empty?

      message = "임베딩 모델(#{model})과 다른 모델로 적재된 문서가 있습니다: #{stale.join(', ')}. documents:sync를 다시 돌려야 합니다"
      raise ModelMismatch, message unless with_chunks.exists?(embedding_model: model)

      Rails.logger.warn(message)
      Document.where(embedding_model: model)
    end

    # 현행본과 미시행본의 같은 조각이 글자까지 같으면(예: 제75조 첫 조각) 결과 칸을 두 번 차지하므로 미시행본을 뺀다.
    # 개정 예정이라는 정보는 현행본의 pending_amendment_date로 남는다.
    def drop_identical_pending(candidates)
      effective_keys = candidates.select(&:is_effective).to_set { |chunk| version_key(chunk) }
      candidates.reject { |chunk| !chunk.is_effective && effective_keys.include?(version_key(chunk)) }
    end

    def version_key(chunk)
      [ chunk.document_id, chunk.article_number, chunk.part_index, chunk.text ]
    end

    # 현행 조문 중 같은 조번호의 미시행 개정본이 있는 것에 가장 이른 시행일을 붙인다.
    def pending_amendment_dates(chunks)
      effective = chunks.select(&:is_effective)
      return {} if effective.empty?

      DocumentChunk.pending
        .where(document_id: effective.map(&:document_id).uniq, article_number: effective.map(&:article_number).uniq)
        .group(:document_id, :article_number)
        .minimum(:article_effective_date)
    end
  end
end
