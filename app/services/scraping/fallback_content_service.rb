# app/services/scraping/fallback_content_service.rb
class Scraping::FallbackContentService
    def self.generate_from_search_result(url, title, snippet)
      cleaned = snippet.to_s.strip.squeeze(' ')
      {
        success: true,
        title: title,
        content: build_content(url, title, cleaned),
        cleaned_content: cleaned,
        content_chunks: cleaned.present? ? [cleaned] : [],
        url: url,
        scraped_at: Time.current
      }
    end
    
    private
    
    def self.build_content(url, title, snippet)
      content = []
      content << "Title: #{title}"
      content << "URL: #{url}"
      content << "Summary: #{snippet}"
      
      # Extract domain-specific information
      domain = URI.parse(url).host rescue url
      content << "Source: #{domain}"
      
      content.join("\n\n")
    end
  end