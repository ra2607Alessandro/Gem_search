class SearchResult < ApplicationRecord
  belongs_to :search
  belongs_to :document
end
