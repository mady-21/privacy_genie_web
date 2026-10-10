class Document < ApplicationRecord
  DOCUMENT_TYPES = %w[act decree guide].freeze

  has_many :document_chunks,
    dependent: :destroy,
    inverse_of: :document

  has_many :document_supplements,
    dependent: :destroy,
    inverse_of: :document

  validates :source_key, :name, presence: true
  validates :source_key, uniqueness: true
  validates :document_type, inclusion: { in: DOCUMENT_TYPES }
end
