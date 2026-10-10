class DocumentSupplement < ApplicationRecord
  belongs_to :document, inverse_of: :document_supplements
  has_many :document_chunks, inverse_of: :document_supplement

  before_destroy :prevent_destroy_with_chunks

  validates :source_key, :heading, presence: true
  validates :source_key, uniqueness: { scope: :document_id }
  validate :preamble_is_an_array_of_strings
  validate :document_cannot_change_with_chunks

  private

  def preamble_is_an_array_of_strings
    unless preamble.is_a?(Array) && preamble.all? { |line| line.is_a?(String) }
      errors.add(:preamble, "문자열 배열이어야 합니다")
    end
  end

  def document_cannot_change_with_chunks
    if persisted? && will_save_change_to_document_id? && document_chunks.exists?
      errors.add(:document, "청크가 연결된 부칙의 소속 문서는 변경할 수 없습니다")
    end
  end

  def prevent_destroy_with_chunks
    if DocumentChunk.where(document_supplement_id: id).exists?
      raise ActiveRecord::DeleteRestrictionError.new(:document_chunks)
    end
  end

end
