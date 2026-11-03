module Llm
  # OpenAI Chat Completions API (POST /v1/chat/completions).
  # 같은 형식을 쓰는 호환 서버도 base_url만 바꿔 붙일 수 있다.
  class OpenAI < Base
    FINISH_REASONS = {
      "stop" => :end_turn,
      "length" => :max_tokens,
      "content_filter" => :refusal
    }.freeze

    def provider_name = :openai

    private

    def default_base_url = "https://api.openai.com"
    def path = "/v1/chat/completions"
    def headers = { "Authorization" => "Bearer #{@api_key}" }

    def payload(messages:, system:, max_tokens:, temperature:)
      chat = messages.map { |message| { role: message.role, content: message.content } }
      chat.unshift({ role: "system", content: system }) if system.present?
      { model: model, max_completion_tokens: max_tokens, temperature: temperature, messages: chat }.compact
    end

    def parse(body)
      choice = body.dig("choices", 0) || {}
      message = choice["message"] || {}
      Response.new(
        text: message["content"].to_s,
        provider: nil,
        model: body["model"],
        stop_reason: message["refusal"].present? ? :refusal : FINISH_REASONS.fetch(choice["finish_reason"], :other),
        input_tokens: body.dig("usage", "prompt_tokens"),
        output_tokens: body.dig("usage", "completion_tokens"),
        latency_ms: nil
      )
    end
  end
end
