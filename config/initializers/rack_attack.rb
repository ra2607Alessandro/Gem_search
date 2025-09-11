class Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # Lightweight per-IP safety net for POST /searches
  throttle('searches-by-ip', limit: ->(_req) { ::Plan::DEFAULT_DAILY_SEARCH_LIMIT }, period: 1.day) do |req|
    req.path == '/searches' && req.post? ? req.ip : nil
  end
end
