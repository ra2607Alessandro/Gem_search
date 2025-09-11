class Plan < ApplicationRecord
  # Default daily search limit used for global/IP throttles and as fallback
  DEFAULT_DAILY_SEARCH_LIMIT = ENV.fetch('DEFAULT_DAILY_SEARCH_LIMIT', '1000').to_i

  def self.default
    find_by(name: 'Free') || new(name: 'Free', daily_search_limit: DEFAULT_DAILY_SEARCH_LIMIT)
  end

  # Monthly quota helpers
  def monthly_limit
    monthly_search_limit
  end

  def unlimited?
    monthly_search_limit.nil?
  end
end
