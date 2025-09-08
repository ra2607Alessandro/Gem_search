class Scraping::ScrapingCompletionService
  attr_reader :search

  def self.check(search_id)
    service = new(search_id)
    service.check_and_process

    if service.search && service.search.scraping? &&
       service.search.documents.with_content.count >= Ai::ResponseGenerationService::MIN_SOURCES_REQUIRED
      Rails.logger.warn "[ScrapingCompletionService] Search #{service.search.id} met content threshold but remains scraping. Retrying AI generation."
      ActiveSupport::Notifications.instrument("scraping.ai_response_manual_retry", search_id: service.search.id) do
        AiResponseGenerationJob.perform_later(service.search.id)
      end
    end
  end

  def initialize(search_id)
    @search = Search.find_by(id: search_id)
  end

  def check_and_process
    return unless @search

    # Calculate counts first (avoid NameError)
    scraped_documents = @search.documents.where.not(scraped_at: nil).count
    total_documents   = @search.expected_documents_count || @search.documents.count
    documents_with_content = @search.documents.with_content.count

    Rails.logger.info "[ScrapingCompletionService] Search #{@search.id}: " \
                      "#{scraped_documents}/#{total_documents} scraped, " \
                      "#{documents_with_content} with content."

    # Stop if processing already triggered
    return if @search.completed? || @search.failed? || @search.processing? || @search.retryable?

    if documents_with_content >= Ai::ResponseGenerationService::MIN_SOURCES_REQUIRED
      trigger_ai_generation
    elsif all_documents_processed?(total_documents, scraped_documents)
      handle_completion(documents_with_content)
    elsif process_stalled?
      Rails.logger.warn "[ScrapingCompletionService] Search #{@search.id} appears stalled. Forcing completion."
      handle_completion(documents_with_content)
    else
      log_pending_documents
    end
  end

  private

  def all_documents_processed?(total, scraped)
    total.to_i > 0 && scraped >= total.to_i
  end

  def process_stalled?
    # If it's been over 5 minutes and we're not done, force it.
    @search.created_at < 5.minutes.ago
  end

  def handle_completion(documents_with_content)
    # If no documents have content but we have search results,
    # try to generate response from snippets
    if documents_with_content == 0 && @search.search_results.any?
      Rails.logger.warn "[ScrapingCompletionService] No primary content scraped for search #{@search.id}. Falling back to snippets."
      trigger_ai_generation_with_snippets
    elsif documents_with_content >= Ai::ResponseGenerationService::MIN_SOURCES_REQUIRED
      trigger_ai_generation
    else
      mark_as_failed_insufficient_content(documents_with_content)
    end
  end

  def trigger_ai_generation
    Rails.logger.info "[ScrapingCompletionService] Triggering AI response generation for search #{@search.id}"

    # Use a new status to prevent re-triggering and show progress
    @search.update!(status: :processing)
    ActiveSupport::Notifications.instrument("scraping.ai_response_enqueued", search_id: @search.id) do
      AiResponseGenerationJob.perform_later(@search.id)
    end
  end

  def trigger_ai_generation_with_snippets
    # This can be a fallback, but let's prioritize the main flow.
    # For now, we'll let the main handle_completion logic decide.
    Rails.logger.info "[ScrapingCompletionService] Attempting to use snippets for search #{@search.id}"
    @search.search_results.each do |result|
      doc = result.document
      if doc.content.blank? && result.snippet.present?
        doc.update!(content: "Title: #{doc.title}\nSnippet: #{result.snippet}")
      end
    end
    trigger_ai_generation # Re-use the main trigger
  end

  def mark_as_failed_insufficient_content(content_count)
    error_msg = "Scraping complete, but insufficient content was gathered. " \
                "Found content in #{content_count} source(s), " \
                "but require at least #{Ai::ResponseGenerationService::MIN_SOURCES_REQUIRED}."

    Rails.logger.warn "[ScrapingCompletionService] Search #{@search.id}: #{error_msg}"

    @search.update!(
      status: :failed,
      error_message: error_msg
    )
    # Broadcast final failure state
    SearchesController.broadcast_status_update(@search.id)
  end

  def log_pending_documents
    unscraped = @search.documents.where(scraped_at: nil).pluck(:url)

    if unscraped.any?
      Rails.logger.info "[ScrapingCompletionService] Pending scrapes: #{unscraped.join(', ')}"
    end
  end
end

