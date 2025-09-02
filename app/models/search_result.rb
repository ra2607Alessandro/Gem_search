
class SearchResult < ApplicationRecord
  belongs_to :search
  belongs_to :document
  has_many :citations, dependent: :destroy
  
  validates :relevance_score, presence: true, 
    numericality: { greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0 }
  
  scope :ordered_by_relevance, -> { order(relevance_score: :desc) }
end