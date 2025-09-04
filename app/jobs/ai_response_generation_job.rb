class AiResponseGenerationJob < ApplicationJob
  queue_as :default

  def perform(search_id)
    search = Search.find(search_id)

    Rails.logger.info "Starting AI response generation for search #{search_id}"
    Rails.logger.info "Search query: #{search.query}"
    Rails.logger.info "Number of documents: #{search.documents.count}"

    begin
      # Generate the AI response
      response_service = Ai::ResponseGenerationService.new(search)
      ai_response = response_service.generate_response

      Rails.logger.info "AI Response received: #{ai_response.inspect}"

      if ai_response.present? && ai_response.is_a?(Hash)
        # Store the AI response (you might want to add an ai_response field to Search model)
        # For now, we'll just log success and broadcast the update
        search.update!(
          ai_response: ai_response[:response],
          follow_up_questions: ai_response[:follow_up_questions],
          status: :completed
        )


     Rails.logger.info "Successfully saved AI response for search #{search_id}"
     SearchesController.broadcast_ai_response_ready(search.id)
      else
        Rails.logger.warn "Invalid AI response format: #{ai_response.class}"
      end

    rescue => e
      Rails.logger.error "AI response generation failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      search.update!(status: :failed)
    end
  end
