require_relative "../config/environment"

query = (ARGV.join(" ").presence || "ping")
Current.request_id = SecureRandom.uuid

s = Search.create!(query: query)
SearchProcessingJob.perform_now(s.id)
puts({ id: s.id, status: s.status, error:  s.error_message}.inspect)