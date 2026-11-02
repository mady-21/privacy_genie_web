# Claude, GPT 등 LLM을 같은 인터페이스로 호출한다.
#   Llm.provider.generate(messages: [ Llm::Message.user("질문") ], system: "...")
module Llm
  class Error < StandardError; end
  # API 키·모델 미설정, 모르는 provider 이름.
  class ConfigurationError < Error; end
  # 401·403. 키가 틀렸거나 권한이 없다. 재시도해도 소용없다.
  class AuthenticationError < Error; end
  # 400·404·413·422. 요청 자체가 잘못됐다. 재시도해도 소용없다.
  class InvalidRequestError < Error; end
  # 429. 잠시 뒤 재시도할 수 있다.
  class RateLimitError < Error; end
  # 5xx, 과부하, 타임아웃, 연결 실패. 잠시 뒤 재시도하거나 다른 provider로 넘길 수 있다.
  class ServiceUnavailableError < Error; end

  PROVIDERS = {
    "anthropic" => "Llm::Anthropic",
    "openai" => "Llm::OpenAI"
  }.freeze

  def self.provider(name = nil, config: Rails.application.config_for(:llm))
    name = (name || config[:default_provider]).to_s
    class_name = PROVIDERS[name] or raise ConfigurationError, "알 수 없는 LLM provider입니다: #{name.inspect} (#{PROVIDERS.keys.join(', ')})"
    settings = config.dig(:providers, name.to_sym) || {}
    class_name.constantize.new(**settings.symbolize_keys)
  end
end
