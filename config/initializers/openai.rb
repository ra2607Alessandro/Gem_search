require "openai"

OpenAI.configure do |config|
  config.access_token = ENV['OPENAI_API_KEY']
end

Rails.application.config.after_initialize do
  $openai_client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
end
