module Llm
  # stop_reason은 provider마다 다른 값을 :end_turn, :max_tokens, :refusal, :other로 맞춘 것이다.
  Response = Data.define(:text, :provider, :model, :stop_reason, :input_tokens, :output_tokens, :latency_ms) do
    def truncated? = stop_reason == :max_tokens
    def refused? = stop_reason == :refusal
  end
end
