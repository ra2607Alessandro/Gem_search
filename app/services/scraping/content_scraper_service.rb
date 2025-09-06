class Scraping::ContentScraperService
  require 'mechanize'
  require 'readability'
  require 'timeout'
  
  TIMEOUT_SECONDS = 30
  MIN_CONTENT_LENGTH = 50
  MAX_CONTENT_LENGTH = 50_000

  def initialize(url)
    @url = url
    @agent = setup_mechanize_agent
  end

  def call
    return error_response('Invalid URL') unless valid_url?

    if Youtube::YoutubeDetectorService.youtube_url?(@url)
      youtube_service = Youtube::YoutubeMetadataService.new(@url)
      return youtube_service.extract_metadata
    end

    Timeout.timeout(TIMEOUT_SECONDS) do
      execute_scraping
    end

  rescue Timeout::Error
    error_response('Scraping timeout')
  rescue StandardError => e
    Rails.logger.error "[ContentScraperService] Error scraping #{@url}: #{e.message}"
    error_response("Scraping failed: #{e.message}")
  end
  
  private
  
  def execute_scraping
    Rails.logger.info "[ContentScraperService] Starting scrape: #{@url}"
    
    page = fetch_page
    return error_response('Failed to fetch page') unless page
    
    # Try multiple extraction methods
    content = extract_with_readability(page) || 
              extract_with_nokogiri(page) ||
              extract_fallback(page)
    
    if content && content.length >= MIN_CONTENT_LENGTH
      success_response(page, content)
    else
      error_response('Insufficient content extracted')
    end
  end
  
  def fetch_page
    @agent ||= setup_mechanize_agent
    response = @agent.get(@url)
    
    # Check for common blocking patterns
    if blocked_response?(response)
      Rails.logger.warn "[ContentScraperService] Blocked by site: #{@url}"
      return nil
    end
    
    response
  rescue Mechanize::ResponseCodeError => e
    handle_http_error(e)
    nil
  rescue => e
    Rails.logger.error "[ContentScraperService] Fetch error: #{e.message}"
    nil
  end
  
  def setup_mechanize_agent
    Mechanize.new do |agent|
      agent.user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
      agent.read_timeout = 25
      agent.open_timeout = 10
      agent.follow_meta_refresh = true
      agent.max_history = 2
      
      # Handle redirects properly for Mechanize 2.x
      if agent.respond_to?(:max_redirects=)
        agent.max_redirects = 5
      elsif agent.respond_to?(:redirection_limit=)
        agent.redirection_limit = 5
      end
      
      agent.cookie_jar = Mechanize::CookieJar.new
      
      # Relaxed SSL for development
      if Rails.env.development?
        agent.agent.http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      
      # Anti-bot detection headers
      agent.request_headers = {
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language' => 'en-US,en;q=0.5',
        'Accept-Encoding' => 'gzip, deflate, br',
        'DNT' => '1',
        'Connection' => 'keep-alive',
        'Upgrade-Insecure-Requests' => '1'
      }
    end
  end
  
  def blocked_response?(response)
    return false unless response.body
    
    blocking_patterns = [
      'Access Denied',
      '403 Forbidden', 
      'CloudFlare',
      'Please enable JavaScript',
      'robot',
      'captcha'
    ]
    
    body_lower = response.body.downcase
    blocking_patterns.any? { |pattern| body_lower.include?(pattern.downcase) }
  end
  
  def extract_with_readability(page)
    return nil unless page.body.present?
    
    doc = Readability::Document.new(
      page.body,
      tags: %w[div p h1 h2 h3 h4 h5 h6 span a img blockquote pre code ul ol li article section],
      attributes: %w[href src alt title],
      remove_empty_nodes: true,
      remove_unlikely_candidates: true,
      weight_classes: true,
      clean_conditionally: true,
      debug: false
    )
    
    content = doc.content
    return nil if content.blank?
    
    # Clean and normalize
    cleaned = Sanitize.fragment(content, 
      elements: %w[p h1 h2 h3 h4 h5 h6 blockquote pre ul ol li],
      remove_empty_elements: true
    )
    
    text = Nokogiri::HTML.fragment(cleaned).text.squeeze(' ').strip
    text.length >= MIN_CONTENT_LENGTH ? text : nil
    
  rescue StandardError => e
    Rails.logger.warn "[ContentScraperService] Readability extraction failed: #{e.message}"
    nil
  end
  
  def extract_with_nokogiri(page)
    doc = Nokogiri::HTML(page.body)
    
    # Remove script, style, and other non-content elements
    doc.css('script, style, nav, header, footer, aside, .ad, .ads, #cookie, .popup').remove
    
    # Try multiple content selectors
    content_selectors = [
      'main article',
      'article[role="main"]',
      'div[role="main"]',
      '.post-content',
      '.entry-content', 
      '.article-content',
      '.content-body',
      '#main-content',
      'article',
      '.content',
      'main',
      '#content'
    ]
    
    content_selectors.each do |selector|
      elements = doc.css(selector)
      next if elements.empty?
      
      text = elements.map(&:text).join(' ').squeeze(' ').strip
      return text if text.length >= MIN_CONTENT_LENGTH
    end
    
    nil
  rescue StandardError => e
    Rails.logger.warn "[ContentScraperService] Nokogiri extraction failed: #{e.message}"
    nil
  end
  
  def extract_fallback(page)
    # Last resort - extract all paragraph text
    doc = Nokogiri::HTML(page.body)
    paragraphs = doc.css('p').map(&:text).select { |p| p.length > 20 }
    
    return nil if paragraphs.empty?
    
    content = paragraphs.join(' ').squeeze(' ').strip
    content.length >= MIN_CONTENT_LENGTH ? content[0...MAX_CONTENT_LENGTH] : nil
  rescue
    nil
  end
  
  def extract_title(page)
    doc = Nokogiri::HTML(page.body)
    
    # Try multiple title sources
    title = doc.at_css('meta[property="og:title"]')&.attr('content') ||
            doc.at_css('meta[name="twitter:title"]')&.attr('content') ||
            doc.at_css('title')&.text ||
            doc.at_css('h1')&.text ||
            'Untitled'
    
    clean_text(title)
  end
  
  def success_response(page, content)
    {
      success: true,
      title: extract_title(page),
      content: content[0...MAX_CONTENT_LENGTH],
      cleaned_content: clean_text(content[0...MAX_CONTENT_LENGTH]),
      url: @url,
      scraped_at: Time.current
    }
  end
  
  def error_response(reason)
    {
      success: false,
      title: '',
      content: '',
      cleaned_content: '',
      error: reason,
      url: @url,
      scraped_at: Time.current
    }
  end
  
  def handle_http_error(error)
    Rails.logger.warn "[ContentScraperService] HTTP #{error.response_code} for #{@url}"
  end
  
  def valid_url?
    return false if @url.blank?
    
    uri = URI.parse(@url)
    uri.scheme.in?(['http', 'https']) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
  
  def clean_text(text)
    return '' if text.blank?
    text.strip.squeeze(' ').gsub(/[\r\n]+/, ' ')
  end
end