class WebScrapingJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 5.seconds, attempts: 2

  def perform(document_id, search_id, position, search_result_data)
    @document = Document.find(document_id)
    @search = Search.find(search_id)
    @position = position
    @metrics = { started_at: Time.current }

    Rails.logger.info "[WebScrapingJob] Starting scrape for document #{document_id}: #{@document.url}"

    scraped_data = scrape_content
    
     # If scraping failed, try fallback content generation
    if !scraped_data[:success] && search_result_data.present?
     Rails.logger.info "[WebScrapingJob] Using fallback content for #{@document.url}"
      scraped_data = Scraping::FallbackContentService.generate_from_search_result(
       @document.url,
       search_result_data[:title] || @document.title,
       search_result_data[:snippet] || "")
  end

    # Always update document with results (success or failure)
    update_document(scraped_data)
    
    if scraped_data[:success]
      # Generate embeddings if content available
      generate_embeddings if @document.content_available?
      
      # Update search result relevance
      update_relevance_score
    end
    
    # Always check for completion after every scrape attempt to see if the whole batch is done
    Scraping::ScrapingCompletionService.check(search_id)
    
    log_metrics(scraped_data[:success])
    
  rescue StandardError => e
    handle_job_error(e)
    raise # Re-raise for retry
  end
  
  private
  
  def scrape_content
    service = Scraping::ContentScraperService.new(@document.url)
    result = service.call
    
    @metrics[:scraping_success] = result[:success]
    @metrics[:content_length] = result[:content]&.length || 0
    
    result
  end
  
  def update_document(scraped_data)
    @document.assign_attributes(
      title: scraped_data[:title].presence || @document.title,
      content: scraped_data[:success] ? scraped_data[:content] : nil,
      scraped_at: Time.current
    )
    
    # Add error tracking
    if !scraped_data[:success]
      @document.content = nil  # Ensure no partial content
      Rails.logger.warn "[WebScrapingJob] Scraping failed for #{@document.url}: #{scraped_data[:error]}"
    end
    
    @document.save!
  end
  
  def generate_embeddings
    Rails.logger.info "[WebScrapingJob] Queueing embedding generation for document #{@document.id}"
    EmbeddingGenerationJob.perform_later(@document.id)
    @metrics[:embedding_queued] = true
  end
  
  def update_relevance_score
    search_result = SearchResult.find_by(search: @search, document: @document)
    return unless search_result
    
    # Enhance relevance score based on content quality
    content_factor = calculate_content_factor
    new_score = combine_scores(search_result.relevance_score, content_factor)
    
    search_result.update!(relevance_score: new_score)
    @metrics[:relevance_updated] = true
  end
  
  def calculate_content_factor
    return 0.0 unless @document.content.present?
    
    length = @document.content.length
    case length
    when 0...200 then 0.0
    when 200...500 then 0.1
    when 500...1000 then 0.2
    else 0.3
    end
  end
  
  def combine_scores(base_score, content_factor)
    # Weight: 70% position, 30% content quality
    combined = (base_score * 0.7) + (content_factor * 0.3)
    [combined, 1.0].min.round(4)
  end
  
  def handle_job_error(error)
    Rails.logger.error "[WebScrapingJob] Error for document #{@document.id}: #{error.message}"
    
    # Mark document as processed but failed
    @document.update!(scraped_at: Time.current) rescue nil
    
    # Still check completion
    Scraping::ScrapingCompletionService.check(@search.id) rescue nil
  end
  
  def log_metrics(success)
    @metrics[:ended_at] = Time.current
    @metrics[:duration] = @metrics[:ended_at] - @metrics[:started_at]
    @metrics[:success] = success
    
    Rails.logger.info "[WebScrapingJob] Metrics for document #{@document.id}: #{@metrics.to_json}"
  end
end
