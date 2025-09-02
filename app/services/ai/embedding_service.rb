class Ai::EmbeddingService
  def initialize(text)
    @text = text
  end

  def call
    # TODO: Generate embeddings using OpenAI API
    # This will be built by Cursor
    []
  end

  private

  attr_reader :text
end