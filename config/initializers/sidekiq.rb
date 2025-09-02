# Note: Rails 8 uses Solid Queue by default
# This is here if you want to switch to Sidekiq later

# Sidekiq.configure_server do |config|
#   config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }
# end

# Sidekiq.configure_client do |config|
#   config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }
# end
