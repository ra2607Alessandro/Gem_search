# frozen_string_literal: true

# This job identifies searches that have been in the 'scraping' state for an
# extended period and triggers the AI response generation with the content
# that has been successfully scraped. This prevents searches from getting
# permanently stuck due to a single failed scrape.
class StaleSearchProcessingJob < ApplicationJob
    queue_as :default
  
    # Time threshold to consider a search "stale"
    STALE_THRESHOLD = 10.minutes
  
    def perform
      Rails.logger.info 'Running StaleSearchProcessingJob to find stuck searches...'
  
      stale_searches = Search.where(status: :scraping)
                             .where('updated_at < ?', STALE_THRESHOLD.ago)
  
      if stale_searches.empty?
        Rails.logger.info 'No stale searches found.'
        return
      end
  
      Rails.logger.info "Found #{stale_searches.count} stale searches. Triggering AI response for them."
  
      stale_searches.each do |search|
        Rails.logger.warn "Search #{search.id} is stale. Forcing AI response generation."
  
        # Set content of unscraped documents to empty string to unblock
        search.documents.where(content: nil).update_all(content: '')
  
        # Trigger the AI response generation
        AiResponseGenerationJob.perform_later(search.id)
      end
    end
  end