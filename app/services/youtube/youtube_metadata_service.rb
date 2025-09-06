# app/services/youtube/youtube_metadata_service.rb
class Youtube::YoutubeMetadataService
    require 'open-uri'
    require 'json'
    
    def initialize(url)
      @url = url
      @video_id = extract_video_id(url)
    end
    
    def extract_metadata
      return error_response('Invalid YouTube URL') unless @video_id
      
      # Use oEmbed API (no key required)
      oembed_url = "https://www.youtube.com/oembed?url=#{@url}&format=json"
      response = URI.open(oembed_url).read
      data = JSON.parse(response)
      
      {
        success: true,
        title: data['title'],
        content: build_content_from_metadata(data),
        author: data['author_name'],
        thumbnail: data['thumbnail_url']
      }
    rescue => e
      error_response("Failed to extract YouTube metadata: #{e.message}")
    end
    
    private
    
    def extract_video_id(url)
      # Extract video ID from various YouTube URL formats
      patterns = [
        /(?:youtube\.com\/watch\?v=|youtu\.be\/)([^&\n?#]+)/,
        /youtube\.com\/embed\/([^&\n?#]+)/,
        /youtube\.com\/v\/([^&\n?#]+)/
      ]
      
      patterns.each do |pattern|
        match = url.match(pattern)
        return match[1] if match
      end
      nil
    end
    
    def build_content_from_metadata(data)
      # Build searchable content from metadata
      content = []
      content << "Title: #{data['title']}"
      content << "Author: #{data['author_name']}"
      content << "Type: #{data['type']}"
      
      # Add description if available from page meta tags
      content << fetch_description_from_page
      
      content.join("\n\n")
    end
    
    def fetch_description_from_page
      # Quick fetch of meta description without full page load
      page = URI.open(@url, 'User-Agent' => 'Mozilla/5.0').read(10000) # Read first 10KB
      description_match = page.match(/<meta name="description" content="([^"]+)"/)
      description_match ? "Description: #{description_match[1]}" : ""
    rescue
      ""
    end
  end