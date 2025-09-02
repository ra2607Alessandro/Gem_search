module SearchesHelper
  def status_badge_class(status)
    case status.to_sym
    when :completed
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
    when :processing
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800"
    when :failed
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800"
    when :pending
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800"
    else
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800"
    end
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
