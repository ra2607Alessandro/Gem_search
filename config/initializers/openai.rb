require "openai"

  Rails.application.config.after_initialize do
  if ENV['OPENAI_API_KEY'].present?
  $openai_client = OpenAI::Client.new(api_key: ENV['OPENAI_API_KEY'])
  else
    Rails.logger.warn "OpenAI client not initialized: OPENAI_API_KEY missing"
    $openai_client = nil
  end
end