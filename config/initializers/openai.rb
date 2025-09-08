require "openai"

api_key = Rails.application.credentials.openai_api_key.presence ||
          ENV["OPENAI_API_KEY"].presence

if api_key.blank?
  Rails.logger.error "[OpenAI] OPENAI_API_KEY missing – AI responses will fail"
  Rails.application.config.x.openai_client = nil
else
  Rails.application.config.x.openai_client = OpenAI::Client.new(access_token: api_key)
end
