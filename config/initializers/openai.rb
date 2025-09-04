require "openai"

Rails.application.config.after_initialize do
  $openai_client = OpenAI::Client.new(api_key: ENV['OPENAI_API_KEY'])
end