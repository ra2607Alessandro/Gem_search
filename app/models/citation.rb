
class Citation < ApplicationRecord
  belongs_to :search_result
  
  validates :source_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp }
  validates :snippet, presence: true, length: { maximum: 500 }
end