module Documents
  # privacy-genie-doc의 GET /documents/{type} 응답에 맞춰 문서 하나의 청크와 벡터를 DB에 맞춘다.
  # chunk_id 기준으로 upsert하고 응답에 없는 청크는 지운다. 같은 응답으로 여러 번 돌려도 결과가 같다.
  class Sync
    DOCUMENT_TYPES = %w[act decree].freeze

    class InvalidPayload < StandardError; end

    Result = Data.define(:source_key, :inserted, :deleted, :kept, :reloaded)

    def initialize(client: PrivacyGenieDoc::Client.new)
      @client = client
    end

    def call(document_type)
      payload = @client.document(document_type)
      validate!(document_type, payload)
      chunk_ids = payload["chunks"].map { |chunk| chunk["chunk_id"] }

      # 다른 트랜잭션 안에서 불려도 문서 하나가 통째로 되돌려지도록 savepoint를 쓴다.
      Document.transaction(requires_new: true) do
        document = Document.lock.find_or_initialize_by(source_key: payload["source_key"])
        check_document!(document, payload, chunk_ids)

        # 다른 모델로 만든 벡터와 섞이면 거리 비교가 의미 없으므로, 모델이 바뀌면 전부 다시 넣는다.
        reloaded = document.embedding_model.present? && document.embedding_model != payload["embedding_model"]
        document.update!(
          document_type: document_type,
          name: payload["name"],
          law_number: payload["law_number"],
          law_effective_date: parse_date(payload["law_effective_date"]),
          embedding_model: payload["embedding_model"]
        )

        chunks = document.document_chunks
        existing_ids = reloaded ? [] : chunks.pluck(:chunk_id)
        deleted = (reloaded ? chunks : chunks.where.not(chunk_id: chunk_ids)).delete_all
        # position이 밀려도 한 문장 안에서 맞춰지므로 문장 끝에 검사하는 position 제약에 걸리지 않는다.
        DocumentChunk.upsert_all(payload["chunks"].map { |chunk| row(document, chunk) }, unique_by: :chunk_id)

        Result.new(
          source_key: document.source_key,
          inserted: (chunk_ids - existing_ids).size,
          deleted: deleted,
          kept: (chunk_ids & existing_ids).size,
          reloaded: reloaded
        )
      end
    end

    private

    def validate!(document_type, payload)
      raise InvalidPayload, "응답이 JSON 객체가 아닙니다" unless payload.is_a?(Hash)

      errors = []
      errors << "document_type이 #{document_type}가 아닙니다: #{payload['document_type']}" if payload["document_type"] != document_type
      errors << "source_key가 없습니다" if payload["source_key"].blank?
      errors << "embedding_model이 없습니다" if payload["embedding_model"].blank?
      if payload["embedding_dimension"] != DocumentChunk::EMBEDDING_DIMENSION
        errors << "embedding_dimension이 #{DocumentChunk::EMBEDDING_DIMENSION}가 아닙니다: #{payload['embedding_dimension']}"
      end

      chunks = payload["chunks"]
      if !chunks.is_a?(Array) || chunks.empty?
        # 빈 응답을 그대로 받으면 문서의 청크가 전부 지워지므로 거부한다.
        errors << "chunks가 비어 있습니다"
      else
        errors.concat(chunk_errors(chunks))
      end

      raise InvalidPayload, "#{document_type} 응답이 올바르지 않습니다: #{errors.join(', ')}" if errors.any?
    end

    def chunk_errors(chunks)
      errors = []
      ids = chunks.map { |chunk| chunk["chunk_id"] }
      errors << "chunk_id가 비어 있습니다" if ids.any?(&:blank?)
      duplicates = ids.tally.select { |_, count| count > 1 }.keys
      errors << "chunk_id가 중복됩니다: #{duplicates.join(', ')}" if duplicates.any?
      errors << "position이 1부터 이어지지 않습니다" if chunks.map { |chunk| chunk["position"] } != (1..chunks.size).to_a

      invalid = chunks.reject { |chunk| valid_embedding?(chunk["embedding"]) }.map { |chunk| chunk["chunk_id"] }
      if invalid.any?
        errors << "embedding이 숫자 #{DocumentChunk::EMBEDDING_DIMENSION}개가 아닙니다: #{invalid.first(3).join(', ')}"
      end
      errors
    end

    def valid_embedding?(embedding)
      embedding.is_a?(Array) &&
        embedding.size == DocumentChunk::EMBEDDING_DIMENSION &&
        embedding.all? { |value| value.is_a?(Numeric) }
    end

    def check_document!(document, payload, chunk_ids)
      if document.persisted? && document.document_type != payload["document_type"]
        raise InvalidPayload, "#{document.source_key}는 이미 #{document.document_type} 문서입니다"
      end

      foreign = DocumentChunk.where(chunk_id: chunk_ids)
      foreign = foreign.where.not(document_id: document.id) if document.persisted?
      if foreign.exists?
        raise InvalidPayload, "다른 문서에 이미 있는 chunk_id가 있습니다: #{foreign.limit(3).pluck(:chunk_id).join(', ')}"
      end
    end

    def row(document, chunk)
      {
        document_id: document.id,
        chunk_id: chunk["chunk_id"],
        position: chunk["position"],
        article_number: chunk["article_number"],
        article_title: chunk["article_title"],
        chapter: chunk["chapter"],
        section: chunk["section"],
        text: chunk["text"],
        part_index: chunk["part_index"],
        part_count: chunk["part_count"],
        is_effective: chunk["is_effective"],
        article_effective_date: parse_date(chunk["article_effective_date"]),
        metadata: chunk["metadata"] || {},
        embedding: chunk["embedding"]
      }
    end

    def parse_date(value)
      value.nil? ? nil : Date.iso8601(value)
    rescue Date::Error, TypeError
      raise InvalidPayload, "ISO 날짜가 아닙니다: #{value.inspect}"
    end
  end
end
