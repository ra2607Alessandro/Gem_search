# Note: Rails 8 uses Solid Queue by default
# This is here if you want to switch to Sidekiq later

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }

  schedule_file = "config/schedule.yml"

  if File.exist?(schedule_file)
    Sidekiq::Cron::Job.load_from_hash YAML.load_file(schedule_file)
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1') }
end
