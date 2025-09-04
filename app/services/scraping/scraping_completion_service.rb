class Scraping::ScrapingCompletionService
  def self.check(search_id)
    search = Search.find_by(id: search_id)
    return unless search

    # Check if all documents have been scraped (have content)
    unscraped_documents = search.documents.where(content: nil)
    unscraped_count = unscraped_documents.count

    if unscraped_count.zero?
      # All documents have been scraped, trigger AI response generation
      Rails.logger.info "All documents scraped for search #{search_id}, triggering AI response generation"
      if search.scraping?
        AiResponseGenerationJob.perform_later(search_id)
      else
         Rails.logger.warn "Scraping complete for search #{search_id}, but status is '#{search.status}'. AI response will not be triggered."
        end
      else
        document_ids = unscraped_documents.pluck(:id)
            Rails.logger.info "Search #{search_id} still has #{unscraped_count} documents to scrape. Waiting for document IDs: #{document_ids.join(', ')}"

          end
      end
  end
