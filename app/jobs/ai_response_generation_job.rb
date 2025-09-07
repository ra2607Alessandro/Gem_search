class AiResponseGenerationJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(search_id)
    search = Search.find_by(id: search_id)
    return unless search

    Rails.logger.info "[AiResponseGenerationJob] Starting AI generation for search #{search.id}"

    unless $openai_client
      Rails.logger.error "[AiResponseGenerationJob] OpenAI client not initialized!"
      search.update!(status: :failed, error_message: "OpenAI client not configured")
      SearchesController.broadcast_status_update(search.id) rescue nil
      return
    end

    search.update!(status: :processing)
    SearchesController.broadcast_status_update(search.id) rescue nil

    data = Ai::ResponseGenerationService.new(search).generate_response

    if data && data[:response].present?
      search.update!(
        ai_response: data[:response],
        follow_up_questions: data[:follow_up_questions],
        status: :completed,
        completed_at: Time.current
      )
      SearchesController.broadcast_ai_response_ready(search.id)
      Rails.logger.info "[AiResponseGenerationJob] Successfully completed AI generation for search #{search.id}"
    elsif data && data[:error]
      handle_failure(search, data[:error])
    else
      handle_failure(search, "AI response generation failed to produce content.")
    end
  rescue => e
    Rails.logger.error "[AiResponseGenerationJob] Failed: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    handle_failure(search, "AI job error: #{e.message}")
    raise
  end

  private

  def handle_failure(search, msg)
    Rails.logger.error "[AiResponseGenerationJob] Failed for search #{search.id}: #{msg}"
    search.update!(status: :failed, error_message: msg)
    SearchesController.broadcast_status_update(search.id) rescue nil
  end
end
