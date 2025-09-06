# app/services/search/youtube_search_service.rb
class Search::YoutubeSearchService
    def initialize(query)
      @query = query
      @web_service = Search::WebSearchService.new
    end
    
    def search(num_results: 10)
      # Enhance query for better YouTube results
      enhanced_query = "#{@query} site:youtube.com"
      
      results = @web_service.search(enhanced_query, num_results: num_results)
      
      # Enrich results with YouTube metadata
      results.map do |result|
        result[:is_youtube] = true
        result[:content_type] = 'video'
        result
      end
    end
  end