module Llm
  # Anthropic Messages API (POST /v1/messages).
  class Anthropic < Base
    API_VERSION = "2023-06-01"
    STOP_REASONS = {
      "end_turn" => :end_turn,
      "stop_sequence" => :end_turn,
      "max_tokens" => :max_tokens,
      "refusal" => :refusal
    }.freeze

    def provider_name = :anthropic

    private

    def default_base_url = "https://api.anthropic.com"
    def path = "/v1/messages"
    def headers = { "x-api-key" => @api_key, "anthropic-version" => API_VERSION }

    def payload(messages:, system:, max_tokens:, temperature:)
      {
        model: model,
        max_tokens: max_tokens,
        system: system.presence,
        temperature: temperature,
        messages: messages.map { |message| { role: message.role, content: message.content } }
      }.compact
    end

    def parse(body)
      Response.new(
        text: body.fetch("content", []).select { |block| block["type"] == "text" }.sum("") { |block| block["text"] },
        provider: nil,
        model: body["model"],
        stop_reason: STOP_REASONS.fetch(body["stop_reason"], :other),
        input_tokens: body.dig("usage", "input_tokens"),
        output_tokens: body.dig("usage", "output_tokens"),
        latency_ms: nil
      )
    end
  end
end
