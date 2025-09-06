# app/services/youtube/youtube_detector_service.rb
class Youtube::YoutubeDetectorService
    YOUTUBE_DOMAINS = ['youtube.com', 'www.youtube.com', 'youtu.be', 'm.youtube.com']
    YOUTUBE_KEYWORDS = ['youtube', 'video', 'watch', 'tutorial', 'learn']
    
    def self.youtube_query?(query)
      query_lower = query.downcase
      YOUTUBE_KEYWORDS.any? { |keyword| query_lower.include?(keyword) }
    end
    
    def self.youtube_url?(url)
      uri = URI.parse(url)
      YOUTUBE_DOMAINS.include?(uri.host)
    rescue
      false
    end
  end