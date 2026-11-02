require "test_helper"

class LlmTest < ActiveSupport::TestCase
  CONFIG = {
    default_provider: "anthropic",
    providers: {
      anthropic: { api_key: "a-key", model: "claude-model", base_url: nil },
      openai: { api_key: "o-key", model: "gpt-model", base_url: "https://compatible.test" }
    }
  }.freeze

  test "provider builds the default provider from config" do
    provider = Llm.provider(config: CONFIG)

    assert_instance_of Llm::Anthropic, provider
    assert_equal "claude-model", provider.model
  end

  test "provider builds a named provider" do
    provider = Llm.provider("openai", config: CONFIG)

    assert_instance_of Llm::OpenAI, provider
    assert_equal "gpt-model", provider.model
  end

  test "unknown provider raises configuration error" do
    error = assert_raises(Llm::ConfigurationError) { Llm.provider("gemini", config: CONFIG) }
    assert_includes error.message, "gemini"
  end

  test "missing api key names the env variable to set" do
    config = CONFIG.deep_merge(providers: { openai: { api_key: nil } })

    error = assert_raises(Llm::ConfigurationError) { Llm.provider("openai", config: config) }
    assert_includes error.message, "OPENAI_API_KEY"
  end

  test "config file loads with every registered provider" do
    config = Rails.application.config_for(:llm)

    assert_includes Llm::PROVIDERS.keys, config[:default_provider]
    assert_equal Llm::PROVIDERS.keys.sort, config[:providers].keys.map(&:to_s).sort
  end

  test "message accepts only user and assistant roles with content" do
    assert_equal :user, Llm::Message.user("질문").role
    assert_equal :assistant, Llm::Message.new(role: "assistant", content: "답").role
    assert_raises(ArgumentError) { Llm::Message.new(role: :system, content: "지시") }
    assert_raises(ArgumentError) { Llm::Message.user("  ") }
  end
end
