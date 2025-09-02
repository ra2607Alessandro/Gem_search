class WebScrapingJob < ApplicationJob
  queue_as :default

  def perform(document_id, search_id, position, search_result_data)
    @document_id = document_id
    @search_id = search_id
    @position = position
    @search_result_data = search_result_data

    begin
      # Load records
      document = Document.find(document_id)
      search = Search.find(search_id)

      Rails.logger.info "Starting web scraping for document #{document_id}: #{document.url}"

      # Step 1: Scrape content
      scraped_data = scrape_content(document.url)
      return unless scraped_data[:success]

      # Step 2: Update document with scraped content
      update_document_with_content(document, scraped_data)

      # Step 3: Generate embeddings
      generate_and_store_embeddings(document)

      # Step 4: Update search result with improved relevance score
      update_search_result_relevance(search, document, position, scraped_data)

      Rails.logger.info "Completed web scraping for document #{document_id}"

    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "Record not found during scraping: #{e.message}"
    rescue StandardError => e
      Rails.logger.error "Web scraping failed for document #{document_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Mark document as having scraping issues
      begin
        Document.find(document_id).update(scraped_at: Time.current)
      rescue ActiveRecord::RecordNotFound
        # Document was deleted, nothing to do
      end

      raise e
    end
  end

  private

  def scrape_content(url)
    Rails.logger.info "Scraping content from: #{url}"

    scraper = Scraping::ContentScraperService.new(url)
    result = scraper.call

    if result[:success]
      Rails.logger.info "Successfully scraped content from #{url} (#{result[:cleaned_content].length} characters)"
    else
      Rails.logger.warn "Failed to scrape content from #{url}: #{result[:error]}"
    end

    result
  end

  def update_document_with_content(document, scraped_data)
    document.update!(
      title: scraped_data[:title].presence || document.title,
      content: scraped_data[:content],
      scraped_at: Time.current
    )

    Rails.logger.info "Updated document #{document.id} with scraped content"
  end

  def generate_and_store_embeddings(document)
    return unless document.content.present?

    Rails.logger.info "Generating embeddings for document #{document.id}"

    # Generate embeddings for the cleaned content
    embedding_service = Ai::EmbeddingService.new(document.content)
    embedding_vector = embedding_service.call

    if embedding_vector.present? && embedding_vector.length == 1536
      document.update!(embedding: embedding_vector)
      Rails.logger.info "Stored embeddings for document #{document.id}"
    else
      Rails.logger.warn "Failed to generate valid embeddings for document #{document.id}"
    end
  end

  def update_search_result_relevance(search, document, position, scraped_data)
    search_result = SearchResult.find_by(search: search, document: document)

    if search_result
      # Recalculate relevance score with additional factors
      new_score = calculate_enhanced_relevance_score(
        position,
        scraped_data[:cleaned_content]&.length || 0,
        document.embedding.present?
      )

      search_result.update!(relevance_score: new_score)
      Rails.logger.info "Updated relevance score for search result #{search_result.id} to #{new_score}"
    else
      Rails.logger.warn "Search result not found for search #{search.id} and document #{document.id}"
    end
  end

  def calculate_enhanced_relevance_score(position, content_length, has_embedding)
    # Base score from position (0.0 to 1.0)
    position_score = 1.0 - (position.to_f / 10.0) # Assuming max 10 results

    # Content length factor (0.0 to 0.3)
    # Reward longer, more substantial content
    length_factor = if content_length > 1000
                      0.3
                    elsif content_length > 500
                      0.2
                    elsif content_length > 200
                      0.1
                    else
                      0.0
                    end

    # Embedding factor (0.0 to 0.2)
    # Reward documents with successful embeddings
    embedding_factor = has_embedding ? 0.2 : 0.0

    # Combine factors
    total_score = position_score + length_factor + embedding_factor

    # Ensure score is between 0.0 and 1.0
    [total_score, 1.0].min.round(4)
  end
end
