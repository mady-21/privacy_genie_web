class DocumentChunk < ApplicationRecord
  belongs_to :document, inverse_of: :document_chunks
  belongs_to :document_supplement, optional: true, inverse_of: :document_chunks

  scope :ordered, -> { order(:position) }
  scope :main_body, -> { where(document_supplement_id: nil) }
  scope :supplementary, -> { where.not(document_supplement_id: nil) }

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :position, uniqueness: { scope: :document_id }
  validates :article_number, :text, presence: true
  validate :metadata_is_an_object
  validate :supplement_belongs_to_document

  private

  def metadata_is_an_object
    errors.add(:metadata, "JSON 객체여야 합니다") unless metadata.is_a?(Hash)
  end

  def supplement_belongs_to_document
    if document_supplement && document_supplement.document != document
      errors.add(:document_supplement, "청크와 같은 문서에 속해야 합니다")
    end
  end
end
