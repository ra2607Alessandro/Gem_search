
class Search < ApplicationRecord
  has_many :search_results, dependent: :destroy
  has_many :documents, through: :search_results
  belongs_to :user, optional: true

  scope :for_user, ->(user) { where(user_id: user.id) }

  
  has_neighbors :query_embedding, dimensions: 1536
  
  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3, scraping: 4, retryable: 5 }, default: :pending
  
  validates :query, presence: true, length: { minimum: 1, maximum: 1000 }
  validates :goal, length: { maximum: 500 }, allow_blank: true
  validates :rules, length: { maximum: 500 }, allow_blank: true
  
  after_create :process_search_async
  
  private
  
  def process_search_async
    SearchProcessingJob.perform_later(id)
  end
end
