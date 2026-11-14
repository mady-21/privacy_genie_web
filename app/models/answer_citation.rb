# 답변의 근거 조문 스냅샷. number는 답변 본문의 [n]과 같다.
class AnswerCitation < ApplicationRecord
  include Answers::CitationLabels

  belongs_to :answer, inverse_of: :citations

  scope :cited, -> { where(cited: true) }
  scope :uncited, -> { where(cited: false) }

  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :answer_id }
  validates :document_type, :document_name, :article_number, :text, :similarity, presence: true
  validates :status, inclusion: { in: %w[effective pending] }

  # Answers::Generate::Citation → 컬럼 해시
  def self.attributes_from(citation)
    citation.to_h.merge(status: citation.status.to_s)
  end
end
