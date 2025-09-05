require "httparty"

class Search::WebSearchService
  include HTTParty
  base_uri 'https://serpapi.com'

  class SearchError < StandardError; end
  class ApiKeyMissingError < SearchError; end
  class QuotaExceededError < SearchError; end
  

  def initialize
    @api_key = ENV['SERPAPI_KEY']
  end

  def search(query, num_results: 10)
    validate_api_key!
    
  Rails.logger.info "[WebSearchService] Searching for: #{query}"

  begin
    response = execute_search(query, num_results)
    results = parse_results(response)
    
    Rails.logger.info "[WebSearchService] Found #{results.length} results"
    results
    
  rescue QuotaExceededError => e
    Rails.logger.error "[WebSearchService] Quota exceeded: #{e.message}"
    fallback_results(query)
  rescue HTTParty::TimeoutError => e
    Rails.logger.error "[WebSearchService] Request timeout: #{e.message}"
    retry_with_backoff { execute_search(query, num_results) }
  rescue StandardError => e
    Rails.logger.error "[WebSearchService] Search failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    []
  end
end


  private

  def validate_api_key!
    if @api_key.blank?
      raise ApiKeyMissingError, "SERPAPI_KEY is not configured"
    end
  end


  def execute_search(query, num_results)
    self.class.get('/search', {
      query: {
        engine: 'google',
        q: query,
        api_key: @api_key,
        num: [num_results, 20].min,
        safe: 'active',
        hl: 'en',
        gl: 'us'
      },
      timeout: 15,
      headers: {
        'User-Agent' => 'GemSearch/1.0'
      }
    })
  end


  def parse_results(response)
    unless response.success?
      handle_api_error(response)
    end
    
    data = response.parsed_response
    return [] unless data && data['organic_results']
    
    data['organic_results'].map.with_index do |item, index|
      {
        title: clean_text(item['title']),
        url: normalize_url(item['link']),
        snippet: clean_text(item['snippet']),
        display_link: item['displayed_link'] || extract_domain(item['link']),
        position: index
      }
    end.select { |r| valid_result?(r) }
  end
  
  def handle_api_error(response)
    error_data = response.parsed_response || {}
    error_message = error_data['error'] || "HTTP #{response.code}"
    
    if response.code == 429 || error_message.include?('quota')
      raise QuotaExceededError, error_message
    else
      raise SearchError, "SerpAPI error: #{error_message}"
    end
  end

  def valid_result?(result)
    result[:url].present? && 
    result[:title].present? && 
    result[:url].match?(/^https?:\/\//)
  end
  
  def clean_text(text)
    return '' if text.nil?
    text.strip.gsub(/\s+/, ' ')
  end
  
  def normalize_url(url)
    return url if url.nil?
    url.strip.gsub(/\s/, '%20')
  end
  
  def extract_domain(url)
    URI.parse(url).host rescue url
  end
  
  def retry_with_backoff(max_retries: 3)
    retries = 0
    begin
      yield
    rescue => e
      retries += 1
      if retries <= max_retries
        sleep(2 ** retries)
        retry
      else
        raise e
      end
    end
  end
  
  def fallback_results(query)
    # Return cached or default results as fallback
    Rails.logger.warn "[WebSearchService] Using fallback results"
    []
  end
end
  