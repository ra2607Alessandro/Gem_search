class SearchProcessingJob < ApplicationJob
  queue_as :default

  def perform(search_id)
    @search_id = search_id

    begin
      # Load and validate search
      search = Search.find(search_id)
      Rails.logger.info "Starting search processing for search #{search_id}: #{search.query}"

      # Update status to scraping
      search.update!(status: :scraping)

      # Step 1: Perform web search
      search_results = perform_web_search(search)
      return if search_results.empty?

      # Step 2: Process and deduplicate documents
      processed_urls = process_documents(search, search_results)

      # Step 3: Create search results with relevance scores
      create_search_results(search, processed_urls, search_results)

      # Step 4: AI response will be generated after all scraping completes
      Rails.logger.info "Completed search processing for search #{search_id}, waiting for scraping to finish"

    rescue ActiveRecord::RecordNotFound
      Rails.logger.error "Search #{search_id} not found"
    rescue StandardError => e
      Rails.logger.error "Search processing failed for search #{search_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Mark search as failed
      begin
        Search.find(search_id).update!(status: :failed)
      rescue ActiveRecord::RecordNotFound
        # Search was deleted, nothing to do
      end

      raise e
    end
  end

  private

  def perform_web_search(search)
    Rails.logger.info "Performing web search for: #{search.query}"

    begin
      web_search_service = Search::WebSearchService.new
      results = web_search_service.search(search.query, num_results: 10)

      if results.empty?
        Rails.logger.warn "No search results found for query: #{search.query}"
        return []
      end

      Rails.logger.info "Found #{results.length} search results"
      results

    rescue StandardError => e
      Rails.logger.error "Web search failed: #{e.message}"
      []
    end
  end

  def process_documents(search, search_results)
    processed_urls = []
    Rails.logger.info "Processing #{search_results.length} documents"

    search_results.each_with_index do |result, position|
      url = result[:url]

      # Skip if URL already processed recently
      next if document_recently_processed?(url)

      # Create or update document record
      document = find_or_initialize_document(url, result)

      # Queue scraping job
      WebScrapingJob.perform_later(
        document.id,
        search.id,
        position,
        result
      )

      processed_urls << { url: url, document: document, position: position, search_result: result }
      Rails.logger.info "Queued scraping for: #{url}"
    end

    processed_urls
  end

  def document_recently_processed?(url)
    # Consider document "recent" if scraped within last 7 days
    recent_threshold = 7.days.ago

    Document.where(url: url)
            .where('scraped_at > ?', recent_threshold)
            .exists?
  end

  def find_or_initialize_document(url, search_result)
    document = Document.find_or_initialize_by(url: url) do |doc|
      doc.title = search_result[:title]
    end

    # Update title if it's better (longer or different)
    if search_result[:title].present? &&
       (document.title.blank? || document.title.length < search_result[:title].length)
      document.title = search_result[:title]
    end

    document.save!
    document
  end

  def create_search_results(search, processed_urls, search_results)
    Rails.logger.info "Creating search results for #{processed_urls.length} documents"

    processed_urls.each do |processed_url|
      document = processed_url[:document]
      position = processed_url[:position]

      # Calculate initial relevance score based on search position
      relevance_score = calculate_relevance_score(position, search_results.length)

      # Create search result record
      search_result = SearchResult.find_or_initialize_by(
        search: search,
        document: document
      )

      search_result.relevance_score = relevance_score
      search_result.save!

      Rails.logger.info "Created search result for document #{document.id} with score #{relevance_score}"
    end
  end

  def calculate_relevance_score(position, total_results)
    # Higher score for earlier positions (0.0 to 1.0)
    # Position 0 = 1.0, last position approaches 0.0
    base_score = 1.0 - (position.to_f / total_results.to_f)

    # Apply a curve to give more weight to top results
    curve_factor = 0.7
    (base_score ** curve_factor).round(4)
  end


end
