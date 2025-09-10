module Plan
  # Default daily search limit used by Rack::Attack
  DEFAULT_DAILY_SEARCH_LIMIT = ENV.fetch('DEFAULT_DAILY_SEARCH_LIMIT', '1000').to_i
end

