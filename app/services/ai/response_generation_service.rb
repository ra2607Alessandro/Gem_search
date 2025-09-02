class Ai::ResponseGenerationService
  MAX_TOKENS = 4000
  MODEL = 'gpt-4-turbo-preview'

  def initialize(search)
    @search = search
  end

  def generate_response
    return nil unless valid_search?

    begin
      Rails.logger.info "Generating AI response for search #{@search.id}"

      # Prepare context for the AI
      context = prepare_context
      return nil unless context[:sources].present?

      # Generate response using OpenAI
      response = call_openai_api(context)
      return nil unless response

      # Process and format the response
      processed_response = process_response(response, context[:sources])

      # Create citations for the response
      create_citations(processed_response[:citations_data])

      Rails.logger.info "Successfully generated AI response for search #{@search.id}"

      processed_response[:response]

    rescue StandardError => e
      Rails.logger.error "AI response generation failed for search #{@search.id}: #{e.message}"
      nil
    end
  end

  private

  attr_reader :search

  def valid_search?
    search.present? && search.completed? && search.search_results.any?
  end

  def prepare_context
    # Get top search results with content
    top_results = search.search_results
                        .includes(:document)
                        .ordered_by_relevance
                        .limit(8) # Limit to avoid token overflow

    # Prepare sources with numbered references
    sources = []
    top_results.each_with_index do |result, index|
      next unless result.document&.content.present?

      source = {
        number: index + 1,
        title: result.document.title,
        url: result.document.url,
        content: truncate_content(result.document.content, 1000), # Limit content per source
        search_result: result
      }
      sources << source
    end

    {
      query: search.query,
      goal: search.goal.presence,
      rules: search.rules.presence,
      sources: sources,
      total_sources: sources.length
    }
  end

  def truncate_content(content, max_length)
    return content if content.length <= max_length

    # Try to truncate at sentence boundary
    truncated = content[0...max_length]
    last_sentence_end = truncated.rindex(/[.!?]/)

    if last_sentence_end && last_sentence_end > max_length * 0.8
      truncated[0..last_sentence_end]
    else
      truncated + "..."
    end
  end

  def call_openai_api(context)
    client = OpenAI::Client.new

    messages = build_messages(context)

    response = client.chat(
      parameters: {
        model: MODEL,
        messages: messages,
        max_tokens: MAX_TOKENS,
        temperature: 0.3, # Lower temperature for more factual responses
        presence_penalty: 0.1,
        frequency_penalty: 0.1
      }
    )

    if response.success?
      response.dig('choices', 0, 'message', 'content')
    else
      Rails.logger.error "OpenAI API error: #{response.dig('error', 'message')}"
      nil
    end

  rescue OpenAI::Error => e
    Rails.logger.error "OpenAI client error: #{e.message}"
    nil
  end

  def build_messages(context)
    system_prompt = build_system_prompt
    user_prompt = build_user_prompt(context)

    [
      { role: 'system', content: system_prompt },
      { role: 'user', content: user_prompt }
    ]
  end

  def build_system_prompt
    <<~SYSTEM_PROMPT
    You are a knowledgeable research assistant that provides accurate, well-cited answers based on web search results.

    CRITICAL RULES:
    1. ONLY use information from the provided sources - never make up facts or use external knowledge
    2. ALWAYS cite your sources using [1], [2], etc. format for every factual claim
    3. Be comprehensive but concise - cover the main points without unnecessary details
    4. If sources conflict, note the disagreement and cite both
    5. If information is insufficient, clearly state what you cannot answer
    6. Maintain neutrality and avoid bias

    RESPONSE STRUCTURE:
    - Start with a clear, direct answer to the query
    - Provide supporting evidence with citations
    - End with 3 follow-up questions that could help the user explore further

    CITATION FORMAT:
    - Use [1], [2], etc. for inline citations
    - Each number corresponds to a source in the provided list
    - Cite specific claims, not general statements

    FOLLOW-UP QUESTIONS:
    - Ask 3 contextual questions that build on the current topic
    - Questions should be answerable with web searches
    - Focus on practical next steps or deeper exploration
    SYSTEM_PROMPT
  end

  def build_user_prompt(context)
    prompt_parts = []

    # Query and context
    prompt_parts << "QUERY: #{context[:query]}"
    prompt_parts << "GOAL: #{context[:goal]}" if context[:goal]
    prompt_parts << "RULES: #{context[:rules]}" if context[:rules]

    # Sources
    prompt_parts << "\nSOURCES:"
    context[:sources].each do |source|
      prompt_parts << "[#{source[:number]}] #{source[:title]}"
      prompt_parts << "URL: #{source[:url]}"
      prompt_parts << "Content: #{source[:content]}"
      prompt_parts << ""
    end

    prompt_parts.join("\n")
  end

  def process_response(raw_response, sources)
    return nil unless raw_response.present?

    # Extract citations from the response
    citations_data = extract_citations(raw_response, sources)

    # Format the response for display
    formatted_response = format_response(raw_response)

    # Extract follow-up questions
    follow_up_questions = extract_follow_up_questions(raw_response)

    {
      response: formatted_response,
      citations_data: citations_data,
      follow_up_questions: follow_up_questions
    }
  end

  def extract_citations(response, sources)
    citations = []

    # Find all citation patterns like [1], [2], etc.
    citation_pattern = /\[(\d+)\]/i
    response.scan(citation_pattern) do |match|
      source_number = match.first.to_i
      source = sources.find { |s| s[:number] == source_number }

      if source
        citations << {
          source_url: source[:url],
          snippet: extract_citation_snippet(response, source_number),
          search_result: source[:search_result]
        }
      end
    end

    citations.uniq { |c| c[:source_url] }
  end

  def extract_citation_snippet(response, source_number)
    # Find the sentence containing the citation
    pattern = /([^.!?]*\[#{source_number}\][^.!?]*[.!?])/
    match = response.match(pattern)

    if match
      match[1].strip
    else
      "Citation #{source_number}"
    end
  end

  def format_response(response)
    # Clean up any formatting issues
    response.strip
  end

  def extract_follow_up_questions(response)
    # Try to extract follow-up questions from the end of the response
    lines = response.split("\n")
    questions = []

    # Look for lines that start with numbers or bullets that might be questions
    lines.each do |line|
      line = line.strip
      next if line.empty?

      # Check if it looks like a question
      if line.match?(/^\d+\.|\*\s|•\s/) && line.match?(/\?$/)
        questions << line.sub(/^\d+\.\s*|\*\s|•\s/, '').strip
      end
    end

    # If we found questions, return them; otherwise, generate generic ones
    questions.any? ? questions.first(3) : generate_generic_questions
  end

  def generate_generic_questions
    [
      "What specific aspects of this topic would you like to explore further?",
      "Are there particular sources or viewpoints you'd like me to examine?",
      "What additional context or examples would help clarify this topic?"
    ]
  end

  def create_citations(citations_data)
    return if citations_data.empty?

    citations_data.each do |citation_data|
      Citation.find_or_create_by!(
        search_result: citation_data[:search_result],
        source_url: citation_data[:source_url]
      ) do |citation|
        citation.snippet = citation_data[:snippet]
      end
    end

    Rails.logger.info "Created #{citations_data.length} citations for search #{search.id}"
  end
end
