
class Document < ApplicationRecord
  has_many :search_results, dependent: :destroy
  has_many :searches, through: :search_results

  has_neighbors :embedding, dimensions: 1536

  validates :url, presence: true, uniqueness: true
  validates :title, presence: true
  # Remove content validation - allow nil/empty content for failed scrapes

  scope :with_embeddings, -> { where.not(embedding: nil) }
  scope :with_content, -> { where.not(cleaned_content: [nil, '']) }
  scope :recently_scraped, -> { where('scraped_at > ?', 7.days.ago) }

  def self.semantic_search(query_embedding, limit: 10)
    nearest_neighbors(:embedding, query_embedding, distance: "cosine")
      .limit(limit)
      .with_embeddings
  end

  def content_available?
    cleaned_content.present? && cleaned_content.length > 50
  end

  def generate_embedding!
    return unless content_available?
    EmbeddingGenerationJob.perform_later(id)
  end
end