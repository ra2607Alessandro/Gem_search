class Scraping::ContentScraperService
  require 'mechanize'
  require 'readability'

  def initialize(url)
    @url = url
    @agent = setup_mechanize_agent
  end

  def call
    return error_response('Invalid URL') unless valid_url?

    begin
      Rails.logger.info "Scraping content from: #{url}"

      page = fetch_page
      return error_response('Failed to fetch page') unless page

      raw_content = extract_content(page)
      return error_response('No content found') unless raw_content

      sanitized_content = sanitize_content(raw_content)

      {
        title: extract_title(page),
        content: raw_content,
        cleaned_content: sanitized_content,
        success: true
      }
    rescue Mechanize::ResponseCodeError => e
      handle_response_error(e)
    rescue Net::ReadTimeout, Net::OpenTimeout
      error_response('Request timeout')
    rescue SocketError => e
      error_response("DNS/Network error: #{e.message}")
    rescue StandardError => e
      Rails.logger.error "Content scraping error for #{url}: #{e.message}"
      error_response("Unexpected error: #{e.message}")
    end
  end

  private

  attr_reader :url, :agent

  def setup_mechanize_agent
    Mechanize.new do |agent|
      agent.user_agent = 'Mozilla/5.0 (compatible; SearchAssistant/1.0; +https://example.com/bot)'
      agent.read_timeout = 30
      agent.open_timeout = 10
      agent.follow_meta_refresh = true
      agent.redirect_ok = true
      agent.max_history = 2
      agent.max_redirects = 5

      # Enable cookies for JavaScript-heavy sites
      agent.cookie_jar = Mechanize::CookieJar.new

      # Configure SSL
      agent.agent.http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
  end

  def valid_url?
    return false if url.blank?

    begin
      parsed = URI.parse(url)
      parsed.scheme.in?(['http', 'https']) && parsed.host.present?
    rescue URI::InvalidURIError
      false
    end
  end

  def fetch_page
    page = agent.get(url)

    # Check for common blocking patterns
    return nil if page.body.include?('Access Denied') || page.body.include?('403 Forbidden')

    page
  rescue Mechanize::ResponseCodeError
    nil
  end

  def extract_content(page)
    # Primary method: Readability extraction
    begin
      source = Readability::Document.new(
        page.body,
        tags: %w[div p h1 h2 h3 h4 h5 h6 span a img blockquote pre code],
        attributes: %w[href src alt title],
        remove_empty_nodes: true,
        debug: Rails.env.development?
      )

      readable_content = source.content
      return readable_content if readable_content.present? && readable_content.length > 100
    rescue StandardError => e
      Rails.logger.warn "Readability extraction failed for #{url}: #{e.message}"
    end

    # Fallback method: Custom Nokogiri extraction
    extract_with_nokogiri(page)
  end

  def extract_with_nokogiri(page)
    doc = Nokogiri::HTML(page.body)

    # Remove unwanted elements
    doc.search('script, style, nav, header, footer, aside, .ad, .ads, .advertisement, .sidebar').remove

    # Try common content selectors
    content_selectors = [
      'article',
      '.content',
      '.post-content',
      '.entry-content',
      '.article-content',
      '.main-content',
      '#content',
      '#main',
      '.post',
      '.article'
    ]

    content_selectors.each do |selector|
      content = doc.at_css(selector)
      next unless content

      text = content.text.strip
      return text if text.length > 200 # Minimum content length
    end

    # Last resort: extract from body
    body = doc.at_css('body')
    body&.text&.strip || ''
  end

  def extract_title(page)
    doc = Nokogiri::HTML(page.body)

    # Try title tag first
    title = doc.at_css('title')&.text&.strip
    return title if title.present? && title.length > 3

    # Try Open Graph title
    og_title = doc.at_css('meta[property="og:title"]')&.attr('content')&.strip
    return og_title if og_title.present?

    # Try h1 tag
    h1_title = doc.at_css('h1')&.text&.strip
    return h1_title if h1_title.present?

    # Fallback to URL-based title
    URI.parse(url).host || 'Untitled Page'
  end

  def sanitize_content(content)
    return '' unless content

    # Convert to Nokogiri for cleaning
    doc = Nokogiri::HTML.fragment(content)

    # Remove scripts, styles, and tracking elements
    doc.search('script, style, link, meta, noscript, iframe').remove

    # Convert relative URLs to absolute
    doc.search('a[href], img[src]').each do |element|
      if element.name == 'a' && element['href']
        element['href'] = make_absolute_url(element['href'])
      elsif element.name == 'img' && element['src']
        element['src'] = make_absolute_url(element['src'])
      end
    end

    # Clean up whitespace and normalize
    text = doc.text
    text = text.gsub(/\n\s*\n\s*\n/, "\n\n") # Remove extra newlines
    text = text.gsub(/[ \t]+/, ' ') # Normalize spaces
    text.strip
  end

  def make_absolute_url(href)
    return href if href.blank? || href.start_with?('http')

    begin
      URI.join(url, href).to_s
    rescue URI::InvalidURIError
      href
    end
  end

  def handle_response_error(error)
    case error.response_code
    when '404'
      error_response('Page not found')
    when '403', '401'
      error_response('Access forbidden')
    when '429'
      error_response('Rate limited')
    when '500', '502', '503', '504'
      error_response('Server error')
    else
      error_response("HTTP #{error.response_code}")
    end
  end

  def error_response(reason)
    Rails.logger.warn "Content scraping failed for #{url}: #{reason}"

    {
      title: '',
      content: '',
      cleaned_content: '',
      success: false,
      error: reason
    }
  end
end