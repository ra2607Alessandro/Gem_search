class StaleSearchProcessingJob < ApplicationJob
    queue_as :low
    
    STALE_THRESHOLD = 10.minutes
  
    def perform
      Rails.logger.info 'Running StaleSearchProcessingJob...'
  
      # Find searches stuck in scraping status
      stale_searches = Search.where(status: :scraping)
                            .where('updated_at < ?', STALE_THRESHOLD.ago)
  
      stale_searches.each do |search|
        Rails.logger.warn "Search #{search.id} is stale, checking completion status"
        
        # First, try the normal completion check
        Scraping::ScrapingCompletionService.check(search.id)
        
        # Reload and check if still stuck
        search.reload
        if search.scraping? && search.updated_at < STALE_THRESHOLD.ago
          # Force completion if truly stuck
          Rails.logger.error "Search #{search.id} is still stuck after check, forcing AI generation"
          
          documents_with_content = search.documents.with_content.count
          if documents_with_content > 0
            AiResponseGenerationJob.perform_later(search.id)
          else
            search.update!(status: :failed, error_message: "Search timed out with no content extracted")
            SearchesController.broadcast_status_update(search.id)
          end
        end
      end
    end
  end
