class ApiConfiguration
    class MissingApiKeyError < StandardError; end
    
    def self.validate!
      missing_keys = []
      
      # Check required API keys
      missing_keys << 'SERPAPI_KEY' if ENV['SERPAPI_KEY'].blank?
      missing_keys << 'OPENAI_API_KEY' if ENV['OPENAI_API_KEY'].blank?
      
      if missing_keys.any?
        Rails.logger.error "Missing required API keys: #{missing_keys.join(', ')}"
        
        # In development/test, show warning but continue
        if Rails.env.development? || Rails.env.test?
          Rails.logger.warn "Running in #{Rails.env} mode without some API keys. Features will be limited."
        else
          # In production, fail fast
          raise MissingApiKeyError, "Missing required API keys: #{missing_keys.join(', ')}"
        end
      end
    end
  end
  
  # Run validation after Rails initialization
  Rails.application.config.after_initialize do
    ApiConfiguration.validate!
  end