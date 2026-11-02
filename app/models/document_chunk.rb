class DocumentChunk < ApplicationRecord
  # privacy-genie-doc의 임베딩 모델(nlpai-lab/KURE-v1) 차원. 컬럼도 vector(1024)로 고정되어 있다.
  EMBEDDING_DIMENSION = 1024

  belongs_to :document, inverse_of: :document_chunks

  has_neighbors :embedding, dimensions: EMBEDDING_DIMENSION

  scope :ordered, -> { order(:position) }
  scope :effective, -> { where(is_effective: true) }
  scope :pending, -> { where(is_effective: false) }

  validates :chunk_id, presence: true, uniqueness: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :position, uniqueness: { scope: :document_id }
  validates :part_index, :part_count, numericality: { only_integer: true, greater_than: 0 }
  validates :article_number, :text, :embedding, presence: true
  validates :is_effective, inclusion: { in: [ true, false ] }
  validates :article_effective_date, presence: true, unless: :is_effective?
  validate :part_index_within_part_count
  validate :metadata_is_an_object

  private

  def part_index_within_part_count
    if part_index.is_a?(Integer) && part_count.is_a?(Integer) && part_index > part_count
      errors.add(:part_index, "part_count보다 클 수 없습니다")
    end
  end

  def metadata_is_an_object
    errors.add(:metadata, "JSON 객체여야 합니다") unless metadata.is_a?(Hash)
  end
end
