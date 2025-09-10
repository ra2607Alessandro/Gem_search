class Rack::Attack
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  throttle('searches-by-user-or-ip', limit: ->(_req) { ::Plan::DEFAULT_DAILY_SEARCH_LIMIT }, period: 1.day) do |req|
    if req.path == '/searches' && req.post?
      (req.env['rack.session'] && req.env['rack.session'][:user_id]) || req.ip
    end
  end
end
