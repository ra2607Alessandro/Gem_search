class AiResponseGenerationJob < ApplicationJob
  queue_as :default

  # Retry on network errors or other transient issues
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(search_id)
    search = Search.find_by(id: search_id)
    return unless search
  
    Rails.logger.info "[AiResponseGenerationJob] Starting AI generation for search #{search.id}"
    
    # Add validation
    unless $openai_client
      Rails.logger.error "[AiResponseGenerationJob] OpenAI client not initialized!"
      search.update!(status: :failed, error_message: "OpenAI client not configured")
      return
    end
  
    search.update!(status: :processing)
  
    service = Ai::ResponseGenerationService.new(search)
    response_data = service.generate_response

    if response_data&.dig(:response).present?
      search.update!(
        ai_response: response_data[:response],
        follow_up_questions: response_data[:follow_up_questions],
        status: :completed,
        completed_at: Time.current
      )
      
      # Broadcast the final response to the UI
      SearchesController.broadcast_ai_response_ready(search.id)
      Rails.logger.info "[AiResponseGenerationJob] Successfully completed AI generation for search #{search.id}"
    else
      handle_failure(search, "AI response generation failed to produce content.")
    end
 

rescue StandardError => e
  Rails.logger.error "[AiResponseGenerationJob] Failed with error: #{e.class.name}: #{e.message}"
  Rails.logger.error "Full backtrace:\n#{e.backtrace.join("\n")}"  // Log full backtrace for debugging
  handle_failure(search, "AI job error: #{e.message} - Check logs for details")
  raise
end

// In handle_failure, add broadcast for better UI feedback
def handle_failure(search, error_message)
  Rails.logger.error "[AiResponseGenerationJob] Failed for search #{search.id}: #{error_message}"
  search.update!(
    status: :failed,
    error_message: error_message
  )
  # Broadcast detailed error to UI
  SearchesController.broadcast_status_update(search.id, error: error_message)  // Assume broadcast method supports optional error param; add if needed
end


  private

  def handle_failure(search, error_message)
    Rails.logger.error "[AiResponseGenerationJob] Failed for search #{search.id}: #{error_message}"
    search.update!(
      status: :failed,
      error_message: error_message
    )
    # Also broadcast a status update so the UI reflects the failure
    SearchesController.broadcast_status_update(search.id)
  end
end