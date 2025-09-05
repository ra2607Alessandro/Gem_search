class SearchProcessingJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(search_id)
    @search = Search.find(search_id)
    @metrics = { started_at: Time.current, steps_completed: [] }

    Rails.logger.info "[SearchProcessingJob] Starting search #{search_id}: #{@search.query}"

      # Update status to scraping
      @search.update!(status: :scraping)

      generate_query_embedding
    

      # Step 1: Perform web search
      search_results = perform_web_search

      if search_results.empty?
        handle_search_failure("No search results found")
        return
      end

      # Step 2: Process and deduplicate documents
      @search.update!(status: :scraping)
    processed_count = process_search_results(search_results)
    
    # Store expected document count for tracking
    @search.update!(expected_documents_count: processed_count)
    
    log_metrics
    
  rescue StandardError => e
    handle_job_error(e)
    raise # Re-raise for retry mechanism
  end
  
  private
  
  def generate_query_embedding
    return if @search.query_embedding.present?
    
    Rails.logger.info "[SearchProcessingJob] Generating query embedding"
    
    service = Ai::EmbeddingService.new(@search.query)
    embedding = service.call
    
    if embedding.present? && embedding.is_a?(Array) && embedding.length == 1536
      @search.update!(query_embedding: embedding)
      @metrics[:steps_completed] << :query_embedding
    else
      Rails.logger.warn "[SearchProcessingJob] Failed to generate valid query embedding"
    end
  rescue => e
    Rails.logger.error "[SearchProcessingJob] Query embedding error: #{e.message}"
  end
  
  def perform_web_search
    Rails.logger.info "[SearchProcessingJob] Performing web search"
    
    service = Search::WebSearchService.new
    results = service.search(@search.query, num_results: 10)
    
    @metrics[:steps_completed] << :web_search
    @metrics[:search_results_count] = results.length
    
    results
  rescue => e
    Rails.logger.error "[SearchProcessingJob] Web search error: #{e.message}"
    []
  end
  
  def process_search_results(results)
    processed_count = 0
    
    results.each_with_index do |result, index|
      begin
        process_single_result(result, index)
        processed_count += 1
      rescue => e
        Rails.logger.error "[SearchProcessingJob] Error processing result #{index}: #{e.message}"
      end
    end
    
    @metrics[:steps_completed] << :document_processing
    @metrics[:documents_processed] = processed_count
    
    processed_count
  end
  
  def process_single_result(result, position)
    # Find or create document
    document = Document.find_or_initialize_by(url: result[:url])
    
    # Update document info
    document.title = result[:title] if result[:title].present?
    document.save!
    
    # Create search result association
    search_result = SearchResult.find_or_create_by(
      search: @search,
      document: document
    ) do |sr|
      sr.relevance_score = calculate_relevance_score(position)
    end
    
    # Queue scraping job only if document needs scraping
    if should_scrape_document?(document)
      WebScrapingJob.perform_later(
        document.id,
        @search.id,
        position,
        result
      )
    else
      Rails.logger.info "[SearchProcessingJob] Skipping scrape for #{document.url} (recently scraped)"
      # Still check for completion in case all docs are already scraped
      Scraping::ScrapingCompletionService.check(@search.id)
    end
  end
  
  def should_scrape_document?(document)
    return true if document.scraped_at.nil?
    return true if document.content.blank?
    
    # Re-scrape if older than 7 days
    document.scraped_at < 7.days.ago
  end
  
  def calculate_relevance_score(position)
    # Higher score for earlier positions
    base_score = 1.0 - (position.to_f / 10.0)
    (base_score ** 0.7).round(4)
  end
  
  def handle_search_failure(reason)
    @search.update!(
      status: :failed,
      error_message: reason
    )
    
    Rails.logger.error "[SearchProcessingJob] Search #{@search.id} failed: #{reason}"
  end
  
  def handle_job_error(error)
    Rails.logger.error "[SearchProcessingJob] Job error for search #{@search.id}: #{error.message}"
    Rails.logger.error error.backtrace.first(10).join("\n")
    
    @search.update!(
      status: :failed,
      error_message: "Search processing error: #{error.message}"
    )
    
    log_metrics
  end
  
  def log_metrics
    @metrics[:ended_at] = Time.current
    @metrics[:duration] = @metrics[:ended_at] - @metrics[:started_at]
    
    Rails.logger.info "[SearchProcessingJob] Metrics for search #{@search.id}: #{@metrics.to_json}"
  end
end