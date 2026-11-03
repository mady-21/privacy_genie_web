require "test_helper"

class Llm::AnthropicTest < ActiveSupport::TestCase
  include LlmProviderContract

  test "sends messages api request with system prompt and headers" do
    @stubs.post("/v1/messages") do |env|
      assert_equal "test-key", env.request_headers["x-api-key"]
      assert_equal Llm::Anthropic::API_VERSION, env.request_headers["anthropic-version"]
      assert_equal(
        {
          "model" => "test-model",
          "max_tokens" => 200,
          "system" => "법령에 근거해 답하세요",
          "temperature" => 0.2,
          "messages" => [
            { "role" => "user", "content" => "질문" },
            { "role" => "assistant", "content" => "이전 답" },
            { "role" => "user", "content" => "추가 질문" }
          ]
        },
        JSON.parse(env.body)
      )
      [ 200, json_headers, JSON.generate(success_body(text: "답변")) ]
    end

    @provider.generate(
      messages: [ Llm::Message.user("질문"), Llm::Message.assistant("이전 답"), Llm::Message.user("추가 질문") ],
      system: "법령에 근거해 답하세요", max_tokens: 200, temperature: 0.2
    )
    @stubs.verify_stubbed_calls
  end

  test "omits optional fields when not given" do
    @stubs.post("/v1/messages") do |env|
      body = JSON.parse(env.body)
      assert_not body.key?("system")
      assert_not body.key?("temperature")
      assert_equal Llm::Base::DEFAULT_MAX_TOKENS, body["max_tokens"]
      [ 200, json_headers, JSON.generate(success_body(text: "답변")) ]
    end

    @provider.generate(messages: [ Llm::Message.user("질문") ])
  end

  test "joins text blocks and ignores other block types" do
    body = success_body(text: "첫 문단").merge(
      "content" => [
        { "type" => "thinking", "thinking" => "생각" },
        { "type" => "text", "text" => "첫 문단" },
        { "type" => "text", "text" => " 둘째 문단" }
      ]
    )
    @stubs.post("/v1/messages") { [ 200, json_headers, JSON.generate(body) ] }

    assert_equal "첫 문단 둘째 문단", @provider.generate(messages: [ Llm::Message.user("질문") ]).text
  end

  test "normalizes stop reasons" do
    {
      "end_turn" => :end_turn, "stop_sequence" => :end_turn, "max_tokens" => :max_tokens,
      "refusal" => :refusal, "pause_turn" => :other
    }.each do |raw, normalized|
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/v1/messages") { [ 200, json_headers, JSON.generate(success_body(text: "답").merge("stop_reason" => raw)) ] }

      assert_equal normalized, build_provider(stubs: stubs).generate(messages: [ Llm::Message.user("질문") ]).stop_reason
    end
  end

  private

  def provider_class = Llm::Anthropic
  def provider_path = "/v1/messages"

  def success_body(text:)
    {
      "id" => "msg_1",
      "type" => "message",
      "role" => "assistant",
      "model" => "test-model",
      "content" => [ { "type" => "text", "text" => text } ],
      "stop_reason" => "end_turn",
      "usage" => { "input_tokens" => 12, "output_tokens" => 7 }
    }
  end
end
