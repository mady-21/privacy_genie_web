# 보관 기간(Answer::RETENTION)이 지난 답변의 질문·본문·근거 조문을 지운다. config/recurring.yml에서 매일 돈다.
class PurgeExpiredAnswersJob < ApplicationJob
  queue_as :default

  def perform
    Answer.expired.find_each(&:purge!)
  end
end
