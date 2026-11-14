ENV["RAILS_ENV"] ||= "test"

require_relative "../config/environment"
require "rails/test_help"
require_relative "support/fake_doc_client"
require_relative "support/llm_provider_contract"
require_relative "support/fake_llm"
require_relative "support/answer_helpers"

module EmbeddingHelpers
  # 축별 가중치로 만든 길이 1의 벡터. 예: embedding(0 => 1, 1 => 1)은 0번·1번 축 사이 45도.
  def embedding(weights = { 0 => 1.0 })
    vector = Array.new(DocumentChunk::EMBEDDING_DIMENSION, 0.0)
    weights.each { |axis, weight| vector[axis] = weight.to_f }
    norm = Math.sqrt(vector.sum { |value| value * value })
    vector.map { |value| value / norm }
  end
end

class ActiveSupport::TestCase
  include EmbeddingHelpers
end
