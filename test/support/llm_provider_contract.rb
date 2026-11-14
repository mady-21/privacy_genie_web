# 모든 Llm provider가 지켜야 하는 동작. provider 테스트에 include하고 아래 메서드를 정의한다.
#   provider_class, provider_path, success_body(text:)
module LlmProviderContract
  extend ActiveSupport::Concern

  included do
    setup do
      @stubs = Faraday::Adapter::Test::Stubs.new
      @provider = build_provider
    end

    test "contract: generate returns a normalized response" do
      @stubs.post(provider_path) { [ 200, json_headers, JSON.generate(success_body(text: "답변")) ] }

      response = @provider.generate(messages: [ Llm::Message.user("질문") ])

      assert_equal "답변", response.text
      assert_equal @provider.provider_name, response.provider
      assert_equal :end_turn, response.stop_reason
      assert_kind_of Integer, response.input_tokens
      assert_kind_of Integer, response.output_tokens
      assert_operator response.latency_ms, :>=, 0
      @stubs.verify_stubbed_calls
    end

    test "contract: requires api key and model" do
      assert_raises(Llm::ConfigurationError) { build_provider(api_key: "") }
      assert_raises(Llm::ConfigurationError) { build_provider(model: nil) }
    end

    test "contract: rejects empty messages without calling the api" do
      assert_raises(ArgumentError) { @provider.generate(messages: []) }
    end

    test "contract: maps http status to error classes with the api message" do
      {
        401 => Llm::AuthenticationError,
        403 => Llm::AuthenticationError,
        400 => Llm::InvalidRequestError,
        429 => Llm::RateLimitError,
        500 => Llm::ServiceUnavailableError,
        529 => Llm::ServiceUnavailableError
      }.each do |status, error_class|
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post(provider_path) { [ status, json_headers, JSON.generate("error" => { "message" => "이유 #{status}" }) ] }

        error = assert_raises(error_class) { build_provider(stubs: stubs).generate(messages: [ Llm::Message.user("질문") ]) }
        assert_includes error.message, status.to_s
        assert_includes error.message, "이유 #{status}"
      end
    end

    test "contract: timeouts and connection failures are retryable" do
      [ Faraday::TimeoutError, Faraday::ConnectionFailed ].each do |failure|
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post(provider_path) { raise failure, "실패" }

        assert_raises(Llm::ServiceUnavailableError) { build_provider(stubs: stubs).generate(messages: [ Llm::Message.user("질문") ]) }
      end
    end

    test "contract: non-json error body still raises with the status" do
      @stubs.post(provider_path) { [ 502, {}, "Bad Gateway" ] }

      error = assert_raises(Llm::ServiceUnavailableError) { @provider.generate(messages: [ Llm::Message.user("질문") ]) }
      assert_includes error.message, "502"
    end
  end

  private

  def build_provider(stubs: @stubs, api_key: "test-key", model: "test-model")
    connection = Faraday.new(url: "https://llm.test") { |faraday| faraday.adapter :test, stubs }
    provider_class.new(api_key: api_key, model: model, connection: connection)
  end

  def json_headers = { "Content-Type" => "application/json" }
end
