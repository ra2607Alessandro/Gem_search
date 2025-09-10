require_relative "../config/environment"
require 'json'

query = (ARGV.join(" ").presence || "ping")
Current.request_id = SecureRandom.uuid

s = Search.create!(query: query)
SearchProcessingJob.perform_now(s.id)

# Wait for content to be available (worker must be running)
min_sources = Ai::ResponseGenerationService::MIN_SOURCES_REQUIRED
deadline = Time.now + 30 # seconds
loop do
  s.reload
  break if s.documents.with_content.count >= min_sources
  break if Time.now > deadline
  sleep 0.5
end

if s.documents.with_content.count >= min_sources
  AiResponseGenerationJob.perform_now(s.id)
  s.reload
  summary = {
    id: s.id,
    status: s.status,
    error: s.error_message,
    follow_up_questions: s.follow_up_questions
  }
  puts JSON.pretty_generate(summary)
  puts "\nAI response:\n#{s.ai_response}\n"
else
  # Attempt a single fallback via snippets, then try AI once
  Scraping::ScrapingCompletionService.check(s.id)
  s.reload
  if s.documents.with_content.count >= min_sources
    AiResponseGenerationJob.perform_now(s.id)
    s.reload
  end
  summary = {
    id: s.id,
    status: s.status,
    error: s.error_message,
    content_sources: s.documents.with_content.count,
    follow_up_questions: s.follow_up_questions
  }
  puts JSON.pretty_generate(summary)
  puts "\nAI response:\n#{s.ai_response}\n"
end
