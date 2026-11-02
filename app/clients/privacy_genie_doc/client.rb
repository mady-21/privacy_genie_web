module PrivacyGenieDoc
  class Client
    class Error < StandardError; end
    # 벡터 파일이 없거나 낡았을 때(503). doc에서 rebuild_chunks.py를 다시 돌려야 한다.
    class ServiceUnavailable < Error; end
    # 지원하지 않는 문서 종류, 빈 텍스트, 요청 제한 초과(422).
    class InvalidRequest < Error; end

    OPEN_TIMEOUT = 2
    # 문서 응답은 약 4MB JSON, 질문 인코딩은 약 0.6초다.
    READ_TIMEOUT = 30

    def initialize(
      base_url: ENV.fetch("PRIVACY_GENIE_DOC_URL"),
      connection: nil
    )
      @connection = connection || Faraday.new(url: base_url) do |faraday|
        faraday.options.open_timeout = OPEN_TIMEOUT
        faraday.options.timeout = READ_TIMEOUT
      end
    end

    def health
      request { @connection.get("/health") }
    end

    # 미리 계산한 청크와 벡터를 문서 단위로 받는다. document_type은 act 또는 decree.
    def document(document_type)
      request { @connection.get("/documents/#{document_type}") }
    end

    # 텍스트(최대 64개)를 문서와 같은 모델로 임베딩한다. {"model", "dimension", "embeddings"}를 돌려준다.
    def embed(texts)
      request do
        @connection.post("/embeddings", JSON.generate(texts: texts), "Content-Type" => "application/json")
      end
    end

    private

    def request
      response = yield
      case response.status
      when 200..299 then JSON.parse(response.body)
      when 503 then raise ServiceUnavailable, error_message(response)
      when 422 then raise InvalidRequest, error_message(response)
      else raise Error, error_message(response)
      end
    rescue Faraday::Error, JSON::ParserError => error
      raise Error, "privacy-genie-doc API error: #{error.message}"
    end

    def error_message(response)
      detail = begin
        JSON.parse(response.body)["detail"]
      rescue JSON::ParserError, TypeError
        nil
      end
      [ "privacy-genie-doc API error: #{response.status}", detail ].compact.join(" - ")
    end
  end
end
