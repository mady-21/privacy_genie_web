module Llm
  # provider 공통: 설정 검증, HTTP 호출, 상태 코드 → 에러 변환, 지연시간 측정.
  # 하위 클래스는 path, headers, payload, parse만 provider 형식에 맞게 채운다.
  # 재시도는 여기서 하지 않는다. 호출하는 쪽(Job 등)이 RateLimitError·ServiceUnavailableError를 보고 정한다.
  class Base
    DEFAULT_MAX_TOKENS = 1024
    OPEN_TIMEOUT = 5
    # 긴 답변 생성은 수십 초 걸릴 수 있다.
    READ_TIMEOUT = 120

    attr_reader :model

    def initialize(api_key:, model:, base_url: nil, connection: nil)
      raise ConfigurationError, "#{provider_name} API 키가 없습니다. #{api_key_env}를 설정하세요" if api_key.blank?
      raise ConfigurationError, "#{provider_name} 모델이 없습니다. #{model_env}를 설정하세요" if model.blank?

      @api_key = api_key
      @model = model
      @connection = connection || Faraday.new(url: base_url.presence || default_base_url) do |faraday|
        faraday.options.open_timeout = OPEN_TIMEOUT
        faraday.options.timeout = READ_TIMEOUT
      end
    end

    def generate(messages:, system: nil, max_tokens: DEFAULT_MAX_TOKENS, temperature: nil)
      raise ArgumentError, "messages가 비어 있습니다" if messages.blank?

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      body = post(payload(messages: messages, system: system, max_tokens: max_tokens, temperature: temperature))
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      parse(body).with(provider: provider_name, latency_ms: latency_ms)
    end

    def provider_name = raise(NotImplementedError)

    private

    def default_base_url = raise(NotImplementedError)
    def path = raise(NotImplementedError)
    def headers = raise(NotImplementedError)
    def payload(messages:, system:, max_tokens:, temperature:) = raise(NotImplementedError)
    # provider와 latency_ms는 generate가 채우므로 nil로 둔 Response를 돌려준다.
    def parse(body) = raise(NotImplementedError)
    def api_key_env = "#{provider_name.upcase}_API_KEY"
    def model_env = "#{provider_name.upcase}_MODEL"

    def post(payload)
      response = @connection.post(path, JSON.generate(payload), headers.merge("Content-Type" => "application/json"))
      raise_for_status(response)
      JSON.parse(response.body)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
      raise ServiceUnavailableError, "#{provider_name} 연결 실패: #{error.message}"
    rescue JSON::ParserError => error
      raise Error, "#{provider_name} 응답을 해석할 수 없습니다: #{error.message}"
    end

    def raise_for_status(response)
      error_class =
        case response.status
        when 200..299 then return
        when 401, 403 then AuthenticationError
        when 429 then RateLimitError
        when 400, 404, 413, 422 then InvalidRequestError
        when 500..599 then ServiceUnavailableError
        else Error
        end
      raise error_class, [ "#{provider_name} API error: #{response.status}", error_detail(response) ].compact.join(" - ")
    end

    # Anthropic과 OpenAI 모두 {"error": {"message": ...}} 형식이다.
    def error_detail(response)
      body = JSON.parse(response.body)
      body.dig("error", "message") if body.is_a?(Hash) && body["error"].is_a?(Hash)
    rescue JSON::ParserError, TypeError
      nil
    end
  end
end
