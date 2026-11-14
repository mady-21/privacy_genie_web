# 사용자 질문 하나와 그 답변. AnswerJob이 pending → searching → generating → completed/failed로 진행시키고,
# 상태가 바뀔 때마다 Turbo refresh를 보내 답변 화면이 스스로 다시 그려지게 한다.
class Answer < ApplicationRecord
  MAX_QUESTION_LENGTH = 1_000
  # 보관 기간이 지나면 질문·답변·근거 조문을 지우고 상태·토큰 같은 통계만 남긴다.
  RETENTION = 90.days

  has_secure_token :token
  has_many :citations, -> { order(:number) }, class_name: "AnswerCitation", dependent: :delete_all, inverse_of: :answer

  enum :status, %w[pending searching generating completed failed].index_with(&:itself), default: :pending
  enum :outcome, Answers::Generate::OUTCOMES.map(&:to_s).index_with(&:itself), prefix: true
  # temporary: LLM 과부하·한도라 잠시 뒤 다시 시도할 수 있음.
  # unavailable: LLM 설정·요청 오류, doc 장애·벡터 불일치라 다시 해도 소용없음(운영자가 고쳐야 함).
  enum :error_kind, %w[temporary unavailable].index_with(&:itself), prefix: :error

  broadcasts_refreshes

  validates :question, presence: { message: "질문을 입력하세요." },
    length: { maximum: MAX_QUESTION_LENGTH, message: "질문은 #{MAX_QUESTION_LENGTH.to_fs(:delimited)}자까지 입력할 수 있습니다." },
    unless: :purged?

  scope :expired, -> { where(purged_at: nil).where(created_at: ...RETENTION.ago) }
  scope :created_today, -> { where(created_at: Time.current.all_day) }

  # 저장되는 질문은 항상 마스킹을 거친다. 무엇을 가렸는지는 masked_kinds로 화면에 알린다.
  def question=(value)
    if value.nil?
      self.masked_kinds = []
      return super(nil)
    end

    masking = Answers::Masking.call(value.to_s.strip)
    self.masked_kinds = masking.kinds
    super(masking.text)
  end

  def to_param = token
  def purged? = purged_at.present?
  def in_progress? = pending? || searching? || generating?
  def retryable? = failed? && error_temporary?

  # 검색이 끝나 LLM을 부르기 직전. LLM이 실패해도 화면에 근거 조문을 보여 줄 수 있게 먼저 저장한다.
  def start_generating!(citations)
    transaction do
      replace_citations(citations)
      update!(status: :generating)
    end
  end

  def complete!(result)
    llm = result.llm
    transaction do
      replace_citations(result.citations)
      update!(
        status: :completed, outcome: result.outcome, body: result.body,
        dropped_citation_numbers: result.dropped_citation_numbers,
        provider: llm&.provider || provider, model: llm&.model, stop_reason: llm&.stop_reason,
        input_tokens: llm&.input_tokens, output_tokens: llm&.output_tokens, latency_ms: llm&.latency_ms,
        error_kind: nil, error_message: nil, completed_at: Time.current
      )
    end
  end

  # error_message는 로그·운영 확인용이다. 화면에는 error_kind에 맞춘 안내 문구만 보여 준다.
  def fail!(kind, error)
    update!(status: :failed, error_kind: kind, error_message: "#{error.class}: #{error.message}".truncate(1_000),
      completed_at: Time.current)
  end

  def retry!
    update!(status: :pending, error_kind: nil, error_message: nil, completed_at: nil)
  end

  def purge!
    transaction do
      citations.delete_all
      update!(question: nil, body: nil, error_message: nil, purged_at: Time.current)
    end
  end

  private

  def replace_citations(new_citations)
    citations.delete_all
    citations.reset
    new_citations.each { |citation| citations.create!(AnswerCitation.attributes_from(citation)) }
  end
end
