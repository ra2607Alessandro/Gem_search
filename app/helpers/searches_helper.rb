module SearchesHelper
  def status_badge_class(status)
    case status.to_s
    when 'pending'
      'bg-gray-100 text-gray-700'
    when 'processing'
      'bg-blue-100 text-blue-700'
    when 'completed'
      'bg-green-100 text-green-700'
    when 'failed'
      'bg-red-100 text-red-700'
    else
      'bg-gray-100 text-gray-700'
    end
  end

  def search_status_class(status)
    status_badge_class(status)
  end

  def search_status_icon(status)
    case status.to_sym
    when :completed
      "✅"
    when :processing
      "🔄"
    when :failed
      "❌"
    when :pending
      "⏳"
    when :scraping
      "🕒"
    else
      "❓"
    end
  end

  def format_search_query(search)
    if search.query.length > 100
      "#{search.query[0..97]}..."
    else
      search.query
    end
  end

  def calculate_progress(search)
    case search.status.to_sym
    when :pending
      0
    when :processing
      # Estimate progress based on sources found
      sources_found = search.search_results.count
      max_sources = 10 # Expected maximum
      [(sources_found * 80 / max_sources.to_f).round, 80].min # Cap at 80% until completion
    when :completed
      100
    when :failed
      0
    else
      0
    end
  end
end
