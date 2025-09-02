class Ai::EmbeddingService
  require 'tiktoken_ruby'

  MAX_TOKENS_PER_CHUNK = 8191 # OpenAI ada-002 limit
  OVERLAP_TOKENS = 100 # Tokens to overlap between chunks
  MAX_RETRIES = 3
  BASE_DELAY = 1.0 # seconds

  def initialize(text)
    @text = text&.strip || ''
    @encoding = Tiktoken.encoding_for_model('text-embedding-ada-002')
  end

  def call
    return [] if text.blank?

    Rails.logger.info "Generating embeddings for text (#{count_tokens(text)} tokens)"

    chunks = smart_chunk_text
    embeddings = []

    if chunks.length == 1
      # Single chunk - direct processing
      embedding = generate_single_embedding(chunks.first)
      return embedding || []
    else
      # Multiple chunks - process each and average
      chunk_embeddings = []

      chunks.each do |chunk|
        embedding = generate_single_embedding(chunk)
        chunk_embeddings << embedding if embedding
      end

      return [] if chunk_embeddings.empty?

      # Average the embeddings
      average_embeddings(chunk_embeddings)
    end
  end

  private

  attr_reader :text, :encoding

  def smart_chunk_text
    return [text] if count_tokens(text) <= MAX_TOKENS_PER_CHUNK

    chunks = []
    sentences = split_into_sentences(text)
    current_chunk = ''

    sentences.each do |sentence|
      potential_chunk = current_chunk.empty? ? sentence : "#{current_chunk} #{sentence}"

      if count_tokens(potential_chunk) > MAX_TOKENS_PER_CHUNK
        if current_chunk.present?
          chunks << current_chunk
          current_chunk = sentence
        else
          # Single sentence is too long, force split
          chunks.concat(force_split_sentence(sentence))
          current_chunk = ''
        end
      else
        current_chunk = potential_chunk
      end
    end

    chunks << current_chunk if current_chunk.present?

    # Add overlap between chunks for better context
    add_overlap_to_chunks(chunks)
  end

  def split_into_sentences(text)
    # Split on sentence endings while preserving abbreviations
    text.split(/(?<=[.!?])\s+/).map(&:strip)
  end

  def force_split_sentence(sentence)
    # If a sentence is too long, split by words
    words = sentence.split
    chunks = []
    current_chunk = ''

    words.each do |word|
      potential_chunk = current_chunk.empty? ? word : "#{current_chunk} #{word}"

      if count_tokens(potential_chunk) > MAX_TOKENS_PER_CHUNK
        chunks << current_chunk if current_chunk.present?
        current_chunk = word
      else
        current_chunk = potential_chunk
      end
    end

    chunks << current_chunk if current_chunk.present?
    chunks
  end

  def add_overlap_to_chunks(chunks)
    return chunks if chunks.length <= 1

    overlapped_chunks = [chunks.first]

    chunks[1..-1].each do |chunk|
      previous_chunk = chunks[chunks.index(chunk) - 1]

      # Get last OVERLAP_TOKENS tokens from previous chunk
      overlap_text = extract_overlap_text(previous_chunk)

      # Prepend overlap to current chunk if it fits
      if overlap_text.present? && count_tokens("#{overlap_text} #{chunk}") <= MAX_TOKENS_PER_CHUNK
        overlapped_chunks << "#{overlap_text} #{chunk}"
      else
        overlapped_chunks << chunk
      end
    end

    overlapped_chunks
  end

  def extract_overlap_text(text)
    tokens = encoding.encode(text)
    return '' if tokens.length <= OVERLAP_TOKENS

    overlap_tokens = tokens.last(OVERLAP_TOKENS)
    encoding.decode(overlap_tokens)
  end

  def count_tokens(text)
    return 0 if text.blank?
    encoding.encode(text).length
  rescue StandardError => e
    Rails.logger.warn "Token counting failed: #{e.message}"
    0
  end

  def generate_single_embedding(text_chunk)
    return nil if text_chunk.blank?

    attempt = 0

    begin
      attempt += 1

      client = OpenAI::Client.new
      response = client.embeddings(
        parameters: {
          model: 'text-embedding-ada-002',
          input: text_chunk
        }
      )

      if response.success?
        embedding = response.dig('data', 0, 'embedding')
        validate_embedding(embedding)
      else
        handle_api_error(response, attempt)
      end

    rescue OpenAI::Error => e
      handle_openai_error(e, attempt)
    rescue StandardError => e
      Rails.logger.error "Embedding generation failed: #{e.message}"
      retry_with_backoff(attempt)
    end
  end

  def validate_embedding(embedding)
    return nil unless embedding.is_a?(Array)
    return nil unless embedding.length == 1536 # OpenAI ada-002 dimensions

    # Check all values are numbers
    return nil unless embedding.all? { |v| v.is_a?(Numeric) }

    embedding
  end

  def handle_api_error(response, attempt)
    error = response.dig('error', 'message') || 'Unknown API error'
    Rails.logger.error "OpenAI API error (attempt #{attempt}): #{error}"

    if response.dig('error', 'type') == 'insufficient_quota'
      Rails.logger.error "OpenAI quota exceeded"
      return nil
    end

    retry_with_backoff(attempt)
  end

  def handle_openai_error(error, attempt)
    Rails.logger.error "OpenAI client error (attempt #{attempt}): #{error.message}"

    case error
    when OpenAI::RateLimitError
      retry_with_backoff(attempt, delay_multiplier: 2.0)
    when OpenAI::TimeoutError
      retry_with_backoff(attempt, delay_multiplier: 1.5)
    when OpenAI::ServerError
      retry_with_backoff(attempt, delay_multiplier: 2.0) if attempt < MAX_RETRIES
    else
      retry_with_backoff(attempt)
    end
  end

  def retry_with_backoff(attempt, delay_multiplier: 1.0)
    return nil if attempt >= MAX_RETRIES

    delay = BASE_DELAY * (delay_multiplier ** attempt) * (1 + rand * 0.1) # Add jitter
    Rails.logger.info "Retrying embedding generation in #{delay.round(2)} seconds (attempt #{attempt + 1}/#{MAX_RETRIES})"

    sleep delay
    nil # Signal to retry
  end

  def average_embeddings(embeddings)
    return [] if embeddings.empty?

    dimension_count = embeddings.first.length
    averaged = Array.new(dimension_count, 0.0)

    embeddings.each do |embedding|
      next unless embedding.length == dimension_count

      embedding.each_with_index do |value, index|
        averaged[index] += value
      end
    end

    # Divide by count to get average
    averaged.map { |sum| sum / embeddings.length }
  end
end