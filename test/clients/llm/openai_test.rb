require "test_helper"

class Llm::OpenAITest < ActiveSupport::TestCase
  include LlmProviderContract

  test "sends chat completions request with system message first" do
    @stubs.post("/v1/chat/completions") do |env|
      assert_equal "Bearer test-key", env.request_headers["Authorization"]
      assert_equal(
        {
          "model" => "test-model",
          "max_completion_tokens" => 200,
          "temperature" => 0.2,
          "messages" => [
            { "role" => "system", "content" => "법령에 근거해 답하세요" },
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

  test "omits system message and temperature when not given" do
    @stubs.post("/v1/chat/completions") do |env|
      body = JSON.parse(env.body)
      assert_equal [ "user" ], body["messages"].map { |message| message["role"] }
      assert_not body.key?("temperature")
      assert_equal Llm::Base::DEFAULT_MAX_TOKENS, body["max_completion_tokens"]
      [ 200, json_headers, JSON.generate(success_body(text: "답변")) ]
    end

    @provider.generate(messages: [ Llm::Message.user("질문") ])
  end

  test "normalizes finish reasons" do
    { "stop" => :end_turn, "length" => :max_tokens, "content_filter" => :refusal, "tool_calls" => :other }.each do |raw, normalized|
      body = success_body(text: "답")
      body["choices"][0]["finish_reason"] = raw
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/v1/chat/completions") { [ 200, json_headers, JSON.generate(body) ] }

      assert_equal normalized, build_provider(stubs: stubs).generate(messages: [ Llm::Message.user("질문") ]).stop_reason
    end
  end

  test "refusal message is reported as refusal with empty text" do
    body = success_body(text: "답")
    body["choices"][0]["message"] = { "role" => "assistant", "content" => nil, "refusal" => "도와드릴 수 없습니다" }
    @stubs.post("/v1/chat/completions") { [ 200, json_headers, JSON.generate(body) ] }

    response = @provider.generate(messages: [ Llm::Message.user("질문") ])
    assert response.refused?
    assert_equal "", response.text
  end

  private

  def provider_class = Llm::OpenAI
  def provider_path = "/v1/chat/completions"

  def success_body(text:)
    {
      "id" => "chatcmpl-1",
      "object" => "chat.completion",
      "model" => "test-model",
      "choices" => [
        { "index" => 0, "message" => { "role" => "assistant", "content" => text }, "finish_reason" => "stop" }
      ],
      "usage" => { "prompt_tokens" => 12, "completion_tokens" => 7, "total_tokens" => 19 }
    }
  end
end
