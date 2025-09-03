class Scraping::ScrapingCompletionService
  def self.check(search_id)
    search = Search.find_by(id: search_id)
    return unless search

    # Check if all documents have been scraped (have content)
    unscraped_count = search.documents.where(content: nil).count

    if unscraped_count.zero?
      # All documents have been scraped, trigger AI response generation
      Rails.logger.info "All documents scraped for search #{search_id}, triggering AI response generation"
      AiResponseGenerationJob.perform_later(search_id)
    else
      Rails.logger.debug "Search #{search_id} still has #{unscraped_count} documents to scrape"
    end
  end
end
