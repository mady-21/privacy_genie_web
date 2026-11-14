# Answer 하나를 끝까지 진행시킨다. 상태가 바뀔 때마다 Answer가 Turbo refresh를 보내 화면이 따라온다.
# LLM 과부하·한도(재시도 가능)는 자동으로 두 번 더 해 보고, 그래도 안 되면 사용자가 "다시 시도"할 수 있게 남긴다.
# 설정·요청 오류, doc 장애·벡터 불일치는 다시 해도 소용없으므로 바로 unavailable로 끝낸다.
class AnswerJob < ApplicationJob
  queue_as :default

  RETRYABLE_ERRORS = [ Llm::RateLimitError, Llm::ServiceUnavailableError ].freeze
  PERMANENT_ERRORS = [ Llm::Error, PrivacyGenieDoc::Client::Error, Documents::Search::ModelMismatch ].freeze

  # 테스트에서 가짜 검색·LLM을 쓰는 Answers::Generate로 바꿀 수 있게 열어 둔다.
  class_attribute :generator_factory, default: ->(answer) { Answers::Generate.new(provider: answer.provider) }

  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 3) do |job, error|
    job.arguments.first.fail!(:temporary, error)
  end
  discard_on ActiveJob::DeserializationError

  def perform(answer)
    # 이미 끝났거나(중복 실행) 보관 기간이 지나 지워진 답변은 건드리지 않는다.
    return unless answer.in_progress? && !answer.purged?

    answer.update!(status: :searching)
    result = generator_factory.call(answer).call(
      answer.question,
      on_progress: ->(_stage, citations) { answer.start_generating!(citations) }
    )
    answer.complete!(result)
  rescue *RETRYABLE_ERRORS
    raise
  rescue *PERMANENT_ERRORS => error
    Rails.logger.error("[AnswerJob] answer=#{answer.id} #{error.class}: #{error.message}")
    answer.fail!(:unavailable, error)
  end
end
