require "openai"

api_key = ENV["OPENAI_API_KEY"]
if api_key.blank?
  raise "OpenAI client not initialized: OPENAI_API_KEY missing"
end

Rails.application.config.x.openai_client = OpenAI::Client.new(access_token: api_key)

