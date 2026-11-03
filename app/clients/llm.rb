# Claude, GPT 등 LLM을 같은 인터페이스로 호출한다. provider는 플래그(심볼)로 고른다.
#   Llm.provider.generate(...)            # 기본값(LLM_PROVIDER)
#   Llm.provider(:openai).generate(...)   # 호출할 때 지정
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
    anthropic: "Llm::Anthropic",
    openai: "Llm::OpenAI"
  }.freeze

  # 사용할 수 있는 provider 플래그. 예: [:anthropic, :openai]
  def self.provider_names = PROVIDERS.keys

  # name은 :anthropic, :openai 같은 플래그다. 환경 변수·폼 값처럼 문자열로 와도 받는다.
  def self.provider(name = nil, config: Rails.application.config_for(:llm))
    name = (name.presence || config[:default_provider]).to_s.to_sym
    class_name = PROVIDERS[name] or raise ConfigurationError, "알 수 없는 LLM provider입니다: #{name.inspect} (#{provider_names.join(', ')})"
    settings = config.dig(:providers, name) || {}
    class_name.constantize.new(**settings.symbolize_keys)
  end
end
