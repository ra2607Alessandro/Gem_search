class EmbeddingGenerationJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 30.seconds, attempts: 2

  def perform(document_id)
    Rails.logger.info "[EmbeddingGenerationJob] Starting for document_id: #{document_id}"
    
    @document = Document.find(document_id)
    Rails.logger.info "[EmbeddingGenerationJob] Found document: #{@document.id}, URL: #{@document.url}"
    
    return if @document.embedding.present?
    return unless @document.content_available?
    
    Rails.logger.info "[EmbeddingGenerationJob] Generating embedding for document #{document_id}"
    
    service = Ai::EmbeddingService.new(@document.cleaned_content)
    embedding = service.call
    
    if embedding.present? && embedding.is_a?(Array) && embedding.length == 1536
      @document.update!(embedding: embedding)
      Rails.logger.info "[EmbeddingGenerationJob] Successfully stored embedding"
    else
      Rails.logger.warn "[EmbeddingGenerationJob] Invalid embedding generated"
    end
    
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[EmbeddingGenerationJob] Document not found: #{document_id}"
    raise
  rescue StandardError => e
    Rails.logger.error "[EmbeddingGenerationJob] Failed: #{e.class.name} - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    raise # Re-raise for retry
  end
end