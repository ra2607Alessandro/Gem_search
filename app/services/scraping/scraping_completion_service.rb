class Scraping::ScrapingCompletionService
  def self.check(search_id)
    new(search_id).check_and_process
  end

  def initialize(search_id)
    @search = Search.find_by(id: search_id)
  end

  def check_and_process
    return unless @search
    return unless @search.scraping?

    # Check if all documents have been processed (have scraped_at timestamp)
    total_documents = @search.documents.count
    scraped_documents = @search.documents.where.not(scraped_at: nil).count
    documents_with_content = @search.documents.with_content.count
    
    Rails.logger.info "[ScrapingCompletionService] Search #{@search.id}: " \
                     "#{scraped_documents}/#{total_documents} scraped, " \
                     "#{documents_with_content} with content"
    
    # Check if all documents have been processed
    if all_documents_processed?(total_documents, scraped_documents)
      handle_completion(documents_with_content)
    else
      log_pending_documents
    end
  end
  
  private
  
  def all_documents_processed?(total, scraped)
    total > 0 && scraped >= total
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
    
    @search.update!(status: :processing)
    AiResponseGenerationJob.perform_later(@search.id)
  end

  def trigger_ai_generation_with_snippets
    # Create minimal content from search result snippets
    @search.search_results.each do |result|
      doc = result.document
      if doc.content.blank? && result.snippet.present?
        doc.update!(content: "Title: #{doc.title}\nSnippet: #{result.snippet}")
      end
    end
    
    @search.update!(status: :processing)
    AiResponseGenerationJob.perform_later(@search.id)
  end
  
  def mark_as_failed_insufficient_content(content_count)
    error_msg = "Insufficient content: only #{content_count} documents have content " \
                "(minimum #{Ai::ResponseGenerationService::MIN_SOURCES_REQUIRED} required)"
    
    Rails.logger.warn "[ScrapingCompletionService] #{error_msg}"
    
    @search.update!(
      status: :failed,
      error_message: error_msg
    )
  end
  
  def log_pending_documents
    unscraped = @search.documents.where(scraped_at: nil).pluck(:url)
    
    if unscraped.any?
      Rails.logger.info "[ScrapingCompletionService] Pending scrapes: #{unscraped.join(', ')}"
    end
  end
end

