require 'timeout'
require "openai"

class Ai::ResponseGenerationService
  MODEL = 'gpt-4o-mini'
  MAX_TOKENS = 2000
  MAX_CONTEXT_LENGTH = 12000
  MIN_SOURCES_REQUIRED = 1
  MAX_RETRIES = 2


  class InsufficientSourcesError < StandardError; end

  def initialize(search)
    @search = search
    @metrics = {}
  end

   def generate_response
    validate_prerequisites!

    Rails.logger.info "[ResponseGenerationService] Starting for search #{@search.id}"

    # Prepare context for the AI
    context = prepare_truth_grounded_context

    # Generate response
    response_data = generate_ai_response(context)
    return response_data if response_data[:error]

    if response_data[:response].blank?
      log_blank_response(response_data)
      response_data = build_fallback_response(context)
    else
      create_citations(response_data[:citations]) if response_data[:citations]&.any?
    end

    Rails.logger.info "[ResponseGenerationService] Completed successfully"

    response_data.except(:messages, :raw_body)

  rescue InsufficientSourcesError => e
    Rails.logger.warn "[ResponseGenerationService] Insufficient sources: #{e.message}"
    raise
  rescue StandardError => e
    Rails.logger.error "[ResponseGenerationService] Failed for search #{@search.id}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    { error: e.message }
  end
  
  private
  
  def validate_prerequisites!
    unless openai_client
      raise "OpenAI client not configured"
    end
    
    available_sources = @search.documents.with_content.count
    if available_sources < MIN_SOURCES_REQUIRED
      raise InsufficientSourcesError, "Only #{available_sources} sources available, need at least #{MIN_SOURCES_REQUIRED}"
    end
  end
  
  def prepare_truth_grounded_context
    # Get documents with content, ordered by relevance
    documents = if @search.query_embedding.present?
      # Use semantic search for better relevance
      docs = Document.semantic_search(@search.query_embedding, limit: 5)
              .joins(:search_results)
              .where(search_results: { search_id: @search.id })

      if docs.blank?
          @search.documents
            .with_content
            .joins(:search_results)
            .order('search_results.relevance_score DESC')
            .limit(5)
      else
        docs
      end
    else
      # Fallback to relevance score ordering
      @search.documents
             .with_content
             .joins(:search_results)
             .order('search_results.relevance_score DESC')
             .limit(5)
    end
    
    # Build context with numbered sources from document chunks
    sources = []
    total_tokens = 0
    # Use in-memory fallback chunks when content_chunks are absent but cleaned_content exists
    doc_chunks_map = {}
    documents.each do |d|
      chunks = d.content_chunks
      if (chunks.nil? || chunks.empty?) && d.cleaned_content.present?
        chunks = [d.cleaned_content.to_s]
      end
      doc_chunks_map[d.id] = chunks || []
    end
    max_chunks = doc_chunks_map.values.map(&:size).max || 0
    break_outer = false

    0.upto(max_chunks - 1) do |chunk_idx|
      documents.each do |doc|
        chunks = doc_chunks_map[doc.id] || []
        chunk = chunks[chunk_idx]
        next unless chunk.present?

        number = sources.length + 1
        source_text = build_source_text(doc, number, chunk)
        source_tokens = estimate_tokens(source_text)

        if total_tokens + source_tokens > MAX_CONTEXT_LENGTH
          break_outer = true
          break
        end

        sources << {
          number: number,
          document: doc,
          text: source_text,
          search_result: @search.search_results.find_by(document: doc)
        }
        total_tokens += source_tokens
      end
      break if break_outer
    end
  
    @metrics[:sources_used] = sources.length
    @metrics[:total_tokens] = total_tokens
  
    { query: @search.query, goal: @search.goal, rules: @search.rules, sources: sources }
  end
  
  def build_source_text(document, number, chunk)
    # Limit content length per source
    max_length = 1000
    content = chunk || ""

    truncated_content = if content.length > max_length
      content[0...max_length].sub(/[^.!?]*$/, '') + "..."
    else
      content
    end

    "[#{number}] #{document.title}\nURL: #{document.url}\nContent: #{truncated_content}\n"
  end
  
 

  def generate_ai_response(context)
    messages = build_messages(context)
    context_info = "search=#{@search.id} model=#{MODEL} tokens=#{@metrics[:total_tokens]}"

    response = nil
    attempts = 0
    timeout_seconds = 60

    begin
      attempts += 1
      Timeout.timeout(timeout_seconds) do
        response = openai_client.chat(
          parameters: {
            model: MODEL,
            messages: messages,
            max_tokens: MAX_TOKENS,
            temperature: 0.3,
            presence_penalty: 0.1,
            frequency_penalty: 0.1
          }
        )
      end
      Rails.logger.debug "[ResponseGenerationService] Raw OpenAI response (#{context_info}): #{response.inspect}"
    rescue Timeout::Error => e
      Rails.logger.error "[ResponseGenerationService] OpenAI timeout (#{context_info}): #{e.message}"
      if attempts <= MAX_RETRIES
        timeout_seconds = 90
        sleep(2 ** attempts)
        retry
      else
        return { error: "OpenAI response timed out after #{timeout_seconds}s" }
      end
    rescue StandardError => e
      Rails.logger.error "[ResponseGenerationService] OpenAI API error (#{context_info}): #{e.message}"
      Rails.logger.error "[ResponseGenerationService] Raw response: #{response.inspect}" if response
      if attempts <= MAX_RETRIES && retryable_openai_error?(e)
        sleep(2 ** attempts)
        retry
      else
        return { error: e.message }
      end
    end

    if response.is_a?(Hash) && response["error"]
      error_msg = response.dig("error", "message") || "OpenAI API error"
      Rails.logger.error "[ResponseGenerationService] OpenAI API returned error (#{context_info}): #{error_msg}"
      return { error: error_msg }
    end

    raw_content = extract_content_from_openai(response)
    parsed = parse_response(raw_content.to_s, context[:sources]) || { response: "", follow_up_questions: [], citations: [] }
    parsed.merge(messages: messages, raw_body: response)
  end


  
  def build_messages(context)
    user_prompt = build_user_prompt(context)
    [
      { role: 'system', content: build_truth_grounded_system_prompt },  # Fix: use correct method name
      { role: 'user', content: user_prompt }
    ]
  end
  
  def build_truth_grounded_system_prompt
    <<~PROMPT
    You are a research assistant that provides accurate, fact-based answers using ONLY information from provided sources.
    
    CRITICAL RULES - NEVER VIOLATE THESE:
    1. ONLY use information explicitly stated in the numbered sources provided
    2. NEVER add information from your training data or general knowledge  
    3. ALWAYS cite sources using [1], [2], etc. for EVERY factual claim
    4. If sources don't contain enough information, explicitly state what's missing
    5. If sources conflict, present both viewpoints with citations
    
    RESPONSE FORMAT:
    1. Start with a direct answer to the query
    2. Provide evidence from sources with inline citations [1], [2], etc.
    3. Use multiple citations if multiple sources support a claim
    4. End with exactly 3 follow-up questions based on the sources
    
    CITATION REQUIREMENTS:
    - Every factual statement must have a citation
    - Use exact source numbers provided
    - Multiple sources for same claim: use [1,3] or [2,4,5]
    - Quote directly when appropriate, with citation
    
    FOLLOW-UP QUESTIONS:
    - Must be answerable by searching for more information
    - Should explore aspects mentioned but not fully covered in sources
    - Format as a bulleted list at the end
    PROMPT
  end
  
  def build_user_prompt(context)
    parts = []
    
    # Query and optional fields
    parts << "QUERY: #{context[:query]}"
    parts << "USER GOAL: #{context[:goal]}" if context[:goal].present?
    parts << "CONSTRAINTS: #{context[:rules]}" if context[:rules].present?
    
    # Sources
    parts << "\nAVAILABLE SOURCES:"
    context[:sources].each do |source|
      parts << source[:text]
    end
    
    parts << "\nGenerate a comprehensive response using ONLY the information from these sources."
    
    parts.join("\n")
  end
  
  def parse_response(raw_response, sources)
    return nil if raw_response.blank?
    
    # Extract main response and follow-up questions
    response_parts = raw_response.split(/follow.?up questions?:?/i)
    main_response = response_parts[0].strip
    
    # Extract follow-up questions
    follow_up_text = response_parts[1] || ""
    follow_up_questions = extract_follow_up_questions(follow_up_text)
    
    # Extract citations
    citations = extract_citations_from_response(main_response, sources)
    
    {
      response: main_response,
      follow_up_questions: follow_up_questions,
      citations: citations
    }
  end
  
  def extract_follow_up_questions(text)
    questions = []
    
    # Look for bullet points or numbered lists
    lines = text.split("\n").map(&:strip)
    
    lines.each do |line|
      # Skip empty lines
      next if line.blank?
      
      # Check for question patterns
      if line =~ /^[-•*]\s*(.+\?)$/ || line =~ /^\d+[\.)]\s*(.+\?)$/
        questions << $1.strip
      elsif line.include?('?')
        # Clean up the line and add if it's a question
        cleaned = line.gsub(/^[-•*\d\.)]\s*/, '').strip
        questions << cleaned if cleaned.include?('?')
      end
    end
    
    # Return first 3 questions
    questions.first(3)
  end
  
  def extract_citations_from_response(response, sources)
    citations = []
    
    # Find all citation patterns [1], [2], [1,3], etc.
    response.scan(/\[(\d+(?:,\s*\d+)*)\]/) do |match|
      numbers = match[0].split(',').map(&:strip).map(&:to_i)
      
      numbers.each do |num|
        source = sources.find { |s| s[:number] == num }
        next unless source
        
        # Find the context around this citation
        citation_context = extract_citation_context(response, num)
        
        citations << {
          source_url: source[:document].url,
          source_title: source[:document].title,
          snippet: citation_context,
          search_result: source[:search_result],
          source_number: num
        }
      end
    end
    
    citations.uniq { |c| [c[:source_url], c[:snippet]] }
  end
  
  def extract_citation_context(response, source_number)
    # Find sentences containing this citation
    sentences = response.split(/(?<=[.!?])\s+/)
    
    matching_sentences = sentences.select do |sentence|
      sentence.include?("[#{source_number}]") || 
      sentence.match(/\[[\d,\s]*#{source_number}[\d,\s]*\]/)
    end
    
    return "Source #{source_number}" if matching_sentences.empty?
    
    # Return the first matching sentence, cleaned up
    matching_sentences.first.strip
  end
  
  def create_citations(citations_data)
    citations_data.each do |data|
      Citation.create!(
        search_result: data[:search_result],
        source_url: data[:source_url],
        snippet: data[:snippet][0...500] # Limit snippet length
      )
    end
    

    @metrics[:citations_created] = citations_data.length
  rescue => e
    Rails.logger.error "[ResponseGenerationService] Citation creation failed: #{e.message}"
  end

  def extract_content_from_openai(resp)
    return nil if resp.nil?
    # Chat Completions
    resp.dig('choices', 0, 'message', 'content') ||
    # Responses API (some SDKs)
    resp.dig('output_text') ||
    resp.dig('output', 'choices', 0, 'message', 'content')
  end

  def estimate_tokens(text)
    # Rough estimation: ~4 characters per token
    (text.length / 4.0).ceil
  end

  def retryable_openai_error?(error)
    error.message.to_s.match?(/Rate limit|timeout|temporarily|429|503/i)
  end

  def openai_client
    Rails.application.config.x.openai_client
  end

  def log_blank_response(data)
    msg_preview = data[:messages].to_a.map { |m| { role: m[:role], content: m[:content].to_s[0...500] } }
    Rails.logger.error(
      "[ResponseGenerationService] Blank AI response for search #{@search.id}. " \
      "sources_used=#{@metrics[:sources_used]} messages=#{msg_preview.inspect} raw_body=#{data[:raw_body].inspect}"
    )
  end

  def build_fallback_response(context)
    sources = context[:sources].first(3)
    response_lines = sources.map do |s|
      snippet = s[:document].cleaned_content.to_s[0...200].squish
      "#{snippet} [#{s[:number]}]"
    end
    follow_ups = sources.map { |s| "What more can we learn about #{s[:document].title}?" }
    while follow_ups.length < 3
      follow_ups << "What additional information is needed about #{@search.query}?"
    end
    follow_ups = follow_ups.first(3)
    citations = sources.map do |s|
      {
        source_url: s[:document].url,
        source_title: s[:document].title,
        snippet: s[:document].cleaned_content.to_s[0...200],
        search_result: s[:search_result],
        source_number: s[:number]
      }
    end
    {
      response: response_lines.join("\n"),
      follow_up_questions: follow_ups,
      citations: citations
    }
  end
end

