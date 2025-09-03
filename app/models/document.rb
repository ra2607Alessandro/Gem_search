
class Document < ApplicationRecord
  has_many :search_results, dependent: :destroy
  has_many :searches, through: :search_results
  
  has_neighbors :embedding, dimensions: 1536 # OpenAI ada-002 dimensions
  
  validates :url, presence: true, uniqueness: true
  validates :title, presence: true
  validates :content, presence: true, if: -> { scraped_at.present? }
  
  scope :with_embeddings, -> { where.not(embedding: nil) }
  
  def self.semantic_search(query_embedding, limit: 10)
    nearest_neighbors(:embedding, query_embedding, distance: "cosine")
      .limit(limit)
      .with_embeddings
  end
  
  def generate_embedding!
    EmbeddingGenerationJob.perform_later(id)
  end
end