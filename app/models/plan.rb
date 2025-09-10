class Plan < ApplicationRecord
  DEFAULT_DAILY_SEARCH_LIMIT = 100

  def self.default
    first || new(daily_search_limit: DEFAULT_DAILY_SEARCH_LIMIT)
  end
end
