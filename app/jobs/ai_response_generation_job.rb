class AiResponseGenerationJob < ApplicationJob
  queue_as :default

  def perform(search_id)
    search = Search.find(search_id)

    Rails.logger.info "Starting AI response generation for search #{search_id}"

    begin
      # Generate the AI response
      response_service = Ai::ResponseGenerationService.new(search)
      ai_response = response_service.generate_response

      if ai_response.present?
        # Store the AI response (you might want to add an ai_response field to Search model)
        # For now, we'll just log success and broadcast the update
        search.update!(
        ai_response: ai_response[:answer],
        follow_up_questions: ai_response[:follow_ups],
        status: :completed )

     SearchesController.broadcast_ai_response_ready(search.id)
      else
        Rails.logger.warn "Failed to generate AI response for search #{search_id}"
      end

    rescue ActiveRecord::RecordNotFound
      Rails.logger.error "Search #{search_id} not found for AI response generation"
    rescue StandardError => e
      Rails.logger.error "AI response generation job failed for search #{search_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Don't re-raise the error as this is not critical for the search functionality
    end
  end
end
