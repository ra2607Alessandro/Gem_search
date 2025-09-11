class SearchProcessingJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: ->(executions) { (2**executions).seconds }, attempts: 3

  def perform(search_id)
    @search = Search.find(search_id)
    @metrics = { started_at: Time.current, steps_completed: [] }

    Rails.logger.info "[SearchProcessingJob] Starting search #{search_id}: #{@search.query}"

      # Update status to scraping and broadcast to clients
      @search.update!(status: :scraping)
      SearchesController.broadcast_status_update(@search.id)

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
    
    # Store expected document count for tracking and update results list
    @search.update!(expected_documents_count: processed_count)
    SearchesController.broadcast_results_update(@search.id)
    
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

    if Youtube::YoutubeDetectorService.youtube_query?(@search.query)
      service = Search::YoutubeSearchService.new(@search.query)
      # Youtube service holds query in initializer; its search takes only keyword args
      results = service.search(num_results: 8)
    else
      service = Search::WebSearchService.new
      results = service.search(@search.query, num_results: 8)
    end

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
      # Ensure normalized content exists so the AI can use this document
      ensure_normalized_content(document, result)
      # Still check for completion in case all docs are already scraped
      Scraping::ScrapingCompletionService.check(@search.id)
    end

    # Broadcast updated results after each search result is processed
    SearchesController.broadcast_results_update(@search.id)
  end

  def ensure_normalized_content(document, result)
    return if document.cleaned_content.present?

    snippet = result[:snippet].to_s.strip.gsub(/\s+/, ' ')
    if snippet.present?
      updates = {
        cleaned_content: snippet,
        content_chunks: [snippet]
      }
      if document.content.blank?
        updates[:content] = "Title: #{document.title}\nSnippet: #{snippet}"
      end
      document.update!(updates)
      document.generate_embedding!
    elsif document.content.present?
      cleaned = document.content.to_s.strip.gsub(/\s+/, ' ')
      document.update!(
        cleaned_content: cleaned,
        content_chunks: cleaned.present? ? [cleaned] : []
      )
      document.generate_embedding!
    end
  rescue => e
    Rails.logger.warn "[SearchProcessingJob] ensure_normalized_content skipped for #{document.url}: #{e.message}"
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
    SearchesController.broadcast_status_update(@search.id)
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
