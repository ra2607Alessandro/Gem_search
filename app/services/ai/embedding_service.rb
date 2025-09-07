class Ai::EmbeddingService
  require 'tiktoken_ruby'

  MODEL = 'text-embedding-3-small'
  DIMENSIONS = 1536
  MAX_TOKENS = 8191
  CHUNK_SIZE = 6000  # Conservative chunk size
  OVERLAP_SIZE = 200

  class EmbeddingError < StandardError; end

  def initialize(text)
    @text = text&.strip || ''
    @encoding = Tiktoken.encoding_for_model('cl100k_base')
  end

  def call
    return nil if @text.blank?

     Rails.logger.info "[EmbeddingService] Generating embedding for #{@text.length} chars"

     if token_count(@text) <= MAX_TOKENS
      generate_single_embedding(@text)
    else
      generate_chunked_embedding
    end
  rescue StandardError => e
    Rails.logger.error "[EmbeddingService] Failed: #{e.message}"
    nil
  end
  
  private
  
  def token_count(text)
    @encoding.encode(text).length
  rescue
    # Fallback estimation
    (text.length / 4.0).ceil
  end
  
  def generate_single_embedding(text)
    validate_client!
    
    response = openai_client.embeddings(
      parameters: {
        model: MODEL,
        input: text,
        dimensions: DIMENSIONS
      }
    )
    
    embedding = response.dig('data', 0, 'embedding')
    validate_embedding!(embedding)
    
    embedding
  rescue => e
    handle_api_error(e)
    nil
  end
  
  def generate_chunked_embedding
    chunks = create_smart_chunks
    embeddings = []
    
    chunks.each_with_index do |chunk, index|
      Rails.logger.info "[EmbeddingService] Processing chunk #{index + 1}/#{chunks.length}"
      
      embedding = generate_single_embedding(chunk)
      embeddings << embedding if embedding
      
      # Rate limiting
      sleep(0.5) if chunks.length > 1
    end
    
    return nil if embeddings.empty?
    
    # Average embeddings
    average_embeddings(embeddings)
  end
  
  def create_smart_chunks
    chunks = []
    sentences = @text.split(/(?<=[.!?])\s+/)
    current_chunk = ""
    current_tokens = 0
    
    sentences.each do |sentence|
      sentence_tokens = token_count(sentence)
      
      if current_tokens + sentence_tokens > CHUNK_SIZE
        chunks << current_chunk.strip if current_chunk.present?
        current_chunk = sentence
        current_tokens = sentence_tokens
      else
        current_chunk += " " + sentence
        current_tokens += sentence_tokens
      end
    end
    
    chunks << current_chunk.strip if current_chunk.present?
    chunks
  end
  
  def average_embeddings(embeddings)
    return nil if embeddings.empty?
    
    # Initialize array with zeros
    averaged = Array.new(DIMENSIONS, 0.0)
    
    # Sum all embeddings
    embeddings.each do |embedding|
      embedding.each_with_index do |value, index|
        averaged[index] += value
      end
    end
    
    # Divide by count
    averaged.map { |sum| sum / embeddings.length }
  end
  
  def validate_client!
    if openai_client.nil?
      raise EmbeddingError, "OpenAI client not initialized"
    end
  end
  
  def validate_embedding!(embedding)
    unless embedding.is_a?(Array) && embedding.length == DIMENSIONS
      raise EmbeddingError, "Invalid embedding format"
    end
  end

  def openai_client
    Rails.application.config.x.openai_client
  end
  
  def handle_api_error(error)
    case error
    when OpenAI::RateLimitError
      Rails.logger.error "[EmbeddingService] Rate limit exceeded"
    when OpenAI::AuthenticationError
      Rails.logger.error "[EmbeddingService] Authentication failed"
    else
      Rails.logger.error "[EmbeddingService] API error: #{error.message}"
    end
  end
end
