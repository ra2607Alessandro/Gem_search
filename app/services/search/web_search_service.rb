require "httparty"

class Search::WebSearchService
  include HTTParty
  base_uri 'https://serpapi.com'

  def initialize
    @api_key = ENV.fetch('SERPAPI_KEY')
  end

  def search(query, num_results: 10)
    Rails.logger.info "Searching for: #{query}"
    
    response = self.class.get('/search', {
      query: {
        engine: 'google',
        q: query,
        api_key: @api_key,
        num: [num_results, 20].min, # SerpApi allows up to 100 results
        safe: 'active' # Filter adult content
      },
      timeout: 15
    })

    if response.success?
      parse_results(response.parsed_response)
    else
      handle_api_error(response)
    end
  rescue HTTParty::TimeoutError
    Rails.logger.error "SerpApi timeout for query: #{query}"
    []
  rescue StandardError => e
    Rails.logger.error "SerpApi error: #{e.message}"
    []
  end

  private

  def parse_results(data)
    return [] unless data['organic_results']

    data['organic_results'].map do |item|
      {
        title: item['title'],
        url: item['link'],
        snippet: item['snippet'],
        display_link: item['displayed_link'] || extract_domain(item['link'])
      }
    end
  end

  def extract_domain(url)
    URI.parse(url).host rescue url
  end

  def handle_api_error(response)
    error_data = response.parsed_response
    error_message = error_data&.dig('error') || 'Unknown SerpApi error'
    Rails.logger.error "SerpApi error: #{error_message}"
    []
  end
end