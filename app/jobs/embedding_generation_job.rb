class EmbeddingGenerationJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100
  MAX_RETRIES = 3
  RETRY_DELAY = 5.minutes

  def perform(document_ids, attempt = 1)
    @document_ids = Array(document_ids)
    @attempt = attempt

    Rails.logger.info "Starting embedding generation for #{document_ids.length} documents (attempt #{attempt})"

    begin
      # Load documents without embeddings
      documents = load_documents_for_processing

      if documents.empty?
        Rails.logger.info "No documents found that need embedding generation"
        return
      end

      # Process in batches
      documents.each_slice(BATCH_SIZE) do |batch|
        process_batch(batch)
      end

      Rails.logger.info "Completed embedding generation for #{documents.length} documents"

    rescue StandardError => e
      Rails.logger.error "Embedding generation job failed (attempt #{attempt}): #{e.message}"

      # Retry with exponential backoff if we haven't exceeded max retries
      if attempt < MAX_RETRIES
        delay = RETRY_DELAY * (2 ** (attempt - 1)) # Exponential backoff
        Rails.logger.info "Retrying embedding generation in #{delay.inspect}"

        self.class.set(wait: delay).perform_later(document_ids, attempt + 1)
      else
        Rails.logger.error "Max retries exceeded for embedding generation job"
        mark_documents_as_failed(document_ids)
      end

      raise e
    end
  end

  private

  def load_documents_for_processing
    Document.where(id: @document_ids)
            .where(embedding: nil)
            .where.not(content: nil)
            .where.not(content: '')
  end

  def process_batch(batch)
    Rails.logger.info "Processing batch of #{batch.length} documents"

    batch.each do |document|
      generate_embedding_for_document(document)
    end
  end

  def generate_embedding_for_document(document)
    return unless document.content.present?

    Rails.logger.info "Generating embedding for document #{document.id}"

    start_time = Time.current

    begin
      # Generate embedding using the service
      embedding_service = Ai::EmbeddingService.new(document.content)
      embedding_vector = embedding_service.call

      if embedding_vector.present? && embedding_vector.length == 1536
        # Store the embedding
        document.update!(embedding: embedding_vector)

        processing_time = Time.current - start_time
        Rails.logger.info "Successfully generated embedding for document #{document.id} in #{processing_time.round(2)} seconds"
      else
        Rails.logger.warn "Failed to generate valid embedding for document #{document.id}"
        mark_document_as_failed(document)
      end

    rescue StandardError => e
      Rails.logger.error "Failed to generate embedding for document #{document.id}: #{e.message}"
      mark_document_as_failed(document)
    end
  end

  def mark_document_as_failed(document)
    # For now, we'll just log the failure
    # In a production system, you might want to add a failed_at timestamp
    # or a failure_count field to the documents table
    Rails.logger.warn "Marking document #{document.id} as failed for embedding generation"

    # Optional: Update a failed_at timestamp if you add this column
    # document.update!(embedding_failed_at: Time.current)
  end

  def mark_documents_as_failed(document_ids)
    Rails.logger.error "Marking #{document_ids.length} documents as failed due to job failure"

    # Optional: Bulk update failed status
    # Document.where(id: document_ids).update_all(embedding_failed_at: Time.current)
  end

  # Class method for convenience - generate embeddings for specific documents
  def self.generate_for_documents(document_ids)
    perform_later(Array(document_ids))
  end

  # Class method for batch processing - find all documents without embeddings
  def self.generate_missing_embeddings(batch_size = BATCH_SIZE)
    document_ids = Document.where(embedding: nil)
                          .where.not(content: nil)
                          .where.not(content: '')
                          .limit(batch_size * 10) # Get more than we need for batching
                          .pluck(:id)

    if document_ids.empty?
      Rails.logger.info "No documents found that need embedding generation"
      return
    end

    # Process in smaller batches to avoid memory issues
    document_ids.each_slice(batch_size) do |batch_ids|
      perform_later(batch_ids)
    end

    Rails.logger.info "Queued embedding generation for #{document_ids.length} documents in #{(document_ids.length / batch_size.to_f).ceil} batches"
  end
end
