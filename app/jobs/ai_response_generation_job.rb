class AiResponseGenerationJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 10.seconds, attempts: 2

  def perform(search_id)
    @search = Search.find(search_id)

    Rails.logger.info "[AiResponseGenerationJob] Starting for search #{search_id}"
    
    # Validate search state
    unless @search.processing?
      Rails.logger.warn "[AiResponseGenerationJob] Search #{search_id} not in processing state (#{@search.status})"
      return
    end
    
    # Generate response using only truth-grounded content
    response_service = Ai::ResponseGenerationService.new(@search)
    response_data = response_service.generate_response
    
    if response_data.present?
      save_response(response_data)
      broadcast_completion
    else
      handle_generation_failure
    end
    
  rescue Ai::ResponseGenerationService::InsufficientSourcesError => e
    handle_insufficient_sources(e)
  rescue StandardError => e
    handle_job_error(e)
    raise # Re-raise for retry
  end
  
  private
  
  def save_response(response_data)
    @search.update!(
      ai_response: response_data[:response],
      follow_up_questions: response_data[:follow_up_questions],
      status: :completed
    )
    
    Rails.logger.info "[AiResponseGenerationJob] Successfully saved response with " \
                     "#{response_data[:citations]&.length || 0} citations"
  end
  
  def broadcast_completion
    # Trigger real-time update
    SearchesController.broadcast_ai_response_ready(@search.id)
  rescue => e
    Rails.logger.error "[AiResponseGenerationJob] Broadcast failed: #{e.message}"
  end
  
  def handle_generation_failure
    Rails.logger.error "[AiResponseGenerationJob] Response generation returned nil"
    
    @search.update!(
      status: :failed,
      error_message: "Failed to generate AI response"
    )
  end
  
  def handle_insufficient_sources(error)
    Rails.logger.error "[AiResponseGenerationJob] #{error.message}"
    
    @search.update!(
      status: :failed,
      error_message: error.message
    )
  end
  
  def handle_job_error(error)
    Rails.logger.error "[AiResponseGenerationJob] Error: #{error.message}"
    Rails.logger.error "[AiResponseGenerationJob] Available sources: #{@search.documents.with_content.count}"
    Rails.logger.error error.backtrace.first(5).join("\n")
    
    @search.update!(
      status: :failed,
      error_message: "AI response generation error: #{error.message}"
    )
  end
end