class Scraping::ScrapingCompletionService
  def self.check(search_id)
    search = Search.find_by(id: search_id)
    return unless search

    # Check if all documents have been processed (have scraped_at timestamp)
    total_documents = search.documents.count
    scraped_documents = search.documents.where.not(scraped_at: nil).count
    
    Rails.logger.info "Search #{search_id}: #{scraped_documents}/#{total_documents} documents scraped"

    if total_documents > 0 && scraped_documents == total_documents
      # All documents have been processed
      Rails.logger.info "All documents scraped for search #{search_id}, triggering AI response generation"
      
      if search.scraping?
        # Check if we have at least some content to work with
        documents_with_content = search.documents.where.not(content: [nil, '']).count
        
        Rails.logger.info "Documents with content: #{documents_with_content}"
        search.documents.each do |doc|
          Rails.logger.info "Document #{doc.id} - URL: #{doc.url}, Content length: #{doc.content&.length || 0}"
        end
        
        if documents_with_content > 0
          Rails.logger.info "Found #{documents_with_content} documents with content, proceeding with AI generation"
          search.update!(status: :processing)
          AiResponseGenerationJob.perform_later(search_id)
        else
          Rails.logger.warn "All documents scraped but no content found for search #{search_id}"
          search.update!(status: :failed, error_message: "No content could be extracted from any sources")
        end
      else
        Rails.logger.warn "Scraping complete for search #{search_id}, but status is '#{search.status}'"
      end
    else
      unscraped_ids = search.documents.where(scraped_at: nil).pluck(:id)
      Rails.logger.info "Search #{search_id} has #{total_documents - scraped_documents} documents pending: #{unscraped_ids.join(', ')}"
    end
  end
end