# Llm.provider 대신 쓰는 테스트용 provider. 받은 요청을 기록하고 정해 둔 Llm::Response(또는 예외)를 돌려준다.
class FakeLlm
  attr_reader :requests

  def initialize(text: "답변입니다 [1].", stop_reason: :end_turn, error: nil)
    @text = text
    @stop_reason = stop_reason
    @error = error
    @requests = []
  end

  def generate(messages:, system: nil, max_tokens: Llm::Base::DEFAULT_MAX_TOKENS, temperature: nil)
    requests << { messages: messages, system: system, max_tokens: max_tokens }
    raise @error if @error

    Llm::Response.new(text: @text, provider: :anthropic, model: "fake-model", stop_reason: @stop_reason,
      input_tokens: 120, output_tokens: 30, latency_ms: 1500)
  end
end
