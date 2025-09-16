require "openai"

api_key = ENV["OPENAI_API_KEY"].presence ||
          Rails.application.credentials.openai_api_key.presence

if api_key.blank?
  message = "[OpenAI] OPENAI_API_KEY missing – AI responses will fail"
  Rails.logger.error message
  raise message
else
  Rails.application.config.x.openai_client = OpenAI::Client.new(access_token: api_key)
end