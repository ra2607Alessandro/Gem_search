# app/services/youtube/youtube_api_service.rb
class Youtube::YoutubeApiService
    require 'google/apis/youtube_v3'
    
    def initialize
      @service = Google::Apis::YoutubeV3::YouTubeService.new
      @service.key = ENV['YOUTUBE_API_KEY'] # Optional, works without for basic queries
    end
    
    def search_videos(query, max_results: 10)
      response = @service.list_searches(
        'snippet',
        q: query,
        type: 'video',
        max_results: max_results,
        order: 'relevance'
      )
      
      format_results(response.items)
    rescue => e
      Rails.logger.error "[YoutubeApiService] API error: #{e.message}"
      []
    end
    
    private
    
    def format_results(items)
      items.map do |item|
        {
          title: item.snippet.title,
          url: "https://youtube.com/watch?v=#{item.id.video_id}",
          snippet: item.snippet.description,
          channel: item.snippet.channel_title,
          published_at: item.snippet.published_at,
          thumbnail: item.snippet.thumbnails.default.url
        }
      end
    end
  end